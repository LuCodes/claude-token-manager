import AppKit

/// Pure AppKit entry point — no SwiftUI App, no phantom Settings window.
@main
@MainActor
enum AppEntry {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate

        // Kill other instances
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for other in others { other.terminate() }

        delegate.statusBar.setup()

        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusBar = StatusBarController()
}
