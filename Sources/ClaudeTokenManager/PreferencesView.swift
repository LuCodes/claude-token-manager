import SwiftUI
import ClaudeTokenManagerCore

struct PreferencesView: View {
    @EnvironmentObject var store: UsageStore
    @Binding var isOpen: Bool
    @State private var budgetText: String = ""
    @State private var orgIdInput: String = ""
    @State private var sessionKeyInput: String = ""
    @State private var isTesting: Bool = false

    private let tintBlue = Color(red: 55/255, green: 138/255, blue: 221/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 14)
            displayFormatCard
            Spacer().frame(height: 10)
            budgetCard
            Spacer().frame(height: 10)
            launchAtLoginCard
            Spacer().frame(height: 10)
            claudeAISyncCard
            Spacer().frame(height: 10)
            infoCard
            Spacer().frame(height: 14)
            Divider().background(Color.white.opacity(0.08))
            Spacer().frame(height: 10)
            footer
        }
        .onAppear {
            if let v = store.dailyBudgetValue {
                budgetText = String(format: "%.0f", v)
            }
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
                    Text("Retour").font(AppFont.inter(size: 12))
                }.foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
            Spacer()
            Text("Pr\u{00E9}f\u{00E9}rences")
                .font(AppFont.inter(size: 13, weight: .medium))
            Spacer()
            Spacer().frame(width: 56)
        }
    }

    // MARK: - Display format

    private var displayFormatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Format d'affichage")
                .font(AppFont.inter(size: 12, weight: .medium))
            SegmentedToggle(
                options: [
                    (value: DisplayFormat.cost, label: "Co\u{00FB}t API"),
                    (value: DisplayFormat.tokens, label: "Tokens")
                ],
                selection: $store.displayFormat
            )
            Text("Affiche les co\u{00FB}ts ou les tokens bruts partout dans l'app")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Budget

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Budget quotidien")
                    .font(AppFont.inter(size: 12, weight: .medium))
                Spacer()
                HStack(spacing: 2) {
                    Text(store.dailyBudgetIsMoney ? "$" : "tk")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    TextField("", text: $budgetText)
                        .font(AppFont.inter(size: 12))
                        .textFieldStyle(.plain)
                        .frame(width: 60)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: budgetText) { newValue in
                            if newValue.isEmpty {
                                store.dailyBudgetValue = nil
                            } else if let v = Double(newValue), v > 0 {
                                store.dailyBudgetValue = v
                            }
                        }
                }
            }
            SegmentedToggle(
                options: [
                    (value: true, label: "$"),
                    (value: false, label: "tokens")
                ],
                selection: $store.dailyBudgetIsMoney
            )
            Text("Te pr\u{00E9}viens \u{00E0} 80 % et 95 % de ton budget. Laisser vide pour d\u{00E9}sactiver.")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Launch at login

    private var launchAtLoginCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lancer au d\u{00E9}marrage")
                        .font(AppFont.inter(size: 12, weight: .medium))
                    Text("L'ic\u{00F4}ne appara\u{00EE}tra dans la barre de menu \u{00E0} chaque ouverture de session")
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
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Claude.ai sync

    private var claudeAISyncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Synchro claude.ai (beta)")
                        .font(AppFont.inter(size: 12, weight: .medium))
                    Text("Affiche les vraies limites de ton forfait au lieu des estimations locales")
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
                   store.claudeAIConnectionStatus == .connected {
                    connectedView
                } else {
                    credentialsForm
                }

                Link(destination: URL(string: "https://github.com/LuCodes/claude-token-manager/blob/main/docs/CLAUDE_AI_SYNC.md")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle").font(.system(size: 10))
                        Text("Comment r\u{00E9}cup\u{00E9}rer ces valeurs ?")
                            .font(AppFont.inter(size: 10))
                    }
                    .foregroundColor(tintBlue)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 239/255, green: 159/255, blue: 39/255))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ton cookie donne un acc\u{00E8}s complet \u{00E0} ton compte claude.ai")
                        .font(AppFont.inter(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 239/255, green: 159/255, blue: 39/255))
                    Text("Ne le partage jamais. Utilise une API non-document\u{00E9}e \u{00E0} tes risques.")
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
                TextField("ex: abc-123-def-456", text: $orgIdInput)
                    .textFieldStyle(.plain)
                    .font(AppFont.inter(size: 11))
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Cookie de session")
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
                    Text(isTesting ? "Test en cours..." : "Tester et enregistrer")
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
                Text("Connect\u{00E9} \u{00E0} claude.ai")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button("D\u{00E9}connecter") {
                store.clearClaudeAICredentials()
                orgIdInput = ""
                sessionKeyInput = ""
            }
            .buttonStyle(.plain)
            .font(AppFont.inter(size: 10))
            .foregroundColor(.white.opacity(0.5))
        }
    }

    private var statusText: String? {
        switch store.claudeAIConnectionStatus {
        case .unknown: return nil
        case .testing: return "Test en cours..."
        case .connected: return "Connect\u{00E9}"
        case .expired: return "Session expir\u{00E9}e, recolle ton cookie"
        case .error(let msg): return "Erreur : \(msg)"
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
                }
            }
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source des donn\u{00E9}es")
                .font(AppFont.inter(size: 11, weight: .medium))
            Text("Logs locaux de Claude Code (~/.claude/projects)")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text("Les chiffres sont mesur\u{00E9}s depuis tes logs Claude Code. Les co\u{00FB}ts sont calcul\u{00E9}s aux tarifs API Anthropic. Si tu es en abonnement Pro/Max, ton co\u{00FB}t r\u{00E9}el est le prix fixe de ton forfait.")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                if let url = URL(string: "https://claude.ai/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Ouvrir claude.ai pour voir mes limites de forfait \u{2192}")
                    .font(AppFont.inter(size: 10, weight: .medium))
                    .foregroundColor(tintBlue)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if AppFont.isInterAvailable {
                Text("Police : Inter")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Link("Installer Inter",
                     destination: URL(string: "https://rsms.me/inter/")!)
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(tintBlue)
            }
            Spacer()
            Text("v1.2.0")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}
