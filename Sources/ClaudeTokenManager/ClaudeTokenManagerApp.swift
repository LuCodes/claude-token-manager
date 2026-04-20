import SwiftUI
import AppKit
import ClaudeTokenManagerCore

@main
struct ClaudeTokenManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            DropdownView()
                .environmentObject(store)
                .frame(width: 380)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for app in others { app.terminate() }
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: loadMenuBarIcon())
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
            Text(labelText)
                .font(AppFont.inter(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundColor(labelColor)
    }

    /// In claude.ai mode, always show the Session (5h) bar — it's the most
    /// actionable metric since it resets frequently.
    private var sessionBar: RemoteProgressBar? {
        store.snapshot.remoteProgressBars.first { $0.id == "session" }
    }

    private var labelText: String {
        if let session = sessionBar {
            return String(format: "%d%%", Int(session.clampedPercent.rounded(.down)))
        }
        return store.compactLabel
    }

    private var labelColor: Color {
        guard let session = sessionBar else {
            return store.menuBarTint
        }
        if session.percent >= 95 { return Color(red: 216/255, green: 90/255, blue: 48/255) }
        if session.percent >= 80 { return Color(red: 239/255, green: 159/255, blue: 39/255) }
        return .primary
    }

    private func loadMenuBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
