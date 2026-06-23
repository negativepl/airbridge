import Foundation
import Network
import Security
import Protocol
import os

// MARK: - WebSocketServer

/// An actor that manages a WebSocket server using `NWListener`.
///
/// Clients connect over TLS (the listener serves the injected `SecIdentity`)
/// with WebSocket framing. Messages are JSON-encoded `Message` values.
public actor WebSocketServer {

    // MARK: - Public Properties

    /// The port the listener is actually bound to.
    /// Set once the listener reaches the `ready` state.
    public private(set) var actualPort: UInt16?

    /// `true` when at least one client is connected.
    public var isConnected: Bool { !connections.isEmpty }

    /// The most recently received message (useful for testing).
    public private(set) var lastReceivedMessage: Message?

    // MARK: - Callbacks

    /// Called whenever a new `Message` arrives from any client. Includes connectionId.
    public var onMessage: (@Sendable (Message, String) -> Void)?

    /// Called whenever a binary frame arrives (used for raw file chunks).
    public var onBinaryMessage: (@Sendable (Data) -> Void)?

    /// Called when a client connects. Passes the connection endpoint description.
    public var onClientConnected: (@Sendable (String) -> Void)?

    /// Called when a client disconnects. Passes the connection endpoint description.
    public var onClientDisconnected: (@Sendable (String) -> Void)?

    /// Optional diagnostic sink for connection-lifecycle events (new/removed
    /// connection, liveness timeout). Wired to the file-based `Diag` log so a
    /// real network switch captures the full server-side sequence. Temporary.
    public var onDiagnostic: (@Sendable (String) -> Void)?

    /// Convenience method to set all callbacks at once from outside the actor.
    public func setCallbacks(
        onMessage: (@Sendable (Message, String) -> Void)?,
        onBinaryMessage: (@Sendable (Data) -> Void)? = nil,
        onClientConnected: (@Sendable (String) -> Void)?,
        onClientDisconnected: (@Sendable (String) -> Void)?
    ) {
        self.onMessage = onMessage
        self.onBinaryMessage = onBinaryMessage
        self.onClientConnected = onClientConnected
        self.onClientDisconnected = onClientDisconnected
    }

    // MARK: - Private State

    private let port: UInt16
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]

    /// Tracks authenticated connection IDs.
    private var authenticatedConnections: Set<String> = []

    private let log = Logger(subsystem: "com.airbridge.macos", category: "WebSocketServer")

    // MARK: - Liveness / heartbeat
    //
    // Bez tego Mac nie wykrywa martwego peera: TCP po zmianie sieci/zniknięciu
    // telefonu zostaje half-open i NWConnection nie przechodzi szybko w .failed.
    // Mac trzyma „zombie" — myśli, że jest połączony i broadcastuje w próżnię,
    // przez co użytkownik musi ręcznie restartować apkę na Macu. Aktywnie
    // pingujemy każde połączenie i zrywamy je, gdy zbyt długo brak jakiejkolwiek
    // ramki zwrotnej (telefon auto-odpowiada pongiem na nasz ping).
    private var lastActivity: [String: Date] = [:]
    private var livenessTask: Task<Void, Never>?
    private let pingInterval: TimeInterval = 10
    private let deadInterval: TimeInterval = 30

    // Continuation used to signal that the listener reached .ready
    private var readyContinuation: CheckedContinuation<Void, Error>?

    // Continuation used to signal that the listener reached .cancelled
    private var stopContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Init

    public init(port: UInt16 = 8765) {
        self.port = port
    }

    // MARK: - Start / Stop

    /// Creates and starts the `NWListener` with WebSocket options.
    /// Suspends until the listener is ready (or throws on failure).
    /// Optionally publishes a Bonjour service if `bonjourName` is set.
    public func isAuthenticated(_ connectionId: String) -> Bool {
        authenticatedConnections.contains(connectionId)
    }

    public func markAuthenticated(_ connectionId: String) {
        authenticatedConnections.insert(connectionId)
    }

    public func setDiagnostic(_ sink: (@Sendable (String) -> Void)?) {
        self.onDiagnostic = sink
    }

    public func disconnectClient(_ connectionId: String) {
        connections[connectionId]?.cancel()
        connections.removeValue(forKey: connectionId)
        lastActivity.removeValue(forKey: connectionId)
        authenticatedConnections.remove(connectionId)
    }

    /// Disconnects all connected clients.
    public func disconnectAllClients() {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        lastActivity.removeAll()
        authenticatedConnections.removeAll()
    }

    public func start(tlsIdentity: SecIdentity, bonjourName: String? = nil, httpPort: UInt16? = nil, mirrorPort: UInt16? = nil, publicKeyFingerprint: String? = nil, certFingerprint: String? = nil) async throws {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        // TLS always — there is no plaintext fallback. The phone pins the
        // certificate fingerprint it learned from the pairing QR code.
        let tlsOptions = NWProtocolTLS.Options()
        // sec_identity_create returns nil when the SecIdentity has no private
        // key in the Keychain (e.g. after a Keychain reset) — surface that as
        // a thrown error instead of crashing in start().
        guard let secIdentity = sec_identity_create(tlsIdentity) else {
            throw WebSocketServerError.tlsIdentityUnavailable
        }
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            secIdentity)
        let parameters = NWParameters(tls: tlsOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let nwPort: NWEndpoint.Port
        if port == 0 {
            nwPort = .any
        } else {
            guard let p = NWEndpoint.Port(rawValue: port) else {
                throw WebSocketServerError.invalidPort(port)
            }
            nwPort = p
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        self.listener = listener

        // Publish Bonjour service on the same listener
        if let bonjourName {
            var txtRecord = NWTXTRecord()
            if let httpPort {
                txtRecord["http_port"] = "\(httpPort)"
            }
            if let mirrorPort {
                txtRecord["mirror_port"] = "\(mirrorPort)"
            }
            if let publicKeyFingerprint {
                txtRecord["pk_fingerprint"] = publicKeyFingerprint
            }
            // Informational only: lets the phone detect a changed TLS cert
            // (Mac re-installed) and prompt for re-pairing. Trust always
            // comes from the pairing QR code, never from NSD.
            if let certFingerprint {
                txtRecord["cert_fingerprint"] = certFingerprint
            }
            listener.service = NWListener.Service(name: bonjourName, type: "_airbridge._tcp", txtRecord: txtRecord)
        }

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
        livenessTask?.cancel()
        livenessTask = nil
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        lastActivity.removeAll()
        authenticatedConnections.removeAll()
        actualPort = nil
        log.notice("server stopped")
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

    // MARK: - Broadcast

    /// JSON-encodes `message` and sends it to all connected clients as a WebSocket text frame.
    public func broadcast(_ message: Message) throws {
        let data = try JSONEncoder().encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw WebSocketServerError.encodingFailed
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "websocket-text",
            metadata: [metadata]
        )

        for (_, conn) in connections {
            conn.send(
                content: Data(jsonString.utf8),
                contentContext: context,
                isComplete: true,
                completion: .idempotent
            )
        }
    }

    /// Sends raw binary data to all connected clients as a WebSocket binary frame.
    public func broadcastBinary(_ data: Data) async throws {
        for (_, conn) in connections {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])
            try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
                conn.send(content: data, contentContext: context, isComplete: true,
                          completion: .contentProcessed { err in
                              if let err { cc.resume(throwing: err) } else { cc.resume(returning: ()) }
                          })
            }
        }
    }

    // MARK: - Send to Single Client

    /// JSON-encodes `message` and sends it to a specific connected client.
    public func sendTo(_ message: Message, connectionId: String) throws {
        guard let conn = connections[connectionId] else { return }
        let data = try JSONEncoder().encode(message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw WebSocketServerError.encodingFailed
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "websocket-text",
            metadata: [metadata]
        )
        conn.send(content: Data(jsonString.utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: - Private Handlers

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
            #if DEBUG
            print("[WebSocketServer] Listener failed: \(error)")
            #endif

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

    private func handleNewConnection(_ connection: NWConnection) {
        let id = connectionID(for: connection)
        connections[id] = connection
        lastActivity[id] = Date()
        log.notice("new connection \(id, privacy: .public) (total=\(self.connections.count, privacy: .public))")
        onDiagnostic?("WS new connection \(id) (total=\(connections.count))")

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleConnectionStateChange(state, id: id)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        onClientConnected?(id)
        startLivenessMonitorIfNeeded()

        receiveNextMessage(on: connection, id: id)
    }

    private func handleConnectionStateChange(_ state: NWConnection.State, id: String) {
        switch state {
        case .failed(let error):
            log.notice("connection \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onDiagnostic?("WS connection \(id) failed: \(error.localizedDescription)")
            removeConnection(id: id)
        case .cancelled:
            log.notice("connection \(id, privacy: .public) cancelled")
            onDiagnostic?("WS connection \(id) cancelled")
            removeConnection(id: id)
        default:
            break
        }
    }

    private nonisolated func receiveNextMessage(on connection: NWConnection, id: String) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if error != nil {
                Task {
                    await self.removeConnection(id: id)
                }
                return
            }

            // Każda ramka (w tym pong na nasz heartbeat) liczy się jako oznaka
            // życia — resetuje licznik bezczynności dla tego połączenia.
            Task {
                await self.noteActivity(id: id)
            }

            if let data, !data.isEmpty {
                // Check if this is a binary WebSocket frame
                let isBinary: Bool
                if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                    isBinary = metadata.opcode == .binary
                } else {
                    isBinary = false
                }

                Task {
                    await self.handleReceivedData(data, isBinary: isBinary, from: id)
                }
            }

            // Continue receiving on the same connection
            self.receiveNextMessage(on: connection, id: id)
        }
    }

    private func handleReceivedData(_ data: Data, isBinary: Bool, from id: String) {
        if isBinary {
            onBinaryMessage?(data)
        } else {
            guard let message = try? JSONDecoder().decode(Message.self, from: data) else {
                return
            }
            lastReceivedMessage = message
            onMessage?(message, id)
        }
    }

    private func removeConnection(id: String) {
        // Idempotentne: stan połączenia i timeout liveness mogą zawołać to oba.
        guard connections[id] != nil || lastActivity[id] != nil else { return }
        connections.removeValue(forKey: id)
        lastActivity.removeValue(forKey: id)
        // Also drop the authentication state. Connection IDs are derived from
        // host:port, so a later connection can legitimately reuse the same ID;
        // leaving it here would let that new client skip authentication.
        authenticatedConnections.remove(id)
        log.notice("removed connection \(id, privacy: .public) (total=\(self.connections.count, privacy: .public))")
        onClientDisconnected?(id)
    }

    // MARK: - Liveness / heartbeat

    private func noteActivity(id: String) {
        guard connections[id] != nil else { return }
        lastActivity[id] = Date()
    }

    /// Pętla heartbeatu: co `pingInterval` pinguje żywe połączenia, a te bez
    /// jakiejkolwiek aktywności przez `deadInterval` zrywa jako zombie.
    private func startLivenessMonitorIfNeeded() {
        guard livenessTask == nil else { return }
        let interval = pingInterval
        livenessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.runLivenessCheck()
            }
        }
    }

    private func runLivenessCheck() {
        guard !connections.isEmpty else { return }
        let now = Date()
        for (id, conn) in connections {
            let last = lastActivity[id] ?? now
            let idle = now.timeIntervalSince(last)
            if idle > deadInterval {
                log.notice("liveness timeout for \(id, privacy: .public) — idle \(Int(idle), privacy: .public)s > \(Int(self.deadInterval), privacy: .public)s, dropping zombie")
                onDiagnostic?("WS liveness timeout \(id) — idle \(Int(idle))s, dropping zombie")
                conn.cancel()
                removeConnection(id: id)
            } else {
                sendPing(on: conn)
            }
        }
    }

    private func sendPing(on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
        connection.send(content: Data(), contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: - Helpers

    private func connectionID(for connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return UUID().uuidString
        }
    }
}

// MARK: - Errors

public enum WebSocketServerError: Error {
    case invalidPort(UInt16)
    case encodingFailed
    /// The TLS `SecIdentity` could not be wrapped for Network.framework —
    /// typically its private key is missing from the Keychain.
    case tlsIdentityUnavailable
}

extension WebSocketServerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid port: \(port)"
        case .encodingFailed:
            return "Failed to encode message"
        case .tlsIdentityUnavailable:
            return "TLS identity is unavailable (private key missing from the Keychain)"
        }
    }
}
