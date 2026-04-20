import SwiftUI
import ClaudeTokenManagerCore

struct PreferencesView: View {
    @EnvironmentObject var store: UsageStore
    @Binding var isOpen: Bool
    @State private var budgetText: String = ""

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
            Text("v0.3.0")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}
