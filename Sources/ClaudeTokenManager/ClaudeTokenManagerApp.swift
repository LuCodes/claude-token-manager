import SwiftUI
import AppKit

@main
struct ClaudeTokenManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusBar = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Kill other instances
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for app in others { app.terminate() }

        statusBar.setup()
    }
}
