import Foundation
import Network
import os

/// Watches the Mac's network path and fires [onChange] when it moves to a
/// different network (e.g. work Wi-Fi -> home Wi-Fi), so the WebSocket listener
/// and Bonjour service can be re-advertised on the new address.
///
/// A network switch is detected either by a satisfied->unsatisfied->satisfied
/// transition or by a change in the network identity (interfaces + gateways +
/// the Mac's own assigned addresses). The assigned address matters: two
/// networks can share the interface name and the default gateway (192.168.1.1
/// is everywhere), so a smooth roam between them changes nothing but our IP —
/// without it in the key the switch is invisible and Bonjour keeps
/// advertising the stale address.
/// The very first satisfied path is the baseline and does not fire. Updates are
/// debounced because a single switch emits several path callbacks.
///
/// All mutable state is touched only on the private monitor queue; start()/stop()
/// are safe to call from the main actor.
final class NetworkChangeMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.airbridge.networkmonitor")
    private let onChange: @Sendable () -> Void
    private let log = Logger(subsystem: "com.airbridge.macos", category: "NetworkChange")

    private var baselineKey: String?
    private var sawUnsatisfied = false
    private var debounce: DispatchWorkItem?
    private var started = false

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handle(path)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        monitor.cancel()
        started = false
    }

    private func handle(_ path: NWPath) {
        guard path.status == .satisfied else {
            sawUnsatisfied = true
            log.notice("path unsatisfied (status=\(String(describing: path.status), privacy: .public))")
            Diag.log("NetworkChange", "path unsatisfied (status=\(path.status))")
            return
        }

        let key = networkKey(path)
        let isBaseline = baselineKey == nil
        let changed = !isBaseline && (sawUnsatisfied || key != baselineKey)
        sawUnsatisfied = false
        baselineKey = key

        // Only log a real transition — the per-callback "satisfied" path updates
        // fire every few seconds and would otherwise flood the log.
        guard changed else { return }
        log.notice("network changed -> \(key, privacy: .public)")
        Diag.log("NetworkChange", "network changed -> \(key); re-advertising")

        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.log.notice("debounce fired -> onChange()")
            Diag.log("NetworkChange", "debounce fired -> onChange()")
            self?.onChange()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func networkKey(_ path: NWPath) -> String {
        let interfaceNames = path.availableInterfaces.map(\.name)
        let interfaces = interfaceNames.sorted()
        let gateways = path.gateways.map { "\($0)" }.sorted()
        let addresses = Self.localIPv4Addresses(forInterfaces: Set(interfaceNames)).sorted()
        return (interfaces + gateways + addresses).joined(separator: "|")
    }

    /// IPv4 addresses currently assigned to the given interfaces. IPv6 is left
    /// out on purpose: privacy/temporary addresses rotate without a network
    /// change and would make the key flap.
    private static func localIPv4Addresses(forInterfaces names: Set<String>) -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let addr = interface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  names.contains(String(cString: interface.ifa_name)) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 {
                addresses.append(hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
            }
        }
        return addresses
    }
}
