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
    /// Arguments: filename, mimeType, SHA-256 hex checksum, and the URL of a
    /// temporary file holding the uploaded bytes. The callback OWNS the temp
    /// file — it must move or delete it.
    public var onFileReceived: (@Sendable (String, String, String, URL) -> Void)?

    /// Called periodically as body bytes arrive.
    /// Marked nonisolated(unsafe) so it can be called from receive callbacks
    /// without hopping to the actor (which causes blocking).
    public nonisolated(unsafe) var onProgress: (@Sendable (String, Int, Int) -> Void)?

    /// Sets both callbacks at once.
    public func setCallbacks(
        onFileReceived: (@Sendable (String, String, String, URL) -> Void)?,
        onProgress: (@Sendable (String, Int, Int) -> Void)?
    ) {
        self.onFileReceived = onFileReceived
        self.onProgress = onProgress
    }

    /// Validator deciding whether an incoming connection's remote host
    /// (e.g. "192.168.1.7") is allowed to talk to this server. Connections
    /// from any other host are dropped before a single request byte is read.
    /// While `nil` (validator not installed yet), ALL connections are
    /// rejected — an unconfigured server accepts nobody.
    private var isAllowedSender: (@Sendable (String) -> Bool)?

    /// Installs the sender validator (see `isAllowedSender`).
    public func setSenderValidator(_ validator: (@Sendable (String) -> Bool)?) {
        self.isAllowedSender = validator
    }

    /// Normalizes a host string for comparison: strips the IPv6 zone index
    /// ("%en0") and lowercases.
    public static func normalizeHost(_ host: String) -> String {
        let stripped = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        return stripped.lowercased()
    }

    // MARK: - Private State

    private let port: UInt16
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    /// Continuation used to signal that the listener reached `.ready`.
    private var readyContinuation: CheckedContinuation<Void, Error>?

    /// Continuation used to signal that the listener reached `.cancelled`.
    private var stopContinuation: CheckedContinuation<Void, Never>?

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
    /// Suspends until the listener has fully cancelled and released its port,
    /// so a subsequent `start()` can re-bind without hitting "address in use".
    public func stop() async {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        actualPort = nil
        pendingOutgoingFiles.removeAll()
        guard let listener else { return }
        self.listener = nil
        // If the listener already reached .cancelled on its own (e.g. after a
        // failure), no further stateUpdateHandler call will arrive — waiting
        // on a continuation here would hang forever.
        if case .cancelled = listener.state { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.stopContinuation = continuation
            listener.cancel()
        }
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
            // A cancelled listener may surface .failed instead of .cancelled;
            // at that point the stop is effectively done — release any waiter
            // so stop() cannot hang.
            let stopCont = stopContinuation
            stopContinuation = nil
            stopCont?.resume()

        case .cancelled:
            // stop() arrived while start() was still waiting for .ready:
            // the start did not succeed, so fail it instead of leaking it.
            let readyCont = readyContinuation
            readyContinuation = nil
            readyCont?.resume(throwing: CancellationError())
            let cont = stopContinuation
            stopContinuation = nil
            cont?.resume()

        default:
            break
        }
    }

    // MARK: - Private — Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        // Sender check: only the currently connected peer may upload/download.
        // Unknown or disallowed remote hosts — and every connection while no
        // validator is installed — are dropped before any parsing.
        guard let validator = isAllowedSender,
              let remoteHost = Self.remoteHost(of: connection),
              validator(remoteHost) else {
            connection.cancel()
            return
        }
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

    /// Extracts the remote host string from an inbound connection's endpoint.
    private static func remoteHost(of connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        return "\(host)"
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

        // Open the temp-file sink and feed it whatever body bytes arrived
        // together with the headers, then stream the rest from the socket.
        let sink: UploadSink
        do {
            sink = try UploadSink()
            if !bodyPrefix.isEmpty {
                // The prefix can contain pipelined bytes past the declared
                // Content-Length — never write more than the body itself.
                try sink.append(bodyPrefix.prefix(contentLength))
            }
        } catch {
            sendErrorResponse(on: connection, status: 500, message: "Temp file create failed: \(error)")
            return
        }

        streamBody(
            on: connection,
            filename: filename,
            mimeType: mimeType,
            expectedChecksum: expectedChecksum,
            contentLength: contentLength,
            sink: sink
        )
    }

    // MARK: - Private — Body Streaming

    /// Incremental sink for an uploaded body: bytes are appended to a temp
    /// file and hashed as they arrive, so the server never holds more than a
    /// single network read in memory (vs. accumulating the whole body, which
    /// OOMs on multi-GB files).
    ///
    /// `@unchecked Sendable`: all mutations happen in the serialized receive
    /// callback chain of a single `NWConnection` (one callback schedules the
    /// next), so there is never concurrent access.
    ///
    /// Lifecycle contract:
    /// - happy path:      `append`* → `finish()` → ownership of the temp file
    ///   passes to the caller (or `deleteTempFile()` on rejection, e.g.
    ///   checksum mismatch).
    /// - abort path:      `append`* → `discard()`.
    /// `finish()` closes the file handle exactly once; `discard()` is safe to
    /// call at any point (before or after `finish()`) and never double-closes.
    private final class UploadSink: @unchecked Sendable {
        let tempURL: URL
        private let handle: FileHandle
        private var hasher = SHA256()
        private(set) var bytesWritten: Int = 0

        /// True once the handle has been closed (or a close was attempted).
        /// Guards against double-closing in `discard()`.
        private var isFinished = false

        init() throws {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("airbridge-upload-\(UUID().uuidString).tmp")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.handle = try FileHandle(forWritingTo: url)
            self.tempURL = url
        }

        func append(_ data: Data) throws {
            try handle.write(contentsOf: data)
            hasher.update(data: data)
            bytesWritten += data.count
        }

        /// Closes the file handle and returns the hex SHA-256 of everything
        /// written. Call at most once. The handle counts as closed even if
        /// the close throws, so a subsequent `discard()` won't close again.
        func finish() throws -> String {
            defer { isFinished = true }
            try handle.close()
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }

        /// Deletes the temp file WITHOUT touching the handle. Only valid
        /// after `finish()` — e.g. when the upload is rejected post-hash
        /// (checksum mismatch) or nobody claims the file.
        func deleteTempFile() {
            try? FileManager.default.removeItem(at: tempURL)
        }

        /// Abort path: closes the handle if it is still open, then deletes
        /// the temp file. Idempotent and safe at any point in the lifecycle.
        func discard() {
            if !isFinished {
                isFinished = true
                try? handle.close()
            }
            deleteTempFile()
        }
    }

    /// Recursively receives body data until `contentLength` bytes have been
    /// written to the sink.
    private nonisolated func streamBody(
        on connection: NWConnection,
        filename: String,
        mimeType: String,
        expectedChecksum: String?,
        contentLength: Int,
        sink: UploadSink
    ) {
        // Report progress — call directly, not via actor hop
        self.onProgress?(filename, sink.bytesWritten, contentLength)

        if sink.bytesWritten >= contentLength {
            Task {
                await self.finalizeUpload(
                    on: connection,
                    filename: filename,
                    mimeType: mimeType,
                    expectedChecksum: expectedChecksum,
                    sink: sink
                )
            }
            return
        }

        let remaining = contentLength - sink.bytesWritten
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 1_048_576)) { [weak self] data, _, isComplete, error in
            guard let self else {
                sink.discard()
                return
            }

            if let error {
                sink.discard()
                self.sendErrorResponse(on: connection, status: 500, message: "Receive error: \(error)")
                return
            }

            if let data, !data.isEmpty {
                do {
                    try sink.append(data)
                } catch {
                    sink.discard()
                    self.sendErrorResponse(on: connection, status: 500, message: "Temp file write failed: \(error)")
                    return
                }
            }

            if isComplete && sink.bytesWritten < contentLength {
                sink.discard()
                self.sendErrorResponse(on: connection, status: 400, message: "Connection closed before full body received")
                return
            }

            self.streamBody(
                on: connection,
                filename: filename,
                mimeType: mimeType,
                expectedChecksum: expectedChecksum,
                contentLength: contentLength,
                sink: sink
            )
        }
    }

    /// Verifies checksum (if provided), invokes callback, and sends HTTP response.
    private func finalizeUpload(
        on connection: NWConnection,
        filename: String,
        mimeType: String,
        expectedChecksum: String?,
        sink: UploadSink
    ) {
        let computedChecksum: String
        do {
            computedChecksum = try sink.finish()
        } catch {
            sink.discard()
            sendErrorResponse(on: connection, status: 500, message: "Temp file finalize failed: \(error)")
            return
        }

        if let expected = expectedChecksum, !expected.isEmpty {
            guard computedChecksum.lowercased() == expected.lowercased() else {
                sink.deleteTempFile()
                sendErrorResponse(
                    on: connection,
                    status: 400,
                    message: "Checksum mismatch: expected \(expected), got \(computedChecksum)"
                )
                return
            }
        }

        if let onFileReceived {
            // Ownership of the temp file passes to the callback.
            onFileReceived(filename, mimeType, computedChecksum, sink.tempURL)
        } else {
            // finish() already closed the handle — nobody wants the file.
            sink.deleteTempFile()
        }

        let json = "{\"status\":\"ok\",\"bytes_received\":\(sink.bytesWritten)}"
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

    /// Disk-read / socket-write chunk size for the outgoing path (1 MB).
    private static let outgoingChunkSize = 1_048_576

    /// Look up a registered outgoing file by transferId and stream it back
    /// to the connecting peer straight from disk — the file is never loaded
    /// into memory as a whole (a multi-GB video would OOM). Fires the file's
    /// onProgress/onComplete callbacks as bytes leave the box. Unregisters
    /// the entry immediately.
    private func serveOutgoingFile(on connection: NWConnection, transferId: String) {
        guard let pending = pendingOutgoingFiles[transferId] else {
            sendErrorResponse(on: connection, status: 404, message: "Unknown transferId")
            return
        }

        // Capture everything locally and remove the registration — from here
        // on, only our local references matter.
        let fileURL = pending.fileURL
        let filename = pending.filename
        let mimeType = pending.mimeType
        let onProgress = pending.onProgress
        let onComplete = pending.onComplete
        pendingOutgoingFiles.removeValue(forKey: transferId)

        // All file I/O runs off the actor so a multi-GB transfer never blocks
        // other HTTP requests.
        //
        // The strong `self` capture is deliberate: it only serves to call
        // `sendErrorResponse` (nonisolated) — no actor-isolated state is
        // touched, and keeping the server alive for the duration of an
        // in-flight transfer is desired. `onProgress`/`onComplete` are plain
        // @Sendable closures with no isolation requirements either.
        Task.detached(priority: .userInitiated) { [self] in
            guard let total = Self.fileSize(at: fileURL),
                  // Integrity checksum the phone verifies after the download
                  // completes. Computed by streaming the file once up front.
                  let checksum = Self.sha256OfFile(at: fileURL),
                  let handle = try? FileHandle(forReadingFrom: fileURL) else {
                self.sendErrorResponse(on: connection, status: 500, message: "File read failed")
                onComplete(false)
                return
            }
            defer { try? handle.close() }

            let encodedFilename = filename
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
            let headers = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: \(mimeType)\r\n"
                + "Content-Length: \(total)\r\n"
                + "X-Filename: \(encodedFilename)\r\n"
                + "X-Checksum-SHA256: \(checksum)\r\n"
                + "Connection: close\r\n"
                + "\r\n"

            do {
                try await Self.send(Data(headers.utf8), on: connection)
                // Report 0% before any body bytes — lets the UI switch out of
                // "waiting for accept" into "transferring" immediately.
                onProgress(0, total)

                var sent: Int64 = 0
                while sent < total {
                    // Never read past the advertised Content-Length, even if
                    // the file grew after the size was taken.
                    let readSize = Int(min(Int64(Self.outgoingChunkSize), total - sent))
                    let chunk = try autoreleasepool { try handle.read(upToCount: readSize) }
                    guard let chunk, !chunk.isEmpty else {
                        // File shrank under us — Content-Length can't be
                        // satisfied; drop the connection so the peer notices.
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    // Backpressure: wait for the previous chunk to be handed
                    // to the transport before reading the next one.
                    try await Self.send(chunk, on: connection)
                    sent += Int64(chunk.count)
                    onProgress(sent, total)
                }
                onComplete(true)
                connection.cancel()
            } catch {
                onComplete(false)
                connection.cancel()
            }
        }
    }

    /// Sends one buffer and suspends until the transport has consumed it
    /// (`contentProcessed`) — this is what bounds memory to a single chunk.
    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// Streaming SHA-256 of a file — reads in chunks, never the whole file.
    private static func sha256OfFile(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? autoreleasepool(invoking: { try handle.read(upToCount: outgoingChunkSize) }),
                  !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
