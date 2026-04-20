import SwiftUI
import ClaudeTokenManagerCore

// MARK: - Card style modifier

private struct PreferenceCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    fileprivate func preferenceCard() -> some View {
        self.modifier(PreferenceCardStyle())
    }
}

// MARK: - PreferencesView

struct PreferencesView: View {
    @EnvironmentObject var store: UsageStore
    @Binding var isOpen: Bool
    @State private var orgIdInput: String = ""
    @State private var sessionKeyInput: String = ""
    @State private var isTesting: Bool = false
    @State private var isEditing: Bool = false

    private let tintBlue = Color(red: 55/255, green: 138/255, blue: 221/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            budgetCard
            launchAtLoginCard
            claudeAISyncCard
            infoCard
            Divider().background(Color.white.opacity(0.08))
            footer
        }
        .onAppear {
            if let orgId = ClaudeAIDataSource.loadOrgId() {
                orgIdInput = orgId
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { isOpen = false }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                    Text("Back").font(AppFont.inter(size: 12))
                }.foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Spacer()
            Text("Preferences")
                .font(AppFont.inter(size: 13, weight: .medium))
            Spacer()
            Spacer().frame(width: 56)
        }
    }

    // MARK: - Budget

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            BudgetSlider(
                value: Binding(
                    get: { store.dailyBudgetValue ?? 0 },
                    set: { newValue in
                        store.dailyBudgetValue = newValue > 0 ? newValue : nil
                    }
                ),
                maxValue: 20,
                step: 1
            )
        }
        .preferenceCard()
    }

    // MARK: - Launch at login

    private var launchAtLoginCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Launch at login")
                    .font(AppFont.inter(size: 12, weight: .medium))
                Text("The icon will appear in the menu bar on every login")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Toggle("", isOn: $store.launchAtLoginEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tintBlue)
                .onChange(of: store.launchAtLoginEnabled) { newValue in
                    LoginItem.setEnabled(newValue)
                }
        }
        .preferenceCard()
    }

    // MARK: - Claude.ai sync

    private var claudeAISyncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("claude.ai sync (beta)")
                        .font(AppFont.inter(size: 12, weight: .medium))
                    Text("Shows your real plan limits instead of local estimates")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.claudeAIModeEnabled },
                    set: { store.setClaudeAIMode(enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tintBlue)
            }

            if store.claudeAIModeEnabled {
                Divider().background(Color.white.opacity(0.1))

                if ClaudeAIDataSource.hasStoredCredentials() &&
                   store.claudeAIConnectionStatus == .connected && !isEditing {
                    connectedView
                } else {
                    credentialsForm
                }

                Link(destination: URL(string: "https://github.com/LuCodes/claude-token-manager/blob/main/docs/CLAUDE_AI_SYNC.md")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle").font(.system(size: 10))
                        Text("How to get these values?")
                            .font(AppFont.inter(size: 10))
                    }
                    .foregroundColor(tintBlue)
                }
            }
        }
        .preferenceCard()
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 239/255, green: 159/255, blue: 39/255))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your cookie gives full access to your claude.ai account")
                        .font(AppFont.inter(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 239/255, green: 159/255, blue: 39/255))
                    Text("Never share it. Uses an undocumented API at your own risk.")
                        .font(AppFont.inter(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .background(Color(red: 239/255, green: 159/255, blue: 39/255).opacity(0.08))
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 3) {
                Text("Organization ID")
                    .font(AppFont.inter(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                TextField("e.g. abc-123-def-456", text: $orgIdInput)
                    .textFieldStyle(.plain)
                    .font(AppFont.inter(size: 11))
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Session cookie")
                    .font(AppFont.inter(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                SecureField("sessionKey=...", text: $sessionKeyInput)
                    .textFieldStyle(.plain)
                    .font(AppFont.inter(size: 11))
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }

            HStack {
                if let status = statusText {
                    HStack(spacing: 4) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                        Text(status)
                            .font(AppFont.inter(size: 10))
                            .foregroundColor(statusColor)
                    }
                }
                Spacer()
                Button(action: testConnection) {
                    Text(isTesting ? "Testing..." : "Test & save")
                        .font(AppFont.inter(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            (orgIdInput.isEmpty || sessionKeyInput.isEmpty || isTesting)
                                ? Color.gray.opacity(0.3)
                                : tintBlue
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(orgIdInput.isEmpty || sessionKeyInput.isEmpty || isTesting)
            }
        }
    }

    private var connectedView: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 29/255, green: 158/255, blue: 117/255))
                    .frame(width: 8, height: 8)
                Text("Connected to claude.ai")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button("Edit") { isEditing = true }
                .buttonStyle(.plain)
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.5))

            Button("Disconnect") {
                store.clearClaudeAICredentials()
                orgIdInput = ""
                sessionKeyInput = ""
                isEditing = false
            }
            .buttonStyle(.plain)
            .font(AppFont.inter(size: 10))
            .foregroundColor(.white.opacity(0.5))
        }
    }

    private var statusText: String? {
        switch store.claudeAIConnectionStatus {
        case .unknown: return nil
        case .testing: return "Testing..."
        case .connected: return "Connected"
        case .expired: return "Session expired, paste your cookie again"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch store.claudeAIConnectionStatus {
        case .connected: return Color(red: 29/255, green: 158/255, blue: 117/255)
        case .expired, .error: return Color(red: 216/255, green: 90/255, blue: 48/255)
        default: return Color.white.opacity(0.5)
        }
    }

    private func testConnection() {
        isTesting = true
        Task {
            await store.testAndSaveClaudeAICredentials(
                orgId: orgIdInput, sessionKey: sessionKeyInput
            )
            await MainActor.run {
                isTesting = false
                NSPasteboard.general.clearContents()
                if store.claudeAIConnectionStatus == .connected {
                    sessionKeyInput = ""
                    orgIdInput = ""
                    isEditing = false
                }
            }
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data source")
                .font(AppFont.inter(size: 11, weight: .medium))
            Text("Local logs from Claude Code (~/.claude/projects)")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text("Figures are measured from your Claude Code logs. Costs are calculated at Anthropic API rates. If you are on a Pro/Max subscription, your real cost is the fixed price of your plan.")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                if let url = URL(string: "https://claude.ai/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Open claude.ai to view my plan limits \u{2192}")
                    .font(AppFont.inter(size: 10, weight: .medium))
                    .foregroundColor(tintBlue)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .preferenceCard()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Made with love \u{2661} thx Claude")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text("v\(appVersion)")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }
}
