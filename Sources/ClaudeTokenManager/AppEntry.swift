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

        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusBar = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup AFTER the run loop is up so NSStatusItem's button is fully
        // attached to the system status bar window. Calling setup() before
        // app.run() leaves button.window nil at first popover.show(), which
        // anchors the popover at screen origin instead of under the icon.
        statusBar.setup()
    }
}
