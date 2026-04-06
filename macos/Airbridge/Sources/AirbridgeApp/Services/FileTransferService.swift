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

    // MARK: - Private

    @ObservationIgnored private let fileChunker = FileChunker()
    @ObservationIgnored private var activeAssemblers: [String: FileAssembler] = [:]
    @ObservationIgnored private var transferStartTime: Date?
    @ObservationIgnored private weak var connectionService: ConnectionService?
    @ObservationIgnored private weak var historyService: HistoryService?
    @ObservationIgnored private var sendQueue: [URL] = []
    @ObservationIgnored private var isSendingFromQueue = false

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
        default:
            break
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

        let filename = url.lastPathComponent
        let mime = Self.mimeType(for: url)

        let identity: DeviceIdentity
        do {
            identity = try connectionService.keyManager.getOrCreateIdentity()
        } catch {
            isSendingFromQueue = false
            processQueue()
            return
        }

        let chunker = self.fileChunker
        Task {
            // Read file off main thread
            let data: Data? = await Task.detached { try? Data(contentsOf: url) }.value
            guard let data else {
                self.isSendingFromQueue = false
                self.processQueue()
                return
            }

            let chunked = chunker.prepare(
                filename: filename,
                mimeType: mime,
                data: data,
                sourceId: identity.deviceId
            )

            do {
                self.fileTransferFileName = filename
                try await connectionService.broadcast(chunked.startMessage)

                for chunk in chunked.chunks {
                    let msg = Message.fileChunk(
                        transferId: chunked.transferId,
                        chunkIndex: chunk.chunkIndex,
                        data: chunk.base64Data
                    )
                    try await connectionService.broadcast(msg)
                    self.fileTransferProgress = Double(chunk.chunkIndex + 1) / Double(chunked.totalChunks)
                }

                let completeMsg = Message.fileTransferComplete(
                    transferId: chunked.transferId,
                    checksumSHA256: chunked.checksumSHA256
                )
                try await connectionService.broadcast(completeMsg)

                self.fileTransferProgress = 0
                self.historyService?.add(type: .file, direction: .sent, description: filename)
                self.isSendingFromQueue = false
                self.processQueue()
            } catch {
                self.fileTransferProgress = 0
                self.isSendingFromQueue = false
                self.processQueue()
            }
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
        let folderPath = UserDefaults.standard.string(forKey: "downloadFolder") ?? "~/Downloads/Airbridge"
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
