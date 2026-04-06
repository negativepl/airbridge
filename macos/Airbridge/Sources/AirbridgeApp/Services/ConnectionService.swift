import Foundation
import SwiftUI
import Protocol
import AirbridgeSecurity
import Clipboard
import FileTransfer
import Networking
import Pairing

/// Delegate protocol for services that handle specific message types.
@MainActor
protocol MessageHandler: AnyObject {
    func handleMessage(_ message: Message)
}

/// Protocol for handling binary WebSocket frames (raw file chunks).
@MainActor
protocol BinaryChunkHandler: AnyObject {
    func handleBinaryChunk(_ data: Data)
}

/// Manages WebSocket + HTTP server lifecycle, Bonjour advertisement,
/// authentication, and message routing to registered handlers.
@Observable
@MainActor
final class ConnectionService {

    // MARK: - Observable State

    private(set) var isConnected: Bool = false
    private(set) var connectedDeviceName: String = ""
    private(set) var connectedClientIP: String?
    private(set) var statusMessage: String = "Idle"
    private var manuallyDisconnected: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored let keyManager = KeyManager.persistent()
    @ObservationIgnored private var _pairingManager: PairingManager?
    var pairingManager: PairingManager {
        if let pm = _pairingManager { return pm }
        let pm = PairingManager(keyManager: keyManager)
        _pairingManager = pm
        return pm
    }
    @ObservationIgnored let server = WebSocketServer(port: 8765)
    @ObservationIgnored let httpServer = HttpUploadServer(port: 8766)
    private var serverStarted = false

    // MARK: - Message Handlers

    private var clipboardHandler: MessageHandler?
    private var fileTransferHandler: MessageHandler?
    private var galleryHandler: MessageHandler?
    private var smsHandler: MessageHandler?

    func registerHandlers(
        clipboard: MessageHandler,
        fileTransfer: MessageHandler,
        gallery: MessageHandler,
        sms: MessageHandler
    ) {
        self.clipboardHandler = clipboard
        self.fileTransferHandler = fileTransfer
        self.galleryHandler = gallery
        self.smsHandler = sms
    }

    // MARK: - Server Lifecycle

    func startServer() {
        guard !serverStarted else { return }
        serverStarted = true
        statusMessage = "Starting..."

        Task {
            do {
                try await httpServer.start()
                let httpPort = await httpServer.actualPort ?? 8766

                let deviceName = Host.current().localizedName ?? "Mac"
                let identity = try keyManager.getOrCreateIdentity()
                let fingerprint = keyManager.fingerprintOf(identity.publicKeyBase64)
                try await server.start(bonjourName: deviceName, httpPort: httpPort, publicKeyFingerprint: fingerprint)

                await configureServerCallbacks()

                keyManager.migrateFromSingleDevice()

                statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
            } catch {
                statusMessage = L10n.isPL ? "Błąd serwera: \(error.localizedDescription)" : "Server failed: \(error.localizedDescription)"
                serverStarted = false
            }
        }
    }

    func stopServer() {
        Task {
            await server.stop()
            await httpServer.stop()
        }
        isConnected = false
        connectedDeviceName = ""
        statusMessage = "Stopped"
        serverStarted = false
    }

    func reconnect() {
        manuallyDisconnected = false
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServer()
        }
    }

    func disconnect() {
        manuallyDisconnected = true
        Task {
            await server.disconnectAllClients()
        }
        isConnected = false
        connectedDeviceName = ""
        statusMessage = L10n.isPL ? "Rozłączono" : "Disconnected"
    }

    // MARK: - Broadcasting

    func broadcast(_ message: Message) async throws {
        try await server.broadcast(message)
    }

    func sendTo(_ message: Message, connectionId: String) async throws {
        try await server.sendTo(message, connectionId: connectionId)
    }

    // MARK: - Auth Handling

    func handlePairRequest(deviceName: String, publicKey: String, token: String, from connectionId: String) {
        guard pairingManager.validateToken(token) else {
            statusMessage = "Pairing rejected: invalid token"
            return
        }

        pairingManager.completePairing(deviceName: deviceName, publicKey: publicKey)
        connectedDeviceName = deviceName
        connectedClientIP = connectionId.components(separatedBy: ":").first
        statusMessage = "Paired with \(deviceName)"
        isConnected = true

        Task {
            await server.markAuthenticated(connectionId)
            do {
                let identity = try keyManager.getOrCreateIdentity()
                let macName = Host.current().localizedName ?? "Mac"
                let response = Message.pairResponse(
                    deviceName: macName,
                    publicKey: identity.publicKeyBase64,
                    accepted: true
                )
                try await server.sendTo(response, connectionId: connectionId)
            } catch {
                #if DEBUG
                print("[ConnectionService] Failed to send pair response: \(error)")
                #endif
            }
        }
    }

    func handleAuthRequest(publicKey: String, signature: String, timestamp: Int64, from connectionId: String) {
        Task {
            guard keyManager.isPairedByKey(publicKey) else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "not_paired"), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            let timestampData = Data("\(timestamp)".utf8)
            guard let sigData = Data(base64Encoded: signature),
                  let valid = try? KeyManager.verify(message: timestampData, signature: sigData, publicKeyBase64: publicKey),
                  valid else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "invalid_signature"), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            guard abs(now - timestamp) < 30_000 else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "expired"), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            await server.markAuthenticated(connectionId)
            try? await server.sendTo(.authResponse(accepted: true, reason: nil), connectionId: connectionId)

            let device = keyManager.getPairedDevices().first { $0.publicKeyBase64 == publicKey }
            self.connectedDeviceName = device?.deviceName ?? "Device"
            self.connectedClientIP = connectionId.components(separatedBy: ":").first
            self.isConnected = true
            self.statusMessage = "Connected to \(self.connectedDeviceName)"
        }
    }

    // MARK: - Message Routing

    private func handleMessage(_ message: Message, from connectionId: String) {
        switch message {
        case .authRequest(let publicKey, let signature, let timestamp):
            handleAuthRequest(publicKey: publicKey, signature: signature, timestamp: timestamp, from: connectionId)

        case .pairRequest(let deviceName, let publicKey, let pairingToken):
            handlePairRequest(deviceName: deviceName, publicKey: publicKey, token: pairingToken, from: connectionId)

        default:
            Task {
                let isAuth = await server.isAuthenticated(connectionId)
                guard isAuth else { return }
                await MainActor.run {
                    self.routeAuthenticatedMessage(message)
                }
            }
        }
    }

    private func routeAuthenticatedMessage(_ message: Message) {
        switch message {
        case .clipboardUpdate:
            clipboardHandler?.handleMessage(message)
        case .fileTransferStart, .fileChunk, .fileChunkAck, .fileTransferComplete,
             .fileTransferAccept, .fileTransferReject, .fileTransferOffer:
            fileTransferHandler?.handleMessage(message)
        case .galleryResponse, .galleryThumbnailResponse:
            galleryHandler?.handleMessage(message)
        case .smsConversationsResponse, .smsMessagesResponse, .smsSendResponse:
            smsHandler?.handleMessage(message)
        case .ping(let timestamp):
            Task { try? await server.broadcast(Message.pong(timestamp: timestamp)) }
        default:
            break
        }
    }

    // MARK: - Server Callbacks

    private func configureServerCallbacks() async {
        let onMessage: @Sendable (Message, String) -> Void = { [weak self] message, connectionId in
            Task { @MainActor in
                self?.handleMessage(message, from: connectionId)
            }
        }
        let onBinaryMessage: @Sendable (Data) -> Void = { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let handler = self.fileTransferHandler {
                    (handler as? BinaryChunkHandler)?.handleBinaryChunk(data)
                }
            }
        }
        let onConnect: @Sendable (String) -> Void = { _ in }
        let onDisconnect: @Sendable (String) -> Void = { [weak self] endpoint in
            Task { @MainActor in
                guard let self else { return }
                let stillConnected = await self.server.isConnected
                self.isConnected = stillConnected
                if !stillConnected && !self.manuallyDisconnected {
                    self.connectedDeviceName = ""
                    self.statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
                }
            }
        }
        await server.setCallbacks(
            onMessage: onMessage,
            onBinaryMessage: onBinaryMessage,
            onClientConnected: onConnect,
            onClientDisconnected: onDisconnect
        )
    }

    // MARK: - Helpers

    func getConnectedClientIP() -> String? {
        connectedClientIP
    }

    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 {
                address = String(cString: hostname)
                break
            }
        }
        return address
    }
}
