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
            Image("MenuBarIcon", bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
            Text(labelText)
                .font(AppFont.inter(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundColor(labelColor)
    }

    private var labelText: String {
        if let hottest = store.snapshot.hottestRemoteBar {
            return "\(Int(hottest.clampedPercent.rounded(.down))) %"
        }
        return store.compactLabel
    }

    private var labelColor: Color {
        guard let hottest = store.snapshot.hottestRemoteBar else {
            return store.menuBarTint
        }
        if hottest.percent >= 95 { return Color(red: 216/255, green: 90/255, blue: 48/255) }
        if hottest.percent >= 80 { return Color(red: 239/255, green: 159/255, blue: 39/255) }
        return .primary
    }
}
