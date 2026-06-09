import Foundation
import Network

/// Watches the Mac's network path and fires [onChange] when it moves to a
/// different network (e.g. work Wi-Fi -> home Wi-Fi), so the WebSocket listener
/// and Bonjour service can be re-advertised on the new address.
///
/// A network switch is detected either by a satisfied->unsatisfied->satisfied
/// transition or by a change in the network identity (interfaces + gateways).
/// The very first satisfied path is the baseline and does not fire. Updates are
/// debounced because a single switch emits several path callbacks.
///
/// All mutable state is touched only on the private monitor queue; start()/stop()
/// are safe to call from the main actor.
final class NetworkChangeMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.airbridge.networkmonitor")
    private let onChange: @Sendable () -> Void

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
            return
        }

        let key = networkKey(path)
        let isBaseline = baselineKey == nil
        let changed = !isBaseline && (sawUnsatisfied || key != baselineKey)
        sawUnsatisfied = false
        baselineKey = key

        guard changed else { return }

        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func networkKey(_ path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map(\.name).sorted()
        let gateways = path.gateways.map { "\($0)" }.sorted()
        return (interfaces + gateways).joined(separator: "|")
    }
}
