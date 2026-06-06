import Foundation
import AppKit
import IOKit.ps
import Protocol

/// Collects the Mac's own system info + wallpaper so the phone can act as a
/// resource monitor / controller for the computer.
enum MacSystemInfo {

    static func collect() -> MacInfo {
        let pi = ProcessInfo.processInfo
        let total = Int64(pi.physicalMemory)
        let (used, _) = ramUsage(total: total)
        let (storageTotal, storageFree) = storage()
        let battery = batteryInfo()

        return MacInfo(
            name: Host.current().localizedName ?? pi.hostName,
            model: friendlyModel(),
            chip: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            osVersion: "macOS \(pi.operatingSystemVersion.majorVersion).\(pi.operatingSystemVersion.minorVersion)",
            cpuCores: pi.processorCount,
            cpuLoadPercent: CPUSampler.shared.sample(),
            totalRamBytes: total,
            usedRamBytes: used,
            totalStorageBytes: storageTotal,
            freeStorageBytes: storageFree,
            batteryPercent: battery.percent,
            batteryCharging: battery.charging,
            onACPower: battery.ac,
            uptimeSeconds: Int64(pi.systemUptime)
        )
    }

    /// The desktop wallpaper as base64 JPEG (empty string if unavailable).
    static func wallpaperJPEGBase64() -> String {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return "" }

        // Downscale to a sane size for the phone.
        let maxLong: CGFloat = 900
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        let scale = max(w, h) > maxLong ? maxLong / max(w, h) : 1.0
        let outW = Int(w * scale), outH = Int(h * scale)

        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return "" }
        resized.size = NSSize(width: outW, height: outH)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        image.draw(in: NSRect(x: 0, y: 0, width: outW, height: outH))
        NSGraphicsContext.restoreGraphicsState()

        guard let jpeg = resized.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return "" }
        return jpeg.base64EncodedString()
    }

    // MARK: - Helpers

    private static func ramUsage(total: Int64) -> (used: Int64, free: Int64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Int64(pageSize)
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return (used, max(0, total - used))
    }

    private static func storage() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let total = values.volumeTotalCapacity {
            let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            return (Int64(total), free)
        }
        return (0, 0)
    }

    private static func batteryInfo() -> (percent: Int, charging: Bool, ac: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return (-1, false, true) }
        for src in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, src)?.takeUnretainedValue() as? [String: Any],
               let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int {
                let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                let state = desc[kIOPSPowerSourceStateKey as String] as? String
                let ac = (state == (kIOPSACPowerValue as String))
                return (capacity, charging, ac)
            }
        }
        return (-1, false, true)   // no battery = desktop on AC
    }

    private static func friendlyModel() -> String {
        let id = sysctlString("hw.model") ?? "Mac"
        switch true {
        case id.hasPrefix("MacBookPro"): return "MacBook Pro"
        case id.hasPrefix("MacBookAir"): return "MacBook Air"
        case id.hasPrefix("MacBook"):    return "MacBook"
        case id.hasPrefix("Macmini"):    return "Mac mini"
        case id.hasPrefix("MacStudio"):  return "Mac Studio"
        case id.hasPrefix("MacPro"):     return "Mac Pro"
        case id.hasPrefix("iMac"):       return "iMac"
        default:                         return "Mac"
        }
    }

    /// Live CPU usage via deltas of host CPU tick counters.
    final class CPUSampler: @unchecked Sendable {
        static let shared = CPUSampler()
        private let lock = NSLock()
        private var prevBusy: UInt64 = 0
        private var prevTotal: UInt64 = 0

        func sample() -> Int {
            var info = host_cpu_load_info()
            var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
                }
            }
            guard kr == KERN_SUCCESS else { return 0 }
            let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
            let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
            let busy = user &+ system &+ nice
            let total = busy &+ idle

            lock.lock(); defer { lock.unlock() }
            let dBusy = busy &- prevBusy
            let dTotal = total &- prevTotal
            prevBusy = busy; prevTotal = total
            guard dTotal > 0 else { return 0 }
            return min(100, max(0, Int((Double(dBusy) / Double(dTotal) * 100).rounded())))
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
