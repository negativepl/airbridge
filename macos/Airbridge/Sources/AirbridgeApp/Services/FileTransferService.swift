import Foundation
import AppKit
import SwiftUI
import Protocol
import AirbridgeSecurity
import Networking

/// Handles file sending and receiving (both over HTTP), with progress tracking.
@Observable
@MainActor
final class FileTransferService: MessageHandler {

    // MARK: - Observable State

    private(set) var fileTransferProgress: Double = 0
    private(set) var fileTransferFileName: String = ""
    private(set) var isReceivingFile: Bool = false
    private(set) var transferSpeed: Double = 0
    private(set) var transferEta: Int = 0
    private(set) var isWaitingForAccept: Bool = false
    private(set) var isRejected: Bool = false
    private(set) var incomingOfferTransferId: String? = nil
    private(set) var incomingOfferFileSize: Int64 = 0
    var hasIncomingOffer: Bool { !pendingOfferIds.isEmpty }

    // MARK: - Private

    @ObservationIgnored private var transferStartTime: Date?
    @ObservationIgnored private weak var connectionService: ConnectionService?
    @ObservationIgnored private var sendQueue: [(url: URL, destinationDir: String?)] = []
    @ObservationIgnored private var isSendingFromQueue = false
    @ObservationIgnored private var offerResponseStream: AsyncStream<Bool>.Continuation?
    /// All incoming offers awaiting one accept/reject (the phone can share many
    /// files at once — accept/reject must cover every offer, not just the last).
    @ObservationIgnored private var pendingOfferIds: [String] = []
    @ObservationIgnored private var pendingOffersTotalSize: Int64 = 0
    /// Gdy ustawione, najbliższy przychodzący plik o tej nazwie idzie do cache
    /// podglądu (a nie do Downloads) i wywołuje completion z URL-em. Korelacja po
    /// nazwie wystarcza, bo apka prowadzi jeden transfer naraz.
    @ObservationIgnored private var pendingPreview: (filename: String, cacheURL: URL, onProgress: (Double) -> Void, completion: (URL?) -> Void)?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
        Task {
            await setupHttpCallbacks()
        }
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        switch message {
        case .fileTransferOffer(let transferId, let filename, _, let fileSize, _):
            handleIncomingOffer(transferId: transferId, filename: filename, fileSize: fileSize)
        case .fileTransferAccept:
            offerResponseStream?.yield(true)
            offerResponseStream?.finish()
            offerResponseStream = nil
        case .fileTransferReject:
            offerResponseStream?.yield(false)
            offerResponseStream?.finish()
            offerResponseStream = nil
        default:
            break
        }
    }

    // MARK: - Incoming Offer (file from phone)

    private func handleIncomingOffer(transferId: String, filename: String, fileSize: Int64) {
        // No withAnimation here — TransferPopupView has .animation(value:
        // stateKind) which catches state changes and animates them. Wrapping
        // in withAnimation creates a competing transaction that conflicts.
        // Accumulate offers — the phone can share several files at once, each
        // arriving as its own offer within milliseconds.
        pendingOfferIds.append(transferId)
        pendingOffersTotalSize += fileSize
        incomingOfferTransferId = transferId
        incomingOfferFileSize = pendingOffersTotalSize
        fileTransferFileName = pendingOfferIds.count > 1
            ? (L10n.isPL ? "\(pendingOfferIds.count) plików" : "\(pendingOfferIds.count) files")
            : filename
        isReceivingFile = true
        isWaitingForAccept = false
        isRejected = false
        fileTransferProgress = 0
        TransferPopup.shared.show()
    }

    func acceptIncomingOffer() {
        let ids = pendingOfferIds
        pendingOfferIds = []
        pendingOffersTotalSize = 0
        incomingOfferTransferId = nil
        // Nothing to accept (e.g. the offer was cleared by a dropped connection)
        // — don't strand the popup on screen; just dismiss it.
        guard !ids.isEmpty else {
            TransferPopup.shared.hide(delay: 0)
            return
        }
        let connectionService = self.connectionService
        Task {
            for id in ids {
                try? await connectionService?.broadcast(Message.fileTransferAccept(transferId: id))
            }
        }
        // Keep the popup visible — receive HTTP upload progress will replace it
    }

    func rejectIncomingOffer() {
        // Always dismiss locally, even if the offer state is already empty (a
        // dropped connection can clear it while the popup is still on screen).
        // The reject broadcast is best-effort over whatever connection exists.
        let ids = pendingOfferIds
        pendingOfferIds = []
        pendingOffersTotalSize = 0
        if !ids.isEmpty {
            let connectionService = self.connectionService
            Task {
                for id in ids {
                    try? await connectionService?.broadcast(Message.fileTransferReject(transferId: id))
                }
            }
        }
        incomingOfferTransferId = nil
        isRejected = true
        Task {
            // Keep rejected state visible for 2s, then hide (0.5s animation)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            TransferPopup.shared.hide(delay: 0)
            // Wait for hide animation + buffer so state reset happens AFTER
            // the window is fully orderOut'd — otherwise the idle "drop file
            // here" content flashes during the fade.
            try? await Task.sleep(nanoseconds: 800_000_000)
            isRejected = false
            fileTransferFileName = ""
            isReceivingFile = false
        }
    }

    /// The connection dropped while an incoming offer was awaiting accept/reject.
    /// The HTTP upload can't arrive over a dead session, so clear the offer and
    /// dismiss the popup instead of leaving it orphaned (the bug where "Reject"
    /// appeared to do nothing after the connection died).
    func connectionLost() {
        guard hasIncomingOffer else { return }
        pendingOfferIds = []
        pendingOffersTotalSize = 0
        incomingOfferTransferId = nil
        isWaitingForAccept = false
        isRejected = false
        fileTransferFileName = ""
        isReceivingFile = false
        TransferPopup.shared.hide(delay: 0)
    }

    // MARK: - Sending

    func sendFile(url: URL, destinationDir: String? = nil) {
        sendQueue.append((url, destinationDir))
        processQueue()
    }

    /// Cancel a pending offer that's waiting for accept/reject.
    /// Triggers the same path as a rejection.
    func cancelPendingTransfer() {
        guard isWaitingForAccept else { return }
        offerResponseStream?.yield(false)
        offerResponseStream?.finish()
        offerResponseStream = nil
    }

    private func processQueue() {
        guard !isSendingFromQueue, !sendQueue.isEmpty else { return }
        isSendingFromQueue = true
        let item = sendQueue.removeFirst()
        sendSingleFile(url: item.url, destinationDir: item.destinationDir)
    }

    private func sendSingleFile(url: URL, destinationDir: String?) {
        guard let connectionService else {
            isSendingFromQueue = false
            processQueue()
            return
        }

        let filename = url.lastPathComponent
        let mime = Self.mimeType(for: url)
        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let transferId = UUID().uuidString

        // No withAnimation — view-side .animation(value: stateKind) handles
        // it. Wrapping here creates a competing transaction.
        self.fileTransferFileName = filename
        self.fileTransferProgress = 0
        self.isWaitingForAccept = true
        self.isRejected = false
        self.isReceivingFile = false

        // Show the popup immediately in waiting state (idempotent — if the
        // user already opened it via Quick Drop, no new window is created)
        TransferPopup.shared.show()

        Task {
            // 1. Set up response stream for the offer (accept/reject) and
            //    the HTTP completion stream (phone's GET finishes).
            let stream = AsyncStream<Bool> { continuation in
                self.offerResponseStream = continuation
            }
            let (httpStream, httpContinuation) = AsyncStream<Bool>.makeStream()

            // 2. Register the file with Mac's HttpUploadServer BEFORE sending
            //    the offer. CRITICAL: the phone immediately does a GET after
            //    sending back FileTransferAccept, so by the time the GET
            //    arrives on Mac's listener, the file MUST already be in
            //    `pendingOutgoingFiles`. Registering after accept creates a
            //    race where the GET hits 404 (we observed this in testing —
            //    "Unknown transferId" within ~80ms of Android's GET).
            let onProgress: @Sendable (Int64, Int64) -> Void = { [weak self] sent, total in
                Task { @MainActor in
                    guard let self else { return }
                    let progress = total > 0 ? Double(sent) / Double(total) : 0
                    // Clamp away from 0 so the view state computation
                    // doesn't briefly return .idle between "waiting for
                    // accept" and the first progress tick.
                    self.fileTransferProgress = max(progress, 0.001)

                    if let start = self.transferStartTime {
                        let elapsed = Date().timeIntervalSince(start)
                        if elapsed > 0.5 {
                            let speed = Double(sent) / elapsed
                            self.transferSpeed = speed
                            let remaining = total - sent
                            self.transferEta = speed > 0 ? Int(Double(remaining) / speed) : 0
                        }
                    }
                }
            }
            let onComplete: @Sendable (Bool) -> Void = { ok in
                httpContinuation.yield(ok)
                httpContinuation.finish()
            }
            await connectionService.httpServer.registerOutgoingFile(
                transferId: transferId,
                fileURL: url,
                filename: filename,
                mimeType: mime,
                onProgress: onProgress,
                onComplete: onComplete
            )

            // 3. Send offer to the active device only (accept/reject below stay
            //    broadcast — those answer an offer a phone sent us, and must reach
            //    that phone regardless of which one is active).
            let offer = Message.fileTransferOffer(transferId: transferId, filename: filename, mimeType: mime, fileSize: fileSize, destinationDir: destinationDir)
            try? await connectionService.sendToActive(offer)

            // 4. Wait for accept/reject (non-blocking for MainActor)
            var accepted = false
            for await response in stream {
                accepted = response
                break
            }

            guard accepted else {
                // Rejected — drop the pending outgoing file so a later GET
                // (e.g., a retrying stale client) can't accidentally pull it.
                await connectionService.httpServer.unregisterOutgoingFile(transferId: transferId)
                httpContinuation.finish()

                // Rejected — let view-side animation handle the morph
                self.isWaitingForAccept = false
                self.isRejected = true
                // Show rejection for 2s then slide up. Hide animation is
                // 0.5s — total popup-visible time is 2.5s.
                TransferPopup.shared.hide(delay: 2.0)
                // Wait UNTIL the hide animation has fully completed AND the
                // NSWindow has been orderOut'd before resetting state. If we
                // reset earlier, SwiftUI re-renders the fading-out window
                // with idle content and the user sees "drop file here" flash
                // across the dying popup.
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                // No withAnimation — popup is already gone, no one observes
                self.isRejected = false
                self.fileTransferProgress = 0
                self.fileTransferFileName = ""
                self.isSendingFromQueue = false
                self.processQueue()
                return
            }

            // 5. Accepted — switch directly into transferring state.
            // CRITICAL: set progress to a tiny non-zero value BEFORE
            // clearing isWaitingForAccept. Otherwise the state computation
            // briefly returns .idle (no waiting + no progress + nothing
            // else active) and the user sees "drop file here" flash before
            // the upload starts producing progress callbacks.
            self.fileTransferProgress = 0.001
            self.transferStartTime = Date()
            self.transferSpeed = 0
            self.transferEta = 0
            self.isWaitingForAccept = false

            // 6. Wait for phone's GET to finish streaming. Mac's
            //    HttpUploadServer fires onComplete via httpContinuation
            //    when the last chunk lands (or on any transport error).
            var success = false
            for await result in httpStream {
                success = result
                break
            }

            if success {
                self.fileTransferProgress = 1.0
                self.playReceiveSound()
                TransferPopup.shared.hide()
            } else {
                self.fileTransferProgress = 0
                TransferPopup.shared.hide()
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.fileTransferProgress = 0
            self.fileTransferFileName = ""
            self.isSendingFromQueue = false
            self.processQueue()
        }
    }

    // MARK: - HTTP Upload Callbacks

    private func setupHttpCallbacks() async {
        guard let connectionService else { return }

        // The server hands over a temp file URL (ownership included — we must
        // move or delete it). Streaming to disk on the server side keeps
        // multi-GB uploads out of RAM; here we only move files around.
        let onFileReceived: @Sendable (String, String, String, URL) -> Void = { [weak self] filename, _, _, tempURL in
            Task { @MainActor in
                guard let self else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                self.fileTransferProgress = 1.0
                // Keep `isReceivingFile = true` until the whole complete
                // sequence has played. Flipping it false here made the popup
                // briefly compute `.transferring(isReceiving: false)` → flash
                // "Wysyłam 100%", then `.complete(isReceiving: false)` → wrong
                // "Plik wysłany!" text. It's reset at the end with everything
                // else instead.

                if let preview = self.pendingPreview, preview.filename == filename {
                    self.pendingPreview = nil
                    do {
                        try FileManager.default.createDirectory(
                            at: preview.cacheURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: preview.cacheURL.path) {
                            try FileManager.default.removeItem(at: preview.cacheURL)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: preview.cacheURL)
                        self.playReceiveSound()
                        preview.completion(preview.cacheURL)
                    } catch {
                        #if DEBUG
                        print("[FileTransferService] preview cache save failed: \(error)")
                        #endif
                        try? FileManager.default.removeItem(at: tempURL)
                        preview.completion(nil)
                    }
                } else {
                    do {
                        let _ = try self.saveToDownloads(filename: filename, movingFrom: tempURL)
                        self.playReceiveSound()
                    } catch {
                        #if DEBUG
                        print("[FileTransferService] HTTP file save failed: \(error)")
                        #endif
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }

                TransferPopup.shared.hide()

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.fileTransferProgress = 0
                self.fileTransferFileName = ""
                self.isReceivingFile = false
            }
        }

        let onProgress: @Sendable (String, Int, Int) -> Void = { [weak self] filename, bytesReceived, totalBytes in
            Task { @MainActor in
                guard let self else { return }
                let progress = totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0

                // Transfer-podgląd: postęp ląduje w oknie podglądu, BEZ globalnego popovera.
                if let preview = self.pendingPreview, preview.filename == filename {
                    preview.onProgress(progress)
                    return
                }

                self.fileTransferFileName = filename
                self.fileTransferProgress = progress

                if !self.isReceivingFile {
                    self.isReceivingFile = true
                    self.transferStartTime = Date()
                    TransferPopup.shared.show()
                }

                if let start = self.transferStartTime {
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed > 0.5 {
                        let speed = Double(bytesReceived) / elapsed
                        self.transferSpeed = speed
                        let remaining = totalBytes - bytesReceived
                        self.transferEta = speed > 0 ? Int(Double(remaining) / speed) : 0
                    }
                }
            }
        }

        await connectionService.httpServer.setCallbacks(onFileReceived: onFileReceived, onProgress: onProgress)
    }

    // MARK: - Preview

    /// Następny przychodzący plik `filename` zapisz do `cacheURL` zamiast do Downloads
    /// i wywołaj `completion` (URL = sukces, nil = błąd). Nadpisuje wcześniejsze oczekiwanie.
    func requestPreview(filename: String, saveTo cacheURL: URL,
                        onProgress: @escaping (Double) -> Void,
                        completion: @escaping (URL?) -> Void) {
        pendingPreview = (filename, cacheURL, onProgress, completion)
    }

    /// Anuluje oczekujący podgląd (np. gdy użytkownik zamknie okno przed pobraniem).
    func cancelPendingPreview() {
        pendingPreview = nil
    }

    /// Kopiuje już pobrany plik (np. z cache podglądu) do Downloads — bez ponownego transferu.
    @discardableResult
    func saveToDownloads(fileAt sourceURL: URL, filename: String) -> URL? {
        do {
            let fileURL = try downloadsDestination(filename: filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            // Copy on the filesystem — never pull the file through RAM.
            try FileManager.default.copyItem(at: sourceURL, to: fileURL)
            playReceiveSound()
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - File Saving

    /// Resolves (and creates) the destination in the configured Downloads folder.
    private func downloadsDestination(filename: String) throws -> URL {
        let folderPath = UserDefaults.standard.string(forKey: "downloadFolder") ?? "~/Downloads/AirBridge"
        let expandedPath = NSString(string: folderPath).expandingTildeInPath
        let downloadsURL = URL(fileURLWithPath: expandedPath)
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        // Filename comes from the network — sanitize against path traversal.
        guard let fileURL = SafeFileName.resolvedURL(in: downloadsURL, filename: filename) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return fileURL
    }

    /// Moves an already-downloaded temp file into Downloads (no RAM round-trip).
    private func saveToDownloads(filename: String, movingFrom tempURL: URL) throws -> URL {
        let fileURL = try downloadsDestination(filename: filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }

    private func playReceiveSound() {
        guard UserDefaults.standard.bool(forKey: "playSound") else { return }
        if let url = AppResources.bundle.url(forResource: "airdrop", withExtension: "mp3") {
            let sound = NSSound(contentsOf: url, byReference: true)
            sound?.play()
        }
    }

    // MARK: - MIME Type

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "zip": return "application/zip"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "doc", "docx": return "application/msword"
        default: return "application/octet-stream"
        }
    }
}

