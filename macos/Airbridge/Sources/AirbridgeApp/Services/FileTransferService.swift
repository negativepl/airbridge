import Foundation
import AppKit
import Protocol
import AirbridgeSecurity
import FileTransfer
import Networking

/// Handles file sending (chunking) and receiving (HTTP upload), with progress tracking.
@Observable
@MainActor
final class FileTransferService: MessageHandler, BinaryChunkHandler {

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
    var hasIncomingOffer: Bool { incomingOfferTransferId != nil }

    // MARK: - Private

    @ObservationIgnored private let fileChunker = FileChunker()
    @ObservationIgnored private var activeAssemblers: [String: FileAssembler] = [:]
    @ObservationIgnored private var transferStartTime: Date?
    @ObservationIgnored private weak var connectionService: ConnectionService?
    @ObservationIgnored private weak var historyService: HistoryService?
    @ObservationIgnored private var sendQueue: [URL] = []
    @ObservationIgnored private var isSendingFromQueue = false
    @ObservationIgnored private var offerResponseStream: AsyncStream<Bool>.Continuation?

    func configure(connectionService: ConnectionService, historyService: HistoryService) {
        self.connectionService = connectionService
        self.historyService = historyService
        Task {
            await setupHttpCallbacks()
        }
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        switch message {
        case .fileTransferStart(_, let transferId, let filename, _, let totalSize, let totalChunks):
            handleFileTransferStart(transferId: transferId, filename: filename, totalSize: totalSize, totalChunks: totalChunks)
        case .fileChunk(let transferId, let chunkIndex, let data):
            handleFileChunk(transferId: transferId, chunkIndex: chunkIndex, data: data)
        case .fileTransferComplete(let transferId, let checksumSHA256):
            handleFileTransferComplete(transferId: transferId, checksum: checksumSHA256)
        case .fileTransferOffer(let transferId, let filename, _, let fileSize):
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
        incomingOfferTransferId = transferId
        incomingOfferFileSize = fileSize
        fileTransferFileName = filename
        isReceivingFile = true
        isWaitingForAccept = false
        isRejected = false
        fileTransferProgress = 0
        TransferPopup.shared.show(fileTransferService: self)
    }

    func acceptIncomingOffer() {
        guard let transferId = incomingOfferTransferId else { return }
        let connectionService = self.connectionService
        Task {
            try? await connectionService?.broadcast(Message.fileTransferAccept(transferId: transferId))
        }
        // Reset offer state — actual upload will arrive via HTTP and trigger the receive flow
        incomingOfferTransferId = nil
        // Keep the popup visible — receive HTTP upload progress will replace it
    }

    func rejectIncomingOffer() {
        guard let transferId = incomingOfferTransferId else { return }
        let connectionService = self.connectionService
        Task {
            try? await connectionService?.broadcast(Message.fileTransferReject(transferId: transferId))
        }
        incomingOfferTransferId = nil
        isRejected = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            TransferPopup.shared.hide(delay: 0)
            try? await Task.sleep(nanoseconds: 400_000_000)
            isRejected = false
            fileTransferFileName = ""
            isReceivingFile = false
        }
    }

    // MARK: - BinaryChunkHandler

    func handleBinaryChunk(_ data: Data) {
        guard data.count > 40 else { return }
        let transferId = String(data: data[0..<36], encoding: .ascii) ?? ""
        let chunkIndex = Int(data[36]) << 24 | Int(data[37]) << 16 | Int(data[38]) << 8 | Int(data[39])
        let chunkData = data[40...]

        guard let assembler = activeAssemblers[transferId] else { return }
        assembler.addChunk(index: chunkIndex, data: Data(chunkData))
        fileTransferProgress = assembler.progress

        Task {
            try? await connectionService?.broadcast(
                Message.fileChunkAck(transferId: transferId, chunkIndex: chunkIndex)
            )
        }
    }

    // MARK: - Sending

    func sendFile(url: URL) {
        sendQueue.append(url)
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
        let url = sendQueue.removeFirst()
        sendSingleFile(url: url)
    }

    private func sendSingleFile(url: URL) {
        guard let connectionService else {
            isSendingFromQueue = false
            processQueue()
            return
        }

        guard let rawHost = connectionService.getConnectedClientIP() else {
            isSendingFromQueue = false
            processQueue()
            return
        }
        // Sanitize host: strip Network.framework prefixes like "IPv4#abcd1234"
        // and extract a clean dotted-decimal IPv4 if possible.
        let host: String = {
            // If contains "#", assume "IPv4#hex" and decode
            if let hashIdx = rawHost.firstIndex(of: "#") {
                let hexPart = String(rawHost[rawHost.index(after: hashIdx)...])
                if let intVal = UInt32(hexPart, radix: 16) {
                    let a = (intVal >> 24) & 0xff
                    let b = (intVal >> 16) & 0xff
                    let c = (intVal >> 8) & 0xff
                    let d = intVal & 0xff
                    return "\(a).\(b).\(c).\(d)"
                }
            }
            return rawHost
        }()
        #if DEBUG
        print("[FileTransferService] Upload host: \(host) (raw: \(rawHost))")
        #endif

        let filename = url.lastPathComponent
        let mime = Self.mimeType(for: url)
        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let transferId = UUID().uuidString

        self.fileTransferFileName = filename
        self.fileTransferProgress = 0
        self.isWaitingForAccept = true
        self.isRejected = false
        self.isReceivingFile = false

        // Show the popup immediately in waiting state
        TransferPopup.shared.show(fileTransferService: self)

        Task {
            // 1. Set up response stream before sending offer
            let stream = AsyncStream<Bool> { continuation in
                self.offerResponseStream = continuation
            }

            // 2. Send offer
            let offer = Message.fileTransferOffer(transferId: transferId, filename: filename, mimeType: mime, fileSize: fileSize)
            try? await connectionService.broadcast(offer)

            // 3. Wait for accept/reject (non-blocking for MainActor)
            var accepted = false
            for await response in stream {
                accepted = response
                break
            }

            guard accepted else {
                // Rejected — animate rejection in popup, then hide (no extra delay)
                self.isWaitingForAccept = false
                self.isRejected = true
                // Show rejection for 2s then slide up
                TransferPopup.shared.hide(delay: 2.0)
                // Wait for slide-up animation to finish before clearing state
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                self.isRejected = false
                self.fileTransferProgress = 0
                self.fileTransferFileName = ""
                self.isSendingFromQueue = false
                self.processQueue()
                return
            }

            // 4. Accepted — switch state, popup is already showing
            self.isWaitingForAccept = false

            let success = await Self.httpUpload(
                fileURL: url,
                filename: filename,
                mimeType: mime,
                host: host,
                port: 8767
            ) { progress in
                Task { @MainActor in
                    self.fileTransferProgress = progress
                }
            }

            if success {
                self.fileTransferProgress = 1.0
                self.historyService?.add(type: .file, direction: .sent, description: filename)
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

    private static func httpUpload(
        fileURL: URL,
        filename: String,
        mimeType: String,
        host: String,
        port: Int,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename

        guard let url = URL(string: "http://\(host):\(port)/upload") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(encodedFilename, forHTTPHeaderField: "X-Filename")
        request.setValue(mimeType, forHTTPHeaderField: "X-Mime-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.upload(for: request, from: data, delegate: delegate)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Receiving (WebSocket chunks)

    private func handleFileTransferStart(transferId: String, filename: String, totalSize: Int, totalChunks: Int) {
        let assembler = FileAssembler(
            transferId: transferId,
            filename: filename,
            totalSize: totalSize,
            totalChunks: totalChunks,
            checksumSHA256: ""
        )
        activeAssemblers[transferId] = assembler
        fileTransferProgress = 0
        fileTransferFileName = filename
    }

    private func handleFileChunk(transferId: String, chunkIndex: Int, data: String) {
        guard let assembler = activeAssemblers[transferId],
              let chunkData = Data(base64Encoded: data) else { return }
        assembler.addChunk(index: chunkIndex, data: chunkData)
        fileTransferProgress = assembler.progress

        Task {
            try? await connectionService?.broadcast(
                Message.fileChunkAck(transferId: transferId, chunkIndex: chunkIndex)
            )
        }
    }

    private func handleFileTransferComplete(transferId: String, checksum: String) {
        guard let assembler = activeAssemblers.removeValue(forKey: transferId) else { return }
        saveReceivedFile(assembler: assembler)
    }

    // MARK: - HTTP Upload Callbacks

    private func setupHttpCallbacks() async {
        guard let connectionService else { return }

        let onFileReceived: @Sendable (String, String, String, Data) -> Void = { [weak self] filename, _, _, data in
            Task { @MainActor in
                guard let self else { return }
                self.fileTransferProgress = 1.0
                self.isReceivingFile = false

                do {
                    let _ = try self.saveToDownloads(filename: filename, data: data)
                    self.playReceiveSound()
                    self.historyService?.add(type: .file, direction: .received, description: filename)
                } catch {
                    #if DEBUG
                    print("[FileTransferService] HTTP file save failed: \(error)")
                    #endif
                }

                TransferPopup.shared.hide()

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.fileTransferProgress = 0
                self.fileTransferFileName = ""
            }
        }

        let onProgress: @Sendable (String, Int, Int) -> Void = { [weak self] filename, bytesReceived, totalBytes in
            Task { @MainActor in
                guard let self else { return }
                self.fileTransferFileName = filename
                let progress = totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0
                self.fileTransferProgress = progress

                if !self.isReceivingFile {
                    self.isReceivingFile = true
                    self.transferStartTime = Date()
                    TransferPopup.shared.show(fileTransferService: self)
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

    // MARK: - File Saving

    private func saveReceivedFile(assembler: FileAssembler) {
        do {
            let data = try assembler.assemble()
            let fileURL = try saveToDownloads(filename: assembler.filename, data: data)
            fileTransferProgress = 0
            playReceiveSound()
            historyService?.add(type: .file, direction: .received, description: assembler.filename)
        } catch {
            fileTransferProgress = 0
        }
    }

    private func saveToDownloads(filename: String, data: Data) throws -> URL {
        let folderPath = UserDefaults.standard.string(forKey: "downloadFolder") ?? "~/Downloads/AirBridge"
        let expandedPath = NSString(string: folderPath).expandingTildeInPath
        let downloadsURL = URL(fileURLWithPath: expandedPath)
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        let fileURL = downloadsURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func playReceiveSound() {
        guard UserDefaults.standard.bool(forKey: "playSound") else { return }
        if let url = Bundle.module.url(forResource: "airdrop", withExtension: "mp3") {
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

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @Sendable @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(progress)
    }
}
