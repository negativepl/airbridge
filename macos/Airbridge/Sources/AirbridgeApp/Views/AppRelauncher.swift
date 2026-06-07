import AppKit

enum AppRelauncher {
    /// Relaunch the app. Spawns a detached `open` after a short delay (so this
    /// instance can release its listeners/ports first), then terminates.
    ///
    /// Needed because `AXIsProcessTrusted()` is cached per-process: a freshly
    /// granted Accessibility permission only takes effect in a new process. So
    /// after the user grants Accessibility we restart to pick it up.
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
