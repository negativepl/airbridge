import Foundation
import Network
import SwiftUI
import Protocol
import AirbridgeSecurity
import Clipboard
import Networking
import Pairing

/// Delegate protocol for services that handle specific message types.
@MainActor
protocol MessageHandler: AnyObject {
    func handleMessage(_ message: Message)
}

/// Manages WebSocket + HTTP server lifecycle, Bonjour advertisement,
/// authentication, and message routing to registered handlers.
@Observable
@MainActor
final class ConnectionService {

    // MARK: - Observable State

    private(set) var isConnected: Bool = false
    private(set) var connectedDeviceName: String = ""
    private(set) var deviceInfo: DeviceInfo?
    /// The phone's wallpaper (JPEG) for the Home hero, à la Phone Link.
    private(set) var phoneWallpaper: Data?
    private(set) var connectedClientIP: String?
    private(set) var statusMessage: String = "Idle"
    private var manuallyDisconnected: Bool = false
    /// Czy telefon aktualnie dzwoni (sterowanie przyciskiem „Zadzwoń/Zatrzymaj" w pasku menu).
    private(set) var isRinging: Bool = false

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
    /// Thread-safe mirror of `connectedClientIP` readable from the HTTP
    /// server's actor context (the sender validator closure).
    @ObservationIgnored private let allowedUploadSender = AllowedSenderStore()
    var mirrorService: MirrorService?
    var pairingService: PairingService?
    private var serverStarted = false
    @ObservationIgnored private var pathMonitor: NetworkChangeMonitor?

    // MARK: - Message Handlers

    private var clipboardHandler: MessageHandler?
    private var fileTransferHandler: MessageHandler?
    private var galleryHandler: MessageHandler?
    private var smsHandler: MessageHandler?
    private var filesHandler: MessageHandler?
    private var notificationHandler: MessageHandler?

    func registerHandlers(
        clipboard: MessageHandler,
        fileTransfer: MessageHandler,
        gallery: MessageHandler,
        sms: MessageHandler,
        files: MessageHandler,
        notifications: MessageHandler
    ) {
        self.clipboardHandler = clipboard
        self.fileTransferHandler = fileTransfer
        self.galleryHandler = gallery
        self.smsHandler = sms
        self.filesHandler = files
        self.notificationHandler = notifications
    }

    // MARK: - Server Lifecycle

    func startServer() {
        Task { await startServerNow() }
    }

    private func startServerNow() async {
        guard !serverStarted else { return }
        serverStarted = true
        statusMessage = L10n.isPL ? "Uruchamianie…" : "Starting…"
        startDeviceInfoPolling()

        do {
            // Only the currently connected (paired + authenticated) phone may
            // talk to the upload server; with no phone connected, reject all.
            // Installed before start() so there is no allow-all window.
            let allowed = allowedUploadSender
            await httpServer.setSenderValidator { remoteHost in
                guard let host = allowed.host else { return false }
                return HttpUploadServer.normalizeHost(remoteHost) == HttpUploadServer.normalizeHost(host)
            }
            try await httpServer.start()
            try await advertiseServer()
            keyManager.migrateFromSingleDevice()
            startNetworkMonitor()
            statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
        } catch {
            statusMessage = L10n.isPL ? "Błąd serwera: \(error.localizedDescription)" : "Server failed: \(error.localizedDescription)"
            serverStarted = false
        }
    }

    /// (Re)start the WebSocket listener and (re)register the Bonjour service so
    /// it advertises on the Mac's current network address.
    private func advertiseServer() async throws {
        let httpPort = await httpServer.actualPort ?? 8766
        let deviceName = Host.current().localizedName ?? "Mac"
        let identity = try keyManager.getOrCreateIdentity()
        let fingerprint = keyManager.fingerprintOf(identity.publicKeyBase64)
        let mPort = mirrorService?.actualPort
        try await server.start(bonjourName: deviceName, httpPort: httpPort, mirrorPort: mPort, publicKeyFingerprint: fingerprint)
        await configureServerCallbacks()
    }

    private func startNetworkMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NetworkChangeMonitor { [weak self] in
            Task { @MainActor in self?.handleNetworkChange() }
        }
        pathMonitor = monitor
        monitor.start()
    }

    // Serializes server restarts: only one runs at a time. A restart request
    // arriving mid-restart collapses into a single catch-up pass (no queue).
    @ObservationIgnored private var isRestarting = false
    @ObservationIgnored private var restartPending = false

    /// Runs one restart `pass`, then repeats it as long as another restart
    /// request (network change / reconnect) arrived mid-pass, so no request
    /// is ever dropped. Callers must set `isRestarting = true` before
    /// spawning the task that awaits this.
    private func runRestartCatchingUp(_ pass: @MainActor () async -> Void) async {
        defer { isRestarting = false }
        repeat {
            restartPending = false
            await pass()
        } while restartPending
    }

    /// The Mac moved to a different network: re-advertise Bonjour on the new IP
    /// so the phone can rediscover us. The phone is the side that reconnects.
    private func handleNetworkChange() {
        guard serverStarted, !manuallyDisconnected else { return }
        statusMessage = L10n.isPL ? "Zmiana sieci — ponowne rozgłaszanie…" : "Network changed — re-advertising…"
        if isRestarting {
            restartPending = true
            return
        }
        isRestarting = true
        Task {
            await runRestartCatchingUp {
                guard serverStarted, !manuallyDisconnected else { return }
                await server.stop()
                // Reset connection state before trying to come back up, so the UI
                // never shows "Connected" on a dead server if advertising fails.
                resetConnectionState()
                do {
                    try await advertiseServer()
                    statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
                } catch {
                    statusMessage = L10n.isPL ? "Błąd serwera: \(error.localizedDescription)" : "Server failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Stops both servers and returns only after their listeners have fully
    /// released their ports, so a follow-up start can re-bind immediately.
    func stopServer() async {
        pathMonitor?.stop()
        pathMonitor = nil
        resetConnectionState()
        statusMessage = L10n.isPL ? "Zatrzymano" : "Stopped"
        serverStarted = false
        await server.stop()
        await httpServer.stop()
    }

    func reconnect() {
        manuallyDisconnected = false
        if isRestarting {
            restartPending = true
            return
        }
        isRestarting = true
        Task {
            await runRestartCatchingUp {
                await stopServer()
                try? await Task.sleep(for: .milliseconds(500))
                await startServerNow()
            }
        }
    }

    func disconnect() {
        manuallyDisconnected = true
        Task {
            await server.disconnectAllClients()
        }
        resetConnectionState()
        statusMessage = L10n.isPL ? "Rozłączono" : "Disconnected"
    }

    private func resetConnectionState() {
        isConnected = false
        connectedDeviceName = ""
        deviceInfo = nil
        phoneWallpaper = nil
    }

    // MARK: - Broadcasting

    func broadcast(_ message: Message) async throws {
        try await server.broadcast(message)
    }

    func sendTo(_ message: Message, connectionId: String) async throws {
        try await server.sendTo(message, connectionId: connectionId)
    }

    /// Poproś telefon o świeże DeviceInfo (np. cyklicznie, dla stanu ładowania na żywo).
    func requestDeviceInfo() {
        Task { try? await server.broadcast(.deviceInfoRequest) }
    }

    /// Globalna pętla odświeżania DeviceInfo (bateria itp.) co 15 s, niezależna od
    /// otwartego okna — żeby pasek menu miał aktualny stan także przy zamkniętym oknie.
    private var deviceInfoPollTask: Task<Void, Never>?
    private func startDeviceInfoPolling() {
        deviceInfoPollTask?.cancel()
        deviceInfoPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                if self.isConnected {
                    try? await self.server.broadcast(.deviceInfoRequest)
                }
            }
        }
    }

    /// Zadzwoń na telefon (głośny alarm) / zatrzymaj dzwonienie.
    @ObservationIgnored private var ringResetTask: Task<Void, Never>?

    func ringPhone() {
        isRinging = true
        Task { try? await server.broadcast(.phoneRing) }
        // Telefon sam wycisza się po 30 s — zsynchronizuj przycisk nawet gdyby
        // potwierdzenie PhoneRingStop nie dotarło.
        ringResetTask?.cancel()
        ringResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isRinging = false
        }
    }

    func stopRingPhone() {
        isRinging = false
        ringResetTask?.cancel()
        Task { try? await server.broadcast(.phoneRingStop) }
    }

    /// Telefon zgłosił, że dzwonek ucichł (przycisk na telefonie / auto-stop).
    private func handlePhoneRingStopped() {
        isRinging = false
        ringResetTask?.cancel()
    }

    // MARK: - Auth Handling

    func handlePairRequest(deviceName: String, publicKey: String, token: String, from connectionId: String) {
        guard pairingManager.validateToken(token) else {
            statusMessage = L10n.isPL ? "Parowanie odrzucone: nieprawidłowy token" : "Pairing rejected: invalid token"
            return
        }

        pairingManager.completePairing(deviceName: deviceName, publicKey: publicKey)
        connectedDeviceName = deviceName
        setConnectedClientIP(Self.hostPart(ofConnectionId: connectionId))
        statusMessage = L10n.isPL ? "Sparowano z \(deviceName)" : "Paired with \(deviceName)"
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
                try? await server.sendTo(.authResponse(accepted: false, reason: "not_paired", mirrorPort: nil), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            let timestampData = Data("\(timestamp)".utf8)
            guard let sigData = Data(base64Encoded: signature),
                  let valid = try? KeyManager.verify(message: timestampData, signature: sigData, publicKeyBase64: publicKey),
                  valid else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "invalid_signature", mirrorPort: nil), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            guard abs(now - timestamp) < 30_000 else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "expired", mirrorPort: nil), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            await server.markAuthenticated(connectionId)
            // Hand the phone our mirror server port over the application channel so
            // phone-initiated screen sharing works after every (re)connect — not only
            // right after a fresh Bonjour/NSD resolve (which is one-shot and lost on
            // process restart or WebSocket auto-reconnect).
            let mirrorPort = mirrorService?.actualPort.map { Int($0) }
            try? await server.sendTo(.authResponse(accepted: true, reason: nil, mirrorPort: mirrorPort), connectionId: connectionId)

            let device = keyManager.getPairedDevices().first { $0.publicKeyBase64 == publicKey }
            self.connectedDeviceName = device?.deviceName ?? "Device"
            self.setConnectedClientIP(Self.hostPart(ofConnectionId: connectionId))
            self.isConnected = true
            self.statusMessage = L10n.isPL ? "Połączono z \(self.connectedDeviceName)" : "Connected to \(self.connectedDeviceName)"

            // Pull richer device info (exact name, storage, RAM, battery) and
            // the wallpaper for the Home screen.
            try? await self.server.broadcast(.deviceInfoRequest)
            try? await self.server.broadcast(.wallpaperRequest)
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
        case .fileTransferAccept, .fileTransferReject, .fileTransferOffer:
            fileTransferHandler?.handleMessage(message)
        case .galleryResponse, .galleryThumbnailResponse, .galleryPreviewResponse:
            galleryHandler?.handleMessage(message)
        case .smsConversationsResponse, .smsMessagesResponse, .smsSendResponse:
            smsHandler?.handleMessage(message)
        case .filesListResponse, .fileThumbnailResponse, .folderStatsResponse, .fileDeleteResponse:
            filesHandler?.handleMessage(message)
        case .notificationPosted:
            notificationHandler?.handleMessage(message)
        case .deviceInfoResponse(let info):
            deviceInfo = info
        case .wallpaperResponse(let imageBase64):
            phoneWallpaper = imageBase64.isEmpty ? nil : Data(base64Encoded: imageBase64)
        case .macInfoRequest:
            let info = MacSystemInfo.collect()
            Task { try? await server.broadcast(.macInfoResponse(info: info)) }
        case .macWallpaperRequest:
            let image = MacSystemInfo.wallpaperJPEGBase64()
            Task { try? await server.broadcast(.macWallpaperResponse(imageBase64: image)) }
        case .ping(let timestamp):
            Task { try? await server.broadcast(Message.pong(timestamp: timestamp)) }
        case .phoneRingStop:
            handlePhoneRingStopped()
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
        let onConnect: @Sendable (String) -> Void = { _ in }
        let onDisconnect: @Sendable (String) -> Void = { [weak self] endpoint in
            Task { @MainActor in
                guard let self else { return }
                let stillConnected = await self.server.isConnected
                self.isConnected = stillConnected
                if !stillConnected {
                    // No phone connected → the upload server accepts nobody.
                    self.setConnectedClientIP(nil)
                }
                if !stillConnected && !self.manuallyDisconnected {
                    self.connectedDeviceName = ""
                    self.deviceInfo = nil
                    self.phoneWallpaper = nil
                    self.statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
                }
            }
        }
        await server.setCallbacks(
            onMessage: onMessage,
            onClientConnected: onConnect,
            onClientDisconnected: onDisconnect
        )
    }

    // MARK: - Mirror Helpers

    func currentPairingTokenString() -> String? {
        pairingService?.currentTokenData()?.base64EncodedString()
    }

    // MARK: - Helpers

    func getConnectedClientIP() -> String? {
        connectedClientIP
    }

    /// Updates `connectedClientIP` and its thread-safe mirror used by the
    /// HTTP upload server's sender validator.
    private func setConnectedClientIP(_ ip: String?) {
        connectedClientIP = ip
        allowedUploadSender.host = ip
    }

    /// A connectionId has the form "host:port". For IPv6 the host itself
    /// contains colons ("fe80::1%en0:8765"), so take everything before the
    /// LAST colon instead of splitting on the first one.
    private static func hostPart(ofConnectionId id: String) -> String? {
        guard let idx = id.lastIndex(of: ":") else { return id }
        let host = String(id[..<idx])
        return host.isEmpty ? nil : host
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

// MARK: - AllowedSenderStore

/// Lock-protected holder for the connected phone's IP. The MainActor-bound
/// `ConnectionService` writes it; the `HttpUploadServer` actor reads it from
/// the sender-validator closure, so it must be `Sendable` and thread-safe.
final class AllowedSenderStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _host: String?
    var host: String? {
        get { lock.withLock { _host } }
        set { lock.withLock { _host = newValue } }
    }
}
