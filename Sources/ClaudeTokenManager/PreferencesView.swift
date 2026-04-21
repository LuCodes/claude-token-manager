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
    @StateObject private var webSession = ClaudeWebSession.shared
    var onClose: (() -> Void)?

    @State private var customPathInput: String = ClaudeProjectsPathResolver.userConfiguredPath() ?? ""
    @State private var customPathFeedback: String = ""
    @State private var customPathIsValid: Bool = false
    @State private var isLoggingOut: Bool = false

    private let tintBlue = Color(red: 55/255, green: 138/255, blue: 221/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            budgetCard
            launchAtLoginCard
            claudeAISyncCard
            projectsPathCard
            infoCard
            Divider().background(Color.white.opacity(0.08))
            footer
        }
        .padding(16)
        .background(Color(red: 31/255, green: 31/255, blue: 30/255))
        .foregroundColor(Color(red: 241/255, green: 239/255, blue: 232/255))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { onClose?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                    Text("Back").font(AppFont.inter(size: 12))
                }.foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Spacer()
            Text("Preferences")
                .font(AppFont.inter(size: 14, weight: .semibold))
            Spacer()
            Spacer().frame(width: 60)
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
            }

            Divider().background(Color.white.opacity(0.1))

            if webSession.isAuthenticated {
                connectedView
            } else {
                signInView
            }

            if let err = webSession.lastError, webSession.isAuthenticated {
                Text(err)
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(Color(red: 216/255, green: 90/255, blue: 48/255))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .preferenceCard()
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 29/255, green: 158/255, blue: 117/255))
                    .frame(width: 8, height: 8)
                Text("Connected to claude.ai")
                    .font(AppFont.inter(size: 12, weight: .medium))
                Spacer()
            }

            if let orgId = webSession.organizationId {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organization")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    Text(maskOrgId(orgId))
                        .font(AppFont.inter(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .cornerRadius(5)
            }

            Button(action: signOut) {
                Text(isLoggingOut ? "Signing out..." : "Sign out")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(isLoggingOut)
        }
    }

    private var signInView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 239/255, green: 159/255, blue: 39/255))
                    .frame(width: 8, height: 8)
                Text("Not connected")
                    .font(AppFont.inter(size: 12, weight: .medium))
                Spacer()
            }

            Text("Sign in once with your claude.ai account. Credentials never leave your Mac — we use a hidden browser window scoped to this app.")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: signIn) {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 10))
                    Text("Sign in to claude.ai")
                        .font(AppFont.inter(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 217/255, green: 119/255, blue: 87/255))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    private func signIn() {
        ClaudeLoginWindowController.present(session: webSession) { success in
            if success { store.refresh() }
        }
    }

    private func signOut() {
        isLoggingOut = true
        Task {
            await webSession.logout()
            await MainActor.run {
                isLoggingOut = false
                store.refresh()
            }
        }
    }

    private func maskOrgId(_ orgId: String) -> String {
        guard orgId.count > 6 else { return orgId }
        let visible = String(orgId.suffix(6))
        let hidden = String(repeating: "\u{2022}", count: orgId.count - 6)
        return hidden + visible
    }

    // MARK: - Projects path

    private var projectsPathCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Code projects folder")
                .font(AppFont.inter(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text("Where Claude Code stores your project logs (.jsonl files)")
                .font(AppFont.inter(size: 11))
                .foregroundColor(.white.opacity(0.5))

            if let resolved = ClaudeProjectsPathResolver.resolve() {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 29/255, green: 158/255, blue: 117/255))
                        .frame(width: 6, height: 6)
                    Text("Detected: \(resolved.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 239/255, green: 159/255, blue: 39/255))
                        .frame(width: 6, height: 6)
                    Text("No projects folder detected")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom folder (optional)")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                HStack(spacing: 6) {
                    TextField("e.g. ~/Documents/Claude", text: $customPathInput)
                        .textFieldStyle(.plain)
                        .font(AppFont.inter(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    Button("Save") { saveCustomPath() }
                        .buttonStyle(.plain)
                        .font(AppFont.inter(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 55/255, green: 138/255, blue: 221/255))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                        .focusable(false)
                }
            }

            if !customPathFeedback.isEmpty {
                Text(customPathFeedback)
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(
                        customPathIsValid
                            ? Color(red: 29/255, green: 158/255, blue: 117/255)
                            : Color(red: 216/255, green: 90/255, blue: 48/255)
                    )
            }
        }
        .preferenceCard()
    }

    private func saveCustomPath() {
        let trimmed = customPathInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            ClaudeProjectsPathResolver.setUserConfiguredPath(nil)
            customPathFeedback = "Custom path cleared, using auto-detection"
            customPathIsValid = true
            store.startWatching()
            store.refresh()
            return
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir),
              isDir.boolValue else {
            customPathFeedback = "Folder does not exist"
            customPathIsValid = false
            return
        }

        ClaudeProjectsPathResolver.setUserConfiguredPath(trimmed)
        customPathFeedback = "Saved. Rescan in progress..."
        customPathIsValid = true
        store.startWatching()
        store.refresh()
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
