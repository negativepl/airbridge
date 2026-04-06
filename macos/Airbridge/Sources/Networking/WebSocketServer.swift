import Foundation
import Network
import Protocol

// MARK: - WebSocketServer

/// An actor that manages a WebSocket server using `NWListener`.
///
/// Clients connect over a plain (non-TLS) TCP connection with WebSocket framing.
/// Messages are JSON-encoded `Message` values.
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

    // Continuation used to signal that the listener reached .ready
    private var readyContinuation: CheckedContinuation<Void, Error>?

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

    public func disconnectClient(_ connectionId: String) {
        connections[connectionId]?.cancel()
        connections.removeValue(forKey: connectionId)
        authenticatedConnections.remove(connectionId)
    }

    /// Disconnects all connected clients.
    public func disconnectAllClients() {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        authenticatedConnections.removeAll()
    }

    public func start(bonjourName: String? = nil, httpPort: UInt16? = nil, publicKeyFingerprint: String? = nil) async throws {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let parameters = NWParameters.tcp
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
            if let publicKeyFingerprint {
                txtRecord["pk_fingerprint"] = publicKeyFingerprint
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
    public func stop() {
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        actualPort = nil
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
            #if DEBUG
            print("[WebSocketServer] Listener failed: \(error)")
            #endif

        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let id = connectionID(for: connection)
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleConnectionStateChange(state, id: id)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        onClientConnected?(id)

        receiveNextMessage(on: connection, id: id)
    }

    private func handleConnectionStateChange(_ state: NWConnection.State, id: String) {
        switch state {
        case .failed, .cancelled:
            connections.removeValue(forKey: id)
            authenticatedConnections.remove(id)
            onClientDisconnected?(id)
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
        connections.removeValue(forKey: id)
        onClientDisconnected?(id)
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
}
