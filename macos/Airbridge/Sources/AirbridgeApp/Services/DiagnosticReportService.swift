import Foundation

/// Builds the one-file diagnostic report the user can attach to a bug report.
/// Pure input → string composition lives in `DiagnosticReport` so it is unit
/// testable; the `DiagnosticReportService` wrapper only gathers live state.
/// The report never includes keys or tokens — local IP addresses are fine.
enum DiagnosticReport {

    /// Read-only snapshot of one connected phone.
    struct DeviceSummary {
        let name: String
        let ip: String?
        let appVersion: String?
        let isActive: Bool
    }

    struct Input {
        let appVersion: String
        let buildNumber: String
        let macOSVersion: String
        let phase: String
        let statusMessage: String
        let devices: [DeviceSummary]
        let logTail: [String]
    }

    static let maxLogLines = 500

    static func compose(_ input: Input, now: Date = Date()) -> String {
        let timestampFormatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("AirBridge diagnostic report (macOS)")
        lines.append("Generated: \(timestampFormatter.string(from: now))")
        lines.append("")
        lines.append("== App ==")
        lines.append("App version: \(input.appVersion) (\(input.buildNumber))")
        lines.append("macOS: \(input.macOSVersion)")
        lines.append("")
        lines.append("== Connection ==")
        lines.append("Phase: \(input.phase)")
        lines.append("Status: \(input.statusMessage)")
        lines.append("Connected devices: \(input.devices.count)")
        for device in input.devices {
            var parts = [device.name]
            if let ip = device.ip { parts.append(ip) }
            if let version = device.appVersion { parts.append("app \(version)") }
            if device.isActive { parts.append("active") }
            lines.append("- " + parts.joined(separator: " | "))
        }
        lines.append("")
        lines.append("== diagnostics.log (last \(maxLogLines) lines) ==")
        if input.logTail.isEmpty {
            lines.append("(no log entries)")
        } else {
            lines.append(contentsOf: input.logTail)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Last `maxLines` lines of `text`, ignoring a trailing newline.
    static func tail(_ text: String, maxLines: Int = maxLogLines) -> [String] {
        guard !text.isEmpty else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let trimmed = lines.last == "" ? lines.dropLast() : lines[...]
        return Array(trimmed.suffix(maxLines))
    }

    static func suggestedFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "airbridge-diagnostics-\(formatter.string(from: now)).txt"
    }
}

@MainActor
enum DiagnosticReportService {

    /// Snapshots live app state and composes the report text.
    static func makeReport(connectionService: ConnectionService) -> String {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        let devices = connectionService.connectedDevices.map { device in
            DiagnosticReport.DeviceSummary(
                name: device.name,
                ip: device.clientIP,
                appVersion: device.deviceInfo?.appVersion,
                isActive: device.connectionId == connectionService.activeDevice?.connectionId
            )
        }

        let logText = (try? String(contentsOf: Diag.fileURL, encoding: .utf8)) ?? ""

        let input = DiagnosticReport.Input(
            appVersion: appVersion,
            buildNumber: buildNumber,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            phase: String(describing: connectionService.phase),
            statusMessage: connectionService.statusMessage,
            devices: devices,
            logTail: DiagnosticReport.tail(logText)
        )
        return DiagnosticReport.compose(input)
    }
}
