import SwiftUI
import ClaudeTokenManagerCore

@main
struct ClaudeTokenManagerApp: App {
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

struct MenuBarLabel: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon", bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
            Text(store.compactLabel)
                .font(AppFont.inter(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundColor(store.menuBarTint)
    }
}
