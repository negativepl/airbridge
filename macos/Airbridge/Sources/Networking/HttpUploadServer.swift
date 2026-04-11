import Foundation
import Network
import CryptoKit

// MARK: - HttpUploadServer

/// An actor that manages a minimal HTTP/1.1 upload server using `NWListener`.
///
/// Accepts file uploads via POST requests with raw body streaming.
/// Designed to run alongside the WebSocket server on a separate port.
public actor HttpUploadServer {

    // MARK: - Public Properties

    /// The port the listener is actually bound to.
    /// Set once the listener reaches the `ready` state.
    public private(set) var actualPort: UInt16?

    // MARK: - Callbacks

    /// Called when a complete file has been received (on actor context).
    public var onFileReceived: (@Sendable (String, String, String, Data) -> Void)?

    /// Called periodically as body bytes arrive.
    /// Marked nonisolated(unsafe) so it can be called from receive callbacks
    /// without hopping to the actor (which causes blocking).
    public nonisolated(unsafe) var onProgress: (@Sendable (String, Int, Int) -> Void)?

    /// Sets both callbacks at once.
    public func setCallbacks(
        onFileReceived: (@Sendable (String, String, String, Data) -> Void)?,
        onProgress: (@Sendable (String, Int, Int) -> Void)?
    ) {
        self.onFileReceived = onFileReceived
        self.onProgress = onProgress
    }

    // MARK: - Private State

    private let port: UInt16
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    /// Continuation used to signal that the listener reached `.ready`.
    private var readyContinuation: CheckedContinuation<Void, Error>?

    /// Files registered for outgoing download via `GET /send/{transferId}`.
    /// Keyed by transferId — Mac registers the file when it wants to send it
    /// to the phone, phone fetches via GET, callbacks fire as bytes leave.
    ///
    /// Inverting the HTTP direction here is what lets Mac → phone file send
    /// work without triggering the macOS Local Network Privacy check for
    /// outbound connections. The phone initiates the TCP (outbound from its
    /// side, Android has no LNP restriction), Mac only accepts incoming,
    /// which is always allowed.
    private var pendingOutgoingFiles: [String: PendingOutgoingFile] = [:]

    private struct PendingOutgoingFile {
        let fileURL: URL
        let filename: String
        let mimeType: String
        let onProgress: @Sendable (Int64, Int64) -> Void
        let onComplete: @Sendable (Bool) -> Void
    }

    // MARK: - Init

    public init(port: UInt16 = 8766) {
        self.port = port
    }

    // MARK: - Start / Stop

    /// Creates and starts the `NWListener` with plain TCP (no application protocol).
    /// Suspends until the listener is ready (or throws on failure).
    public func start() async throws {
        let parameters = NWParameters.tcp

        let nwPort: NWEndpoint.Port
        if port == 0 {
            nwPort = .any
        } else {
            guard let p = NWEndpoint.Port(rawValue: port) else {
                throw HttpUploadServerError.invalidPort(port)
            }
            nwPort = p
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleListenerStateChange(state, listener: listener)
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleNewConnection(connection)
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Stops the listener and cancels all active connections.
    public func stop() {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        actualPort = nil
        pendingOutgoingFiles.removeAll()
    }

    // MARK: - Outgoing File Registration

    /// Register a file to be served over `GET /send/{transferId}`.
    /// Call this BEFORE telling the remote peer to fetch. `onProgress` fires
    /// repeatedly with (bytesSent, totalBytes). `onComplete` fires once with
    /// success/failure. The registration is automatically removed after
    /// completion, so each call pairs with at most one GET.
    public func registerOutgoingFile(
        transferId: String,
        fileURL: URL,
        filename: String,
        mimeType: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (Bool) -> Void
    ) {
        pendingOutgoingFiles[transferId] = PendingOutgoingFile(
            fileURL: fileURL,
            filename: filename,
            mimeType: mimeType,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }

    /// Manually drop a pending outgoing file (e.g., on cancel).
    public func unregisterOutgoingFile(transferId: String) {
        pendingOutgoingFiles.removeValue(forKey: transferId)
    }

    // MARK: - Private — Listener State

    private func handleListenerStateChange(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            if let port = listener.port {
                actualPort = port.rawValue
            }
            let cont = readyContinuation
            readyContinuation = nil
            cont?.resume()

        case .failed(let error):
            let cont = readyContinuation
            readyContinuation = nil
            cont?.resume(throwing: error)

        default:
            break
        }
    }

    // MARK: - Private — Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { @Sendable [weak self] state in
            if case .failed = state { Task { [weak self] in guard let self else { return }; await self.removeConnection(id: id) } }
            if case .cancelled = state { Task { [weak self] in guard let self else { return }; await self.removeConnection(id: id) } }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receiveHTTPRequest(on: connection, buffer: Data())
    }

    private func removeConnection(id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
    }

    // MARK: - Private — HTTP Parsing

    /// Maximum allowed header block size (64 KB). Protects against oversized headers.
    private static let maxHeaderSize = 64 * 1024

    /// Separator between HTTP headers and body.
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    /// Reads data from the connection until the full HTTP header block is found,
    /// then hands off to body streaming.
    private nonisolated func receiveHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.sendErrorResponse(on: connection, status: 500, message: "Connection error: \(error)")
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            // Check for header terminator
            if let range = accumulated.range(of: HttpUploadServer.headerTerminator) {
                let headerData = accumulated[accumulated.startIndex..<range.lowerBound]
                let bodyPrefix = accumulated[range.upperBound...]

                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    self.sendErrorResponse(on: connection, status: 400, message: "Invalid header encoding")
                    return
                }

                Task {
                    await self.processRequest(
                        headerString: headerString,
                        bodyPrefix: Data(bodyPrefix),
                        connection: connection
                    )
                }
                return
            }

            // Guard against oversized headers
            if accumulated.count > HttpUploadServer.maxHeaderSize {
                self.sendErrorResponse(on: connection, status: 400, message: "Headers too large")
                return
            }

            if isComplete {
                self.sendErrorResponse(on: connection, status: 400, message: "Incomplete request")
                return
            }

            // Keep reading until we find the header terminator
            self.receiveHTTPRequest(on: connection, buffer: accumulated)
        }
    }

    /// Parses headers, validates the request, then streams the body.
    private func processRequest(
        headerString: String,
        bodyPrefix: Data,
        connection: NWConnection
    ) {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendErrorResponse(on: connection, status: 400, message: "Missing request line")
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendErrorResponse(on: connection, status: 400, message: "Malformed request line")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // GET /send/{transferId} — Mac serves a previously-registered file
        // to the phone. This is the INVERTED Mac→phone file transfer path
        // (see `pendingOutgoingFiles` docs for rationale).
        if method == "GET", path.hasPrefix("/send/") {
            let transferId = String(path.dropFirst("/send/".count))
            serveOutgoingFile(on: connection, transferId: transferId)
            return
        }

        guard method == "POST", path == "/upload" else {
            sendErrorResponse(on: connection, status: 400, message: "Expected POST /upload or GET /send/{id}")
            return
        }

        // Parse headers into a dictionary (case-insensitive keys)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        guard let contentLengthStr = headers["content-length"],
              let contentLength = Int(contentLengthStr), contentLength >= 0 else {
            sendErrorResponse(on: connection, status: 400, message: "Missing or invalid Content-Length")
            return
        }

        let filename: String
        if let raw = headers["x-filename"], let decoded = raw.removingPercentEncoding, !decoded.isEmpty {
            filename = decoded
        } else {
            sendErrorResponse(on: connection, status: 400, message: "Missing X-Filename header")
            return
        }

        let mimeType = headers["x-mime-type"] ?? "application/octet-stream"
        let expectedChecksum = headers["x-checksum-sha256"]

        // Stream the body
        streamBody(
            on: connection,
            filename: filename,
            mimeType: mimeType,
            expectedChecksum: expectedChecksum,
            contentLength: contentLength,
            accumulated: bodyPrefix
        )
    }

    // MARK: - Private — Body Streaming

    /// Recursively receives body data until `contentLength` bytes have been read.
    private nonisolated func streamBody(
        on connection: NWConnection,
        filename: String,
        mimeType: String,
        expectedChecksum: String?,
        contentLength: Int,
        accumulated: Data
    ) {
        // Report progress — call directly, not via actor hop
        let count = accumulated.count
        self.onProgress?(filename, count, contentLength)

        if accumulated.count >= contentLength {
            // We have all the data
            let fileData = accumulated.prefix(contentLength)
            Task {
                await self.finalizeUpload(
                    on: connection,
                    filename: filename,
                    mimeType: mimeType,
                    expectedChecksum: expectedChecksum,
                    data: Data(fileData)
                )
            }
            return
        }

        let remaining = contentLength - accumulated.count
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 1_048_576)) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.sendErrorResponse(on: connection, status: 500, message: "Receive error: \(error)")
                return
            }

            var updated = accumulated
            if let data {
                updated.append(data)
            }

            if isComplete && updated.count < contentLength {
                self.sendErrorResponse(on: connection, status: 400, message: "Connection closed before full body received")
                return
            }

            self.streamBody(
                on: connection,
                filename: filename,
                mimeType: mimeType,
                expectedChecksum: expectedChecksum,
                contentLength: contentLength,
                accumulated: updated
            )
        }
    }

    /// Verifies checksum (if provided), invokes callback, and sends HTTP response.
    private func finalizeUpload(
        on connection: NWConnection,
        filename: String,
        mimeType: String,
        expectedChecksum: String?,
        data: Data
    ) {
        let digest = SHA256.hash(data: data)
        let computedChecksum = digest.map { String(format: "%02x", $0) }.joined()

        if let expected = expectedChecksum, !expected.isEmpty {
            guard computedChecksum.lowercased() == expected.lowercased() else {
                sendErrorResponse(
                    on: connection,
                    status: 400,
                    message: "Checksum mismatch: expected \(expected), got \(computedChecksum)"
                )
                return
            }
        }

        onFileReceived?(filename, mimeType, computedChecksum, data)

        let json = "{\"status\":\"ok\",\"bytes_received\":\(data.count)}"
        sendResponse(on: connection, status: 200, statusText: "OK", body: json)
    }

    // MARK: - Private — HTTP Responses

    private nonisolated func sendResponse(
        on connection: NWConnection,
        status: Int,
        statusText: String,
        body: String
    ) {
        let bodyData = Data(body.utf8)
        let response = "HTTP/1.1 \(status) \(statusText)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"

        var payload = Data(response.utf8)
        payload.append(bodyData)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Private — Outgoing (GET /send/{id}) File Streaming

    /// Look up a registered outgoing file by transferId and stream it back
    /// to the connecting peer. Fires the file's onProgress/onComplete
    /// callbacks as bytes leave the box. Unregisters the entry on finish.
    private func serveOutgoingFile(on connection: NWConnection, transferId: String) {
        guard let pending = pendingOutgoingFiles[transferId] else {
            sendErrorResponse(on: connection, status: 404, message: "Unknown transferId")
            return
        }

        // Load the full file into memory. This mirrors how the POST /upload
        // path handles bodies (see `streamBody` which accumulates all bytes
        // before finalizing) — keeps the two paths symmetric. Real disk
        // streaming can be a later optimization if large-file users hit it.
        guard let data = try? Data(contentsOf: pending.fileURL) else {
            sendErrorResponse(on: connection, status: 500, message: "File read failed")
            pending.onComplete(false)
            pendingOutgoingFiles.removeValue(forKey: transferId)
            return
        }

        let total = Int64(data.count)
        let encodedFilename = pending.filename
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pending.filename
        let headers = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: \(pending.mimeType)\r\n"
            + "Content-Length: \(total)\r\n"
            + "X-Filename: \(encodedFilename)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        let headerData = Data(headers.utf8)

        // Capture the per-transfer callbacks so the nonisolated streaming
        // helper can invoke them without hopping back onto the actor for
        // every chunk. After capture, remove the registration — from here
        // on, only our local references matter.
        let onProgress = pending.onProgress
        let onComplete = pending.onComplete
        pendingOutgoingFiles.removeValue(forKey: transferId)

        // Send headers first, then kick off the chunk streamer.
        connection.send(content: headerData, completion: .contentProcessed { error in
            if error != nil {
                onComplete(false)
                connection.cancel()
                return
            }
            // Report 0% before any body bytes — lets the UI switch out of
            // "waiting for accept" into "transferring" immediately.
            onProgress(0, total)
            HttpUploadServer.streamOutgoingChunks(
                on: connection,
                data: data,
                sent: 0,
                total: total,
                onProgress: onProgress,
                onComplete: onComplete
            )
        })
    }

    /// Recursively sends `data` in 64 KB chunks and fires `onProgress` after
    /// each chunk. On final chunk, fires `onComplete(true)` and cancels the
    /// connection. On any send error, fires `onComplete(false)`.
    private static func streamOutgoingChunks(
        on connection: NWConnection,
        data: Data,
        sent: Int64,
        total: Int64,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (Bool) -> Void
    ) {
        if sent >= total {
            onComplete(true)
            connection.cancel()
            return
        }
        let chunkSize: Int64 = 64 * 1024
        let remaining = total - sent
        let size = Int(min(chunkSize, remaining))
        let start = Int(sent)
        let chunk = data.subdata(in: start..<(start + size))

        connection.send(content: chunk, completion: .contentProcessed { error in
            if error != nil {
                onComplete(false)
                connection.cancel()
                return
            }
            let newSent = sent + Int64(size)
            onProgress(newSent, total)
            HttpUploadServer.streamOutgoingChunks(
                on: connection,
                data: data,
                sent: newSent,
                total: total,
                onProgress: onProgress,
                onComplete: onComplete
            )
        })
    }

    // MARK: - Private — HTTP Responses (cont.)

    private nonisolated func sendErrorResponse(on connection: NWConnection, status: Int, message: String) {
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let json = "{\"status\":\"error\",\"message\":\"\(escapedMessage)\"}"
        let statusText: String
        switch status {
        case 400: statusText = "Bad Request"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Error"
        }
        sendResponse(on: connection, status: status, statusText: statusText, body: json)
    }
}

// MARK: - Errors

public enum HttpUploadServerError: Error {
    case invalidPort(UInt16)
}
