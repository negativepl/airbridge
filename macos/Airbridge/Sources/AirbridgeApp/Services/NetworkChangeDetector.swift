import Foundation

/// Pure decision core of NetworkChangeMonitor: fed a stream of path snapshots
/// (satisfied? + network identity key), answers which one is a real network
/// switch. The first satisfied snapshot is the baseline and never fires; a
/// switch is a key change OR a satisfied -> unsatisfied -> satisfied bounce.
struct NetworkChangeDetector {
    private(set) var baselineKey: String?
    private(set) var sawUnsatisfied = false

    /// Returns true when the snapshot represents a real network change and the
    /// service should re-advertise. `key` is an autoclosure because computing
    /// it (getifaddrs) is pointless for unsatisfied paths.
    mutating func register(satisfied: Bool, key: @autoclosure () -> String) -> Bool {
        guard satisfied else {
            sawUnsatisfied = true
            return false
        }
        let key = key()
        let isBaseline = baselineKey == nil
        let changed = !isBaseline && (sawUnsatisfied || key != baselineKey)
        sawUnsatisfied = false
        baselineKey = key
        return changed
    }
}
