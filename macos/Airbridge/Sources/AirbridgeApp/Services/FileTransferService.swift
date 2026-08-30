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
    /// A transfer ended abnormally (peer disconnected, timed out, or the
    /// upload stalled) — drives the island's transient failure state.
    private(set) var isFailed: Bool = false
    /// True between accepting an offer and the first byte of the upload
    /// landing. Without it the popup has nothing to show in that gap — the
    /// offer is gone and progress is still zero — so it fell through to the
    /// idle drop zone and flashed "Drop file here" at someone who had just
    /// accepted a file.
    private(set) var isAwaitingAcceptedTransfer = false

    private(set) var incomingOfferTransferId: String? = nil
    private(set) var incomingOfferFileSize: Int64 = 0
    var hasIncomingOffer: Bool { !pendingOffers.isEmpty }

    // MARK: - Private

    @ObservationIgnored private var transferStartTime: Date?
    @ObservationIgnored private weak var connectionService: ConnectionService?
    @ObservationIgnored private var sendQueue: [(url: URL, destinationDir: String?)] = []
    @ObservationIgnored private var isSendingFromQueue = false
    /// How the wait for an outgoing offer's answer ended. `.failed` covers
    /// everything that is not an explicit answer from the phone: the sender
    /// disconnecting, the last connection dropping, or the wait timing out.
    private enum OutgoingOfferResponse { case accepted, rejected, failed }
    @ObservationIgnored private var offerResponseStream: AsyncStream<OutgoingOfferResponse>.Continuation?
    /// transferId of the outgoing offer currently awaiting accept/reject, so
    /// `cancelPendingTransfer()` can tell the phone to drop its incoming-offer
    /// notification instead of leaving it to time out on its own.
    @ObservationIgnored private var pendingOutgoingTransferId: String? = nil
    /// connectionId of the device the pending outgoing offer targets, so a
    /// disconnect of THAT device (not any other phone) fails the wait.
    @ObservationIgnored private var pendingOutgoingConnectionId: String? = nil
    /// Wait-for-accept timeout for outgoing offers — mirrors the phone's own
    /// 60 s offer timeout. Internal so tests can shorten it.
    @ObservationIgnored var offerAcceptTimeout: TimeInterval = 60
    /// An accepted outgoing upload is considered dead after this long without
    /// a progress callback (the phone vanished between accepting and its GET,
    /// or mid-download). Internal so tests can shorten it.
    @ObservationIgnored var uploadStallTimeout: TimeInterval = 30
    /// Timestamp of the last outgoing-upload progress callback, watched by
    /// the stall watchdog in `sendSingleFile`.
    @ObservationIgnored private var lastOutgoingActivity = Date()
    /// All incoming offers awaiting one accept/reject (the phone can share many
    /// files at once — accept/reject must cover every offer, not just the last).
    /// Each offer remembers its originating connection so the accept/reject
    /// goes back to THAT phone, not to every connected device.
    ///
    /// Deliberately OBSERVED: `hasIncomingOffer` is derived from this array and
    /// is the first thing the popup reads, so while an offer is on screen it is
    /// the only dependency SwiftUI has recorded. Marking the array
    /// `@ObservationIgnored` meant answering the offer changed nothing the view
    /// was watching — the "Incoming file" pane stayed frozen until the hide
    /// timer fired, so rejecting looked like it did nothing at all.
    private var pendingOffers: [(transferId: String, fileSize: Int64, connectionId: String)] = []
    private var pendingOffersTotalSize: Int64 = 0
    /// "host|filename" of the upload that owns the transfer popup. With two
    /// phones uploading concurrently, only the owner drives the shared popup
    /// fields — the other transfer still lands on disk, just without fighting
    /// over the progress UI.
    @ObservationIgnored private var receivingOwnerKey: String? = nil
    /// transferIds we've already sent `.fileTransferAccept` for. `HttpUploadServer`
    /// has no per-transferId failure callback, so if the phone cancels AFTER
    /// acceptance (button, or a 60s-timeout race), `handleIncomingOfferCancelled`
    /// needs this set to know to reset the receive machine instead of treating
    /// the id as unknown (it's already been removed from `pendingOffers`).
    @ObservationIgnored private var acceptedIncomingTransferIds = Set<String>()
    /// Gdy ustawione, najbliższy przychodzący plik o tej nazwie idzie do cache
    /// podglądu (a nie do Downloads) i wywołuje completion z URL-em. Korelacja po
    /// nazwie wystarcza, bo apka prowadzi jeden transfer naraz.
    @ObservationIgnored private var pendingPreview: (filename: String, cacheURL: URL, onProgress: (Double) -> Void, completion: (URL?) -> Void)?
    /// A pending preview download is abandoned (completion(nil)) after this
    /// long without progress. Internal so tests can shorten it.
    @ObservationIgnored var previewStallTimeout: TimeInterval = 30
    /// Timestamp of the last preview progress callback, watched by the
    /// preview stall watchdog.
    @ObservationIgnored private var lastPreviewActivity = Date()
    /// Stall watchdog for the pending preview download. Cancelled whenever
    /// the preview resolves (file arrived, abort, explicit cancel).
    @ObservationIgnored private var previewWatchdogTask: Task<Void, Never>?

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
        Task {
            await setupHttpCallbacks()
        }
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        handleMessage(message, from: "")
    }

    func handleMessage(_ message: Message, from connectionId: String) {
        switch message {
        case .fileTransferOffer(let transferId, let filename, _, let fileSize, _):
            handleIncomingOffer(transferId: transferId, filename: filename, fileSize: fileSize, connectionId: connectionId)
        case .fileTransferAccept:
            offerResponseStream?.yield(.accepted)
            offerResponseStream?.finish()
            offerResponseStream = nil
        case .fileTransferReject:
            offerResponseStream?.yield(.rejected)
            offerResponseStream?.finish()
            offerResponseStream = nil
        case .fileTransferCancel(let transferId):
            handleIncomingOfferCancelled(transferId: transferId)
        default:
            break
        }
    }

    // MARK: - Incoming Offer (file from phone)

    private func handleIncomingOffer(transferId: String, filename: String, fileSize: Int64, connectionId: String) {
        // No withAnimation here — TransferPopupView has .animation(value:
        // stateKind) which catches state changes and animates them. Wrapping
        // in withAnimation creates a competing transaction that conflicts.
        // Accumulate offers — the phone can share several files at once, each
        // arriving as its own offer within milliseconds.
        pendingOffers.append((transferId, fileSize, connectionId))
        pendingOffersTotalSize += fileSize
        incomingOfferTransferId = transferId
        incomingOfferFileSize = pendingOffersTotalSize
        fileTransferFileName = pendingOffers.count > 1
            ? (L10n.isPL ? "\(pendingOffers.count) plików" : "\(pendingOffers.count) files")
            : filename
        isReceivingFile = true
        isWaitingForAccept = false
        isRejected = false
        fileTransferProgress = 0
        TransferPopup.shared.show()
    }

    func acceptIncomingOffer() {
        let offers = pendingOffers
        pendingOffers = []
        pendingOffersTotalSize = 0
        incomingOfferTransferId = nil
        // Nothing to accept (e.g. the offer was cleared by a dropped connection)
        // — don't strand the popup on screen; just dismiss it.
        guard !offers.isEmpty else {
            TransferPopup.shared.hide(delay: 0)
            return
        }
        isAwaitingAcceptedTransfer = true
        for offer in offers { acceptedIncomingTransferIds.insert(offer.transferId) }
        let connectionService = self.connectionService
        Task {
            for offer in offers {
                try? await connectionService?.sendTo(Message.fileTransferAccept(transferId: offer.transferId), connectionId: offer.connectionId)
            }
        }
        // Keep the popup visible — receive HTTP upload progress will replace it
    }

    /// The accepted upload has begun (or can no longer begin) — release the
    /// hold that keeps the island off the idle drop zone.
    func noteIncomingTransferStarted() {
        isAwaitingAcceptedTransfer = false
    }

    /// Seconds remaining, rounded UP: a transfer with a fraction of a second
    /// left has "1 s" left, not "0". Zero is reserved for "nothing left" and
    /// "no estimate" — the popup renders it as "calculating…", so truncating
    /// here used to blank the countdown exactly as a transfer finished.
    static func etaSeconds(remainingBytes: Int64, speed: Double) -> Int {
        guard speed > 0, remainingBytes > 0 else { return 0 }
        return Int((Double(remainingBytes) / speed).rounded(.up))
    }

    /// Whether enough time has passed to divide bytes by it. Kept low so a
    /// file that transfers in a few hundred milliseconds still gets an
    /// estimate instead of showing "calculating…" for its whole life.
    static func canEstimate(elapsed: TimeInterval) -> Bool { elapsed > 0.2 }

    func rejectIncomingOffer() {
        // Always dismiss locally, even if the offer state is already empty (a
        // dropped connection can clear it while the popup is still on screen).
        // The reject broadcast is best-effort over whatever connection exists.
        let offers = pendingOffers
        pendingOffers = []
        pendingOffersTotalSize = 0
        if !offers.isEmpty {
            let connectionService = self.connectionService
            Task {
                for offer in offers {
                    try? await connectionService?.sendTo(Message.fileTransferReject(transferId: offer.transferId), connectionId: offer.connectionId)
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
        isAwaitingAcceptedTransfer = false
        }
    }

    /// The connection dropped while an incoming offer was awaiting accept/reject.
    /// The HTTP upload can't arrive over a dead session, so clear the offer and
    /// dismiss the popup instead of leaving it orphaned (the bug where "Reject"
    /// appeared to do nothing after the connection died).
    func connectionLost() {
        // An outgoing offer can't be answered over a dead session either —
        // fail its wait instead of leaving the island stuck on "waiting".
        failPendingOutgoingWait()
        receivingOwnerKey = nil
        acceptedIncomingTransferIds.removeAll()
        // Released BEFORE the offer guard below: after an accept there is no
        // pending offer left, so an early return here would leave the island
        // waiting forever for an upload that can no longer arrive.
        isAwaitingAcceptedTransfer = false
        guard hasIncomingOffer else { return }
        pendingOffers = []
        pendingOffersTotalSize = 0
        incomingOfferTransferId = nil
        isWaitingForAccept = false
        isRejected = false
        fileTransferFileName = ""
        isReceivingFile = false
        isAwaitingAcceptedTransfer = false
        TransferPopup.shared.hide(delay: 0)
    }

    /// One device (of possibly several) disconnected: drop only ITS pending
    /// offers. Offers and uploads from the remaining phones stay untouched.
    func deviceDisconnected(connectionId: String) {
        // If the disconnected device is the one our outgoing offer targets,
        // its answer can never arrive — fail the wait now.
        if connectionId == pendingOutgoingConnectionId {
            failPendingOutgoingWait()
        }
        let remaining = pendingOffers.filter { $0.connectionId != connectionId }
        guard remaining.count != pendingOffers.count else { return }
        pendingOffers = remaining
        pendingOffersTotalSize = remaining.reduce(0) { $0 + $1.fileSize }
        incomingOfferTransferId = remaining.last?.transferId
        incomingOfferFileSize = pendingOffersTotalSize
        if remaining.isEmpty {
            isWaitingForAccept = false
            isRejected = false
            fileTransferFileName = ""
            isReceivingFile = false
        isAwaitingAcceptedTransfer = false
            TransferPopup.shared.hide(delay: 0)
        }
    }

    /// The sender (phone) cancelled an offer before we accepted/rejected it —
    /// its 60s wait for our response ran out, or the user tapped cancel while
    /// waiting. Drop just that offer and, if none remain, dismiss the popup.
    /// Mirrors deviceDisconnected's partial-removal logic below.
    private func handleIncomingOfferCancelled(transferId: String) {
        if acceptedIncomingTransferIds.remove(transferId) != nil {
            // The phone cancelled after we already accepted — either the
            // Cancel button or the 60s-timeout race on its side. The offer is
            // no longer in `pendingOffers` (accept clears it), and
            // `HttpUploadServer` has no per-transferId failure callback, so
            // reset the receive machine directly instead of leaving the
            // popup stranded mid-progress.
            receivingOwnerKey = nil
            isReceivingFile = false
        isAwaitingAcceptedTransfer = false
            transferStartTime = nil
            transferSpeed = 0
            transferEta = 0
            fileTransferProgress = 0
            fileTransferFileName = ""
            TransferPopup.shared.hide(delay: 0)
            return
        }
        let remaining = pendingOffers.filter { $0.transferId != transferId }
        guard remaining.count != pendingOffers.count else { return } // unknown id — ignore
        pendingOffers = remaining
        pendingOffersTotalSize = remaining.reduce(0) { $0 + $1.fileSize }
        incomingOfferTransferId = remaining.last?.transferId
        incomingOfferFileSize = pendingOffersTotalSize
        if remaining.isEmpty {
            isWaitingForAccept = false
            isRejected = false
            fileTransferFileName = ""
            isReceivingFile = false
        isAwaitingAcceptedTransfer = false
            TransferPopup.shared.hide(delay: 0)
        }
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
        if let transferId = pendingOutgoingTransferId {
            // Tell the phone to drop its incoming-offer notification instead
            // of leaving it to sit there until its own 60s timeout.
            let connectionService = self.connectionService
            Task { try? await connectionService?.sendToActive(Message.fileTransferCancel(transferId: transferId)) }
        }
        offerResponseStream?.yield(.rejected)
        offerResponseStream?.finish()
        offerResponseStream = nil
    }

    /// Ends the wait for an outgoing offer's answer with `.failed` (sender
    /// disconnected, all connections lost, or the wait timed out). No-op when
    /// nothing is being waited on.
    private func failPendingOutgoingWait() {
        offerResponseStream?.yield(.failed)
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
                self.isAwaitingAcceptedTransfer = false
        self.pendingOutgoingTransferId = transferId
        self.pendingOutgoingConnectionId = connectionService.activeDevice?.connectionId

        // Show the popup immediately in waiting state (idempotent — if the
        // user already opened it via Quick Drop, no new window is created)
        TransferPopup.shared.show()

        // Set up the response stream for the offer (accept/reject)
        // SYNCHRONOUSLY, before the async work below gets a chance to run —
        // a disconnect arriving in that window must find the continuation
        // already installed, or its `.failed` yield is lost and the wait
        // hangs forever.
        let stream = AsyncStream<OutgoingOfferResponse> { continuation in
            self.offerResponseStream = continuation
        }

        Task {
            // 1. Set up the HTTP completion stream (phone's GET finishes).
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
                    self.lastOutgoingActivity = Date()
                    let progress = total > 0 ? Double(sent) / Double(total) : 0
                    // Clamp away from 0 so the view state computation
                    // doesn't briefly return .idle between "waiting for
                    // accept" and the first progress tick.
                    self.fileTransferProgress = max(progress, 0.001)

                    if let start = self.transferStartTime {
                        let elapsed = Date().timeIntervalSince(start)
                        if Self.canEstimate(elapsed: elapsed) {
                            let speed = Double(sent) / elapsed
                            self.transferSpeed = speed
                            self.transferEta = Self.etaSeconds(
                                remainingBytes: total - sent, speed: speed
                            )
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

            // 4. Wait for accept/reject (non-blocking for MainActor). The
            //    phone answers within 60 s or never (it enforces the same
            //    timeout on its side) — a disconnected or unresponsive peer
            //    must not leave the island on "waiting" forever.
            let offerTimeout = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.offerAcceptTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.failPendingOutgoingWait()
            }
            // Stream finishing without a value (defensive) counts as failure.
            var response = OutgoingOfferResponse.failed
            for await r in stream {
                response = r
                break
            }
            offerTimeout.cancel()

            guard response == .accepted else {
                // Not sent — drop the pending outgoing file so a later GET
                // (e.g., a retrying stale client) can't accidentally pull it.
                await connectionService.httpServer.unregisterOutgoingFile(transferId: transferId)
                httpContinuation.finish()

                // Rejected/failed — let view-side animation handle the morph
                self.isWaitingForAccept = false
                self.pendingOutgoingTransferId = nil
                self.pendingOutgoingConnectionId = nil
                if response == .rejected {
                    self.isRejected = true
                } else {
                    self.isFailed = true
                }
                // Show rejection/failure for 2s then slide up. Hide animation
                // is 0.5s — total popup-visible time is 2.5s.
                TransferPopup.shared.hide(delay: 2.0)
                // Wait UNTIL the hide animation has fully completed AND the
                // NSWindow has been orderOut'd before resetting state. If we
                // reset earlier, SwiftUI re-renders the fading-out window
                // with idle content and the user sees "drop file here" flash
                // across the dying popup.
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                // No withAnimation — popup is already gone, no one observes
                self.isRejected = false
                self.isFailed = false
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
            self.pendingOutgoingTransferId = nil
            self.pendingOutgoingConnectionId = nil

            // 6. Wait for phone's GET to finish streaming. Mac's
            //    HttpUploadServer fires onComplete via httpContinuation
            //    when the last chunk lands (or on any transport error).
            //    HttpUploadServer has no failure signal for a GET that never
            //    arrives (phone died right after accepting) — a stall
            //    watchdog fails the wait when progress stops for too long.
            self.lastOutgoingActivity = Date()
            let stallTimeout = self.uploadStallTimeout
            let watchdog = Task { @MainActor [weak self] in
                let interval = max(0.05, min(5, stallTimeout / 3))
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    if Date().timeIntervalSince(self.lastOutgoingActivity) > stallTimeout {
                        httpContinuation.yield(false)
                        httpContinuation.finish()
                        return
                    }
                }
            }
            var success = false
            for await result in httpStream {
                success = result
                break
            }
            watchdog.cancel()

            if success {
                self.fileTransferProgress = 1.0
                self.playReceiveSound()
                TransferPopup.shared.hide()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            } else {
                // Transport error or stall — drop the registration so a late
                // GET can't fetch a transfer the UI already reported as
                // failed, then show the transient failure state.
                await connectionService.httpServer.unregisterOutgoingFile(transferId: transferId)
                self.fileTransferProgress = 0
                self.isFailed = true
                TransferPopup.shared.hide(delay: 2.0)
                // Same reset choreography as the rejected/failed offer branch.
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                self.isFailed = false
            }

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
        let onFileReceived: @Sendable (String, String, String, URL, String?, String) -> Void = { [weak self] filename, _, _, tempURL, destinationDir, senderHost in
            Task { @MainActor in
                guard let self else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                // Only the popup-owning upload drives the shared progress
                // fields; a concurrent upload from another phone still gets
                // saved below, it just doesn't touch the UI state.
                let ownerKey = "\(senderHost)|\(filename)"
                let ownsPopup = self.receivingOwnerKey == nil || self.receivingOwnerKey == ownerKey
                if ownsPopup {
                    self.fileTransferProgress = 1.0
                }
                // Keep `isReceivingFile = true` until the whole complete
                // sequence has played. Flipping it false here made the popup
                // briefly compute `.transferring(isReceiving: false)` → flash
                // "Wysyłam 100%", then `.complete(isReceiving: false)` → wrong
                // "Plik wysłany!" text. It's reset at the end with everything
                // else instead.

                if let preview = self.pendingPreview, preview.filename == filename {
                    self.pendingPreview = nil
                    self.previewWatchdogTask?.cancel()
                    self.previewWatchdogTask = nil
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
                } else if let rel = destinationDir,
                          let targetDir = MacFilesProvider().resolve(rel),
                          (try? targetDir.checkResourceIsReachable()) == true,
                          let safeDest = Self.uniqueDestination(in: targetDir, filename: filename) {
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: safeDest)
                        self.playReceiveSound()
                    } catch {
                        #if DEBUG
                        print("[FileTransferService] X-Destination-Dir save failed: \(error); falling back to Downloads")
                        #endif
                        // Move to custom dir failed — fall back to Downloads rather than silently deleting.
                        do {
                            let _ = try self.saveToDownloads(filename: filename, movingFrom: tempURL)
                            self.playReceiveSound()
                        } catch {
                            #if DEBUG
                            print("[FileTransferService] Downloads fallback also failed: \(error)")
                            #endif
                            try? FileManager.default.removeItem(at: tempURL)
                        }
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

                guard ownsPopup else { return }
                self.receivingOwnerKey = nil
                // Best-effort: this callback isn't keyed by transferId, so a
                // completed receive clears the whole accepted-set rather than
                // just its own entry — a stray late cancel for an id from an
                // already-finished multi-file batch is harmless (fresh UUID
                // per offer, so it can never collide with a live transfer).
                self.acceptedIncomingTransferIds.removeAll()
                TransferPopup.shared.hide()

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.fileTransferProgress = 0
                self.fileTransferFileName = ""
                self.isReceivingFile = false
                self.isAwaitingAcceptedTransfer = false
                // Fresh speed/ETA baseline for the next receive.
                self.transferStartTime = nil
                self.transferSpeed = 0
                self.transferEta = 0
            }
        }

        let onProgress: @Sendable (String, Int, Int, String) -> Void = { [weak self] filename, bytesReceived, totalBytes, senderHost in
            Task { @MainActor in
                guard let self else { return }
                let progress = totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0

                // Transfer-podgląd: postęp ląduje w oknie podglądu, BEZ globalnego popovera.
                if let preview = self.pendingPreview, preview.filename == filename {
                    self.lastPreviewActivity = Date()
                    preview.onProgress(progress)
                    return
                }

                // First upload to report progress claims the popup; a
                // concurrent upload from another phone runs headless until
                // the owner finishes.
                let ownerKey = "\(senderHost)|\(filename)"
                if self.receivingOwnerKey == nil {
                    self.receivingOwnerKey = ownerKey
                }
                guard self.receivingOwnerKey == ownerKey else { return }

                self.fileTransferFileName = filename
                self.fileTransferProgress = progress
                self.isAwaitingAcceptedTransfer = false

                if !self.isReceivingFile {
                    self.isReceivingFile = true
                    TransferPopup.shared.show()
                }
                // Set on the first progress tick, NOT inside the branch above:
                // the accept flow already flips isReceivingFile before any byte
                // arrives, which used to leave startTime forever nil — so speed
                // and ETA were never computed ("Remaining: calculating…").
                if self.transferStartTime == nil {
                    self.transferStartTime = Date()
                }

                if let start = self.transferStartTime {
                    let elapsed = Date().timeIntervalSince(start)
                    if Self.canEstimate(elapsed: elapsed) {
                        let speed = Double(bytesReceived) / elapsed
                        self.transferSpeed = speed
                        self.transferEta = Self.etaSeconds(
                            remainingBytes: Int64(totalBytes - bytesReceived), speed: speed
                        )
                    }
                }
            }
        }

        await connectionService.httpServer.setCallbacks(onFileReceived: onFileReceived, onProgress: onProgress)

        // The phone's HTTP upload was torn down mid-stream (connection error,
        // or the peer closing early) — HttpUploadServer has no transferId to
        // give us here, so correlate by the same "host|filename" owner key
        // the progress/completion callbacks use, and only reset state if this
        // upload actually owns the popup.
        connectionService.httpServer.onUploadAborted = { [weak self] filename, senderHost in
            Task { @MainActor in
                guard let self else { return }
                // A preview download never claims the popup (its progress is
                // routed to the preview window, see onProgress above), so its
                // abort is handled separately — otherwise the owner-key guard
                // below skips it and the preview spinner waits forever.
                if let preview = self.pendingPreview, preview.filename == filename {
                    self.pendingPreview = nil
                    self.previewWatchdogTask?.cancel()
                    self.previewWatchdogTask = nil
                    preview.completion(nil)
                    return
                }
                let ownerKey = "\(senderHost)|\(filename)"
                // nil owner + isReceivingFile covers aborts that land before
                // the first progress callback claimed the popup — the accept
                // flow already flipped isReceivingFile on, and it must not
                // stay stuck behind an owner key nobody ever set.
                let ownsPopup = self.receivingOwnerKey == ownerKey
                    || (self.receivingOwnerKey == nil && self.isReceivingFile)
                guard ownsPopup else { return }
                self.receivingOwnerKey = nil
                self.isReceivingFile = false
                self.isAwaitingAcceptedTransfer = false
                self.transferStartTime = nil
                self.transferSpeed = 0
                self.transferEta = 0
                self.fileTransferProgress = 0
                self.fileTransferFileName = ""
                TransferPopup.shared.hide(delay: 0)
            }
        }
    }

    // MARK: - Preview

    /// Następny przychodzący plik `filename` zapisz do `cacheURL` zamiast do Downloads
    /// i wywołaj `completion` (URL = sukces, nil = błąd). Nadpisuje wcześniejsze oczekiwanie.
    func requestPreview(filename: String, saveTo cacheURL: URL,
                        onProgress: @escaping (Double) -> Void,
                        completion: @escaping (URL?) -> Void) {
        previewWatchdogTask?.cancel()
        pendingPreview = (filename, cacheURL, onProgress, completion)
        // The phone may never start the upload (dropped mid-request) and
        // HttpUploadServer only reports aborts of uploads that already
        // delivered bytes — a stall watchdog covers the silent cases so the
        // preview spinner cannot wait forever.
        lastPreviewActivity = Date()
        let stallTimeout = previewStallTimeout
        previewWatchdogTask = Task { @MainActor [weak self] in
            let interval = max(0.05, min(5, stallTimeout / 3))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard let preview = self.pendingPreview, preview.filename == filename else { return }
                if Date().timeIntervalSince(self.lastPreviewActivity) > stallTimeout {
                    self.pendingPreview = nil
                    self.previewWatchdogTask = nil
                    preview.completion(nil)
                    return
                }
            }
        }
    }

    /// Anuluje oczekujący podgląd (np. gdy użytkownik zamknie okno przed pobraniem).
    func cancelPendingPreview() {
        pendingPreview = nil
        previewWatchdogTask?.cancel()
        previewWatchdogTask = nil
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

    /// Returns a non-colliding destination URL inside `dir` for `filename`,
    /// or `nil` when `filename` cannot be safely resolved inside `dir`
    /// (e.g. a path-traversal attempt like `"../../evil.sh"`).
    ///
    /// The sanitized leaf name is used for the dedup loop — only the last
    /// path component of the network-supplied name is ever written under `dir`.
    /// If `filename` already exists, appends " (n)" before the extension
    /// (e.g. "photo.jpg" → "photo (2).jpg") — mirrors Android's dedupedName.
    static func uniqueDestination(in dir: URL, filename: String) -> URL? {
        // Sanitize against path traversal: reduce to leaf, verify containment.
        guard let safeName = SafeFileName.sanitize(filename),
              SafeFileName.resolvedURL(in: dir, filename: safeName) != nil else {
            return nil
        }
        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var candidate = dir.appendingPathComponent(safeName)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
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

