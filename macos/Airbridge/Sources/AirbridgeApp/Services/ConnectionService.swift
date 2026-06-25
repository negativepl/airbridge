import Foundation
import Network
import os
// SecIdentity is immutable and thread-safe but not marked Sendable in the SDK;
// @preconcurrency downgrades the (false-positive) actor-crossing diagnostics.
@preconcurrency import Security
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
/// Machine-readable connection state. Views must branch on this instead of
/// string-matching `statusMessage`, which is display-only text.
enum ConnectionPhase: Equatable {
    /// Server is starting or restarting (launch, reconnect, network change).
    case starting
    /// Server is advertising and waiting for the phone to connect.
    case listening
    /// A paired phone is connected and authenticated.
    case connected
    /// User disconnected manually; waiting for an explicit reconnect.
    case disconnected
    /// Server was stopped (app quitting or mid-restart).
    case stopped
    /// Server failed to start.
    case error
}

@Observable
@MainActor
final class ConnectionService {

    // MARK: - Observable State

    private let log = Logger(subsystem: "com.airbridge.macos", category: "Connection")

    /// Single source of truth for live phone connections. The legacy scalar
    /// properties below are computed views over this so existing consumers
    /// (menu bar, view models, upload validation) keep working unchanged.
    private(set) var connectedDevices: [ConnectedDevice] = []

    /// The device the single-device UI surfaces (menu bar, legacy reads) fall
    /// back to — the most recently added connection.
    var primaryDevice: ConnectedDevice? { connectedDevices.last }

    /// The phone that device-specific actions target (Gallery, Files, SMS, file
    /// send, ring). With multiple phones connected, the user picks it; with one,
    /// it is simply that one.
    private(set) var activeDeviceId: String?
    var activeDevice: ConnectedDevice? {
        connectedDevices.first { $0.connectionId == activeDeviceId } ?? primaryDevice
    }

    func setActiveDevice(_ connectionId: String) {
        guard connectedDevices.contains(where: { $0.connectionId == connectionId }) else { return }
        activeDeviceId = connectionId
    }

    /// Send a message only to the active device. No-op when none is connected.
    func sendToActive(_ message: Message) async throws {
        guard let id = activeDevice?.connectionId else { return }
        try await server.sendTo(message, connectionId: id)
    }

    var isConnected: Bool { !connectedDevices.isEmpty }
    var connectedDeviceName: String { primaryDevice?.name ?? "" }
    var deviceInfo: DeviceInfo? { primaryDevice?.deviceInfo }
    /// The phone's wallpaper (JPEG) for the Home hero, à la Phone Link.
    var phoneWallpaper: Data? { primaryDevice?.wallpaper }
    var connectedClientIP: String? { primaryDevice?.clientIP }
    private(set) var statusMessage: String = "Idle"
    /// Kept in sync with every `statusMessage`/`isConnected` change.
    private(set) var phase: ConnectionPhase = .starting
    private var manuallyDisconnected: Bool = false
    /// Czy telefon aktualnie dzwoni (sterowanie przyciskiem „Zadzwoń/Zatrzymaj" w pasku menu).
    private(set) var isRinging: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored let keyManager = KeyManager.persistent()
    /// Owns the persistent self-signed TLS identity served by all listeners.
    @ObservationIgnored private let tlsIdentityManager = TLSIdentityManager()
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
    /// Typed ref so a dropped connection can dismiss an orphaned incoming-file popup.
    var fileTransferService: FileTransferService?
    private let macFilesService = MacFilesService()
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
        phase = .starting
        startDeviceInfoPolling()

        do {
            macFilesService.configure(server: server, uploadServer: httpServer)
            // Only currently connected (paired + authenticated) phones may talk to
            // the upload server; with no phone connected, the set is empty → reject
            // all. Installed before start() so there is no allow-all window.
            let allowed = allowedUploadSender
            await httpServer.setSenderValidator { remoteHost in
                let normalized = HttpUploadServer.normalizeHost(remoteHost)
                return allowed.hosts.contains { HttpUploadServer.normalizeHost($0) == normalized }
            }
            try await httpServer.start(tlsIdentity: tlsIdentityManager.identity())
            try await advertiseServer()
            keyManager.migrateFromSingleDevice()
            startNetworkMonitor()
            statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
            phase = .listening
        } catch {
            statusMessage = L10n.isPL ? "Błąd serwera: \(error.localizedDescription)" : "Server failed: \(error.localizedDescription)"
            phase = .error
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
        let tlsIdentity = try tlsIdentityManager.identity()
        let certFingerprint = try tlsIdentityManager.certificateFingerprint()
        try await server.start(tlsIdentity: tlsIdentity, bonjourName: deviceName, httpPort: httpPort, mirrorPort: mPort, publicKeyFingerprint: fingerprint, certFingerprint: certFingerprint)
        await configureServerCallbacks()
    }

    /// Lowercase SHA-256 hex over the Mac's TLS certificate DER — embedded in
    /// the pairing QR code so the phone can pin it.
    func tlsCertificateFingerprint() throws -> String {
        try tlsIdentityManager.certificateFingerprint()
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
        log.notice("handleNetworkChange: serverStarted=\(self.serverStarted, privacy: .public) manuallyDisconnected=\(self.manuallyDisconnected, privacy: .public) isRestarting=\(self.isRestarting, privacy: .public)")
        Diag.log("Connection", "handleNetworkChange: serverStarted=\(serverStarted) manuallyDisconnected=\(manuallyDisconnected) isRestarting=\(isRestarting) wasConnected=\(isConnected)")
        guard serverStarted, !manuallyDisconnected else { return }
        statusMessage = L10n.isPL ? "Zmiana sieci — ponowne rozgłaszanie…" : "Network changed — re-advertising…"
        phase = .starting
        if isRestarting {
            restartPending = true
            return
        }
        isRestarting = true
        Task {
            await runRestartCatchingUp {
                guard serverStarted, !manuallyDisconnected else { return }
                self.log.notice("network change: stopping + re-advertising server")
                await server.stop()
                // Reset connection state before trying to come back up, so the UI
                // never shows "Connected" on a dead server if advertising fails.
                resetConnectionState()
                do {
                    try await advertiseServer()
                    Diag.log("Connection", "re-advertise OK — listening, waiting for phone to reconnect")
                    statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
                    phase = .listening
                } catch {
                    Diag.log("Connection", "re-advertise FAILED: \(error.localizedDescription)")
                    statusMessage = L10n.isPL ? "Błąd serwera: \(error.localizedDescription)" : "Server failed: \(error.localizedDescription)"
                    phase = .error
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
        phase = .stopped
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
        phase = .disconnected
    }

    private func resetConnectionState() {
        connectedDevices.removeAll()
        refreshAllowedUploadHosts()
        ensureActiveDeviceValid()
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
        Task { try? await sendToActive(.phoneRing) }
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
        Task { try? await sendToActive(.phoneRingStop) }
    }

    /// Telefon zgłosił, że dzwonek ucichł (przycisk na telefonie / auto-stop).
    private func handlePhoneRingStopped() {
        isRinging = false
        ringResetTask?.cancel()
    }

    // MARK: - Device Bookkeeping

    /// Add a new connection or update the existing one for `connectionId`.
    func upsertDevice(connectionId: String, publicKey: String, name: String, clientIP: String? = nil) {
        if let idx = connectedDevices.firstIndex(where: { $0.connectionId == connectionId }) {
            connectedDevices[idx].name = name
            if let clientIP { connectedDevices[idx].clientIP = clientIP }
        } else {
            connectedDevices.append(ConnectedDevice(
                connectionId: connectionId, publicKey: publicKey,
                name: name, clientIP: clientIP, deviceInfo: nil, wallpaper: nil))
        }
        refreshAllowedUploadHosts()
        ensureActiveDeviceValid()
    }

    /// Syncs the set of IPs allowed to upload to the currently connected devices.
    private func refreshAllowedUploadHosts() {
        allowedUploadSender.hosts = Set(connectedDevices.compactMap { $0.clientIP })
    }

    /// Keeps `activeDeviceId` pointing at a live device: defaults to the most
    /// recent connection when unset, and re-targets when the active one drops.
    private func ensureActiveDeviceValid() {
        if let id = activeDeviceId, connectedDevices.contains(where: { $0.connectionId == id }) { return }
        activeDeviceId = connectedDevices.last?.connectionId
    }

    /// Bumped on every successful pairing so the pairing UI can advance to the
    /// "Paired!" state even when another device is already connected (in which
    /// case `isConnected` does not transition false→true and would not fire).
    private(set) var pairedSignal: Int = 0
    func bumpPairedSignal() { pairedSignal += 1 }

    // MARK: - Auth Handling

    func handlePairRequest(deviceName: String, publicKey: String, token: String, from connectionId: String) {
        guard pairingManager.validateToken(token) else {
            // The server keeps listening and the phone may simply retry
            // pairing with a fresh token.
            phase = .listening
            statusMessage = L10n.isPL ? "Parowanie odrzucone: nieprawidłowy token" : "Pairing rejected: invalid token"
            return
        }

        pairingManager.completePairing(deviceName: deviceName, publicKey: publicKey)
        upsertDevice(
            connectionId: connectionId,
            publicKey: publicKey,
            name: deviceName,
            clientIP: Self.hostPart(ofConnectionId: connectionId)
        )
        statusMessage = L10n.isPL ? "Sparowano z \(deviceName)" : "Paired with \(deviceName)"
        phase = .connected
        bumpPairedSignal()

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

    func handleAuthRequest(publicKey: String, signature: String, timestamp: Int64, protocolVersion: Int, from connectionId: String) {
        Task {
            // Signal-only for now: log the mismatch but keep accepting. Rejecting
            // is a future decision for when the protocol actually diverges.
            if protocolVersion != ProtocolConstants.version {
                NSLog("[ConnectionService] Protocol version mismatch: phone speaks \(protocolVersion), we speak \(ProtocolConstants.version)")
            }

            guard keyManager.isPairedByKey(publicKey) else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "not_paired", mirrorPort: nil, protocolVersion: ProtocolConstants.version), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            let timestampData = Data("\(timestamp)".utf8)
            guard let sigData = Data(base64Encoded: signature),
                  let valid = try? KeyManager.verify(message: timestampData, signature: sigData, publicKeyBase64: publicKey),
                  valid else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "invalid_signature", mirrorPort: nil, protocolVersion: ProtocolConstants.version), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            guard abs(now - timestamp) < 30_000 else {
                try? await server.sendTo(.authResponse(accepted: false, reason: "expired", mirrorPort: nil, protocolVersion: ProtocolConstants.version), connectionId: connectionId)
                await server.disconnectClient(connectionId)
                return
            }

            await server.markAuthenticated(connectionId)
            // Hand the phone our mirror server port over the application channel so
            // phone-initiated screen sharing works after every (re)connect — not only
            // right after a fresh Bonjour/NSD resolve (which is one-shot and lost on
            // process restart or WebSocket auto-reconnect).
            let mirrorPort = mirrorService?.actualPort.map { Int($0) }
            try? await server.sendTo(.authResponse(accepted: true, reason: nil, mirrorPort: mirrorPort, protocolVersion: ProtocolConstants.version), connectionId: connectionId)

            let device = keyManager.getPairedDevices().first { $0.publicKeyBase64 == publicKey }
            self.upsertDevice(
                connectionId: connectionId,
                publicKey: publicKey,
                name: device?.deviceName ?? "Device",
                clientIP: Self.hostPart(ofConnectionId: connectionId)
            )
            Diag.log("Connection", "phone connected + authenticated: \(device?.deviceName ?? "Device") @ \(Self.hostPart(ofConnectionId: connectionId) ?? "?")")
            self.statusMessage = L10n.isPL ? "Połączono z \(self.connectedDeviceName)" : "Connected to \(self.connectedDeviceName)"
            self.phase = .connected

            // Pull richer device info (exact name, storage, RAM, battery) and the
            // wallpaper for the Home screen — targeted to this connection so each
            // device gets its own data instead of a lossy broadcast.
            try? await self.server.sendTo(.deviceInfoRequest, connectionId: connectionId)
            try? await self.server.sendTo(.wallpaperRequest, connectionId: connectionId)
        }
    }

    // MARK: - Message Routing

    private func handleMessage(_ message: Message, from connectionId: String) {
        switch message {
        case .authRequest(let publicKey, let signature, let timestamp, let protocolVersion):
            handleAuthRequest(publicKey: publicKey, signature: signature, timestamp: timestamp, protocolVersion: protocolVersion, from: connectionId)

        case .pairRequest(let deviceName, let publicKey, let pairingToken):
            handlePairRequest(deviceName: deviceName, publicKey: publicKey, token: pairingToken, from: connectionId)

        default:
            Task {
                let isAuth = await server.isAuthenticated(connectionId)
                guard isAuth else { return }
                await MainActor.run {
                    self.routeAuthenticatedMessage(message, from: connectionId)
                }
            }
        }
    }

    private func routeAuthenticatedMessage(_ message: Message, from connectionId: String) {
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
            if let idx = connectedDevices.firstIndex(where: { $0.connectionId == connectionId }) {
                connectedDevices[idx].deviceInfo = info
            }
        case .wallpaperResponse(let imageBase64):
            if let idx = connectedDevices.firstIndex(where: { $0.connectionId == connectionId }) {
                connectedDevices[idx].wallpaper = imageBase64.isEmpty ? nil : Data(base64Encoded: imageBase64)
            }
        case .macFilesListRequest, .macFileThumbnailRequest, .macFolderStatsRequest, .macFileDownloadRequest:
            macFilesService.handle(message, connectionId: connectionId)
        case .macInfoRequest:
            let info = MacSystemInfo.collect()
            Task { try? await server.sendTo(.macInfoResponse(info: info), connectionId: connectionId) }
        case .macWallpaperRequest:
            let image = MacSystemInfo.wallpaperJPEGBase64()
            Task { try? await server.sendTo(.macWallpaperResponse(imageBase64: image), connectionId: connectionId) }
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
                // `endpoint` is the connectionId ("host:port") — drop just that device,
                // leaving any other connected phones intact.
                self.connectedDevices.removeAll { $0.connectionId == endpoint }
                self.refreshAllowedUploadHosts()
                self.ensureActiveDeviceValid()
                Diag.log("Connection", "client disconnected: \(endpoint) — remaining=\(self.connectedDevices.count)")
                if self.connectedDevices.isEmpty {
                    // Dismiss any incoming-file popup orphaned by the dropped link.
                    self.fileTransferService?.connectionLost()
                    if !self.manuallyDisconnected {
                        self.statusMessage = L10n.isPL ? "Oczekiwanie na połączenie" : "Waiting for connection"
                        self.phase = .listening
                    }
                }
            }
        }
        await server.setCallbacks(
            onMessage: onMessage,
            onClientConnected: onConnect,
            onClientDisconnected: onDisconnect
        )
        await server.setDiagnostic { Diag.log("WS", $0) }
    }

    // MARK: - Mirror Helpers

    func currentPairingTokenString() -> String? {
        pairingService?.currentTokenData()?.base64EncodedString()
    }

    /// Hands the persistent TLS identity to the mirror service. Must run
    /// BEFORE `mirrorService.start()` — without an identity the mirror server
    /// refuses to start (main channels are unaffected).
    func provideMirrorTLSIdentity() {
        do {
            mirrorService?.tlsIdentity = try tlsIdentityManager.identity()
        } catch {
            NSLog("[ConnectionService] Mirror TLS identity unavailable: \(error)")
        }
    }

    // MARK: - Helpers

    func getConnectedClientIP() -> String? {
        primaryDevice?.clientIP
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
                address = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                break
            }
        }
        return address
    }
}

// MARK: - AllowedSenderStore

/// Lock-protected set of IPs allowed to upload — one per connected phone. The
/// MainActor-bound `ConnectionService` writes it; the `HttpUploadServer` actor
/// reads it from the sender-validator closure, so it must be `Sendable` and
/// thread-safe.
final class AllowedSenderStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _hosts: Set<String> = []
    var hosts: Set<String> {
        get { lock.withLock { _hosts } }
        set { lock.withLock { _hosts = newValue } }
    }
    func contains(_ host: String) -> Bool {
        lock.withLock { _hosts.contains(host) }
    }
}
