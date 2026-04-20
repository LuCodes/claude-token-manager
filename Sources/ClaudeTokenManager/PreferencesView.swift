import SwiftUI
import ClaudeTokenManagerCore

struct PreferencesView: View {
    @EnvironmentObject var store: UsageStore
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 14)
            notificationsCard
            Spacer().frame(height: 10)
            infoCard
            Spacer().frame(height: 14)
            Divider().background(Color.white.opacity(0.08))
            Spacer().frame(height: 10)
            footer
        }
    }

    private var header: some View {
        HStack {
            Button(action: { isOpen = false }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                    Text("Retour").font(AppFont.inter(size: 12))
                }
                .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Préférences")
                .font(AppFont.inter(size: 13, weight: .medium))
            Spacer()
            Spacer().frame(width: 56) // balance for centered title
        }
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Alertes à 80 % et 95 %")
                        .font(AppFont.inter(size: 12, weight: .medium))
                    Text("Notification discrète quand une limite approche")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Toggle("", isOn: $store.notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color(red: 55/255, green: 138/255, blue: 221/255))
            }

            if store.notificationsEnabled {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 239/255, green: 159/255, blue: 39/255))
                        .frame(width: 6, height: 6)
                    Text("80 % : premier avertissement")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 216/255, green: 90/255, blue: 48/255))
                        .frame(width: 6, height: 6)
                    Text("95 % : limite presque atteinte")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text("Une seule notification par palier et par période de reset.")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Source des données")
                    .font(AppFont.inter(size: 11, weight: .medium))
                Spacer()
            }
            Text("Logs locaux de Claude Code (~/.claude/projects)")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text("Les pourcentages sont des estimations basées sur les seuils annoncés pour le forfait \(store.selectedPlan.rawValue).")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            if AppFont.isInterAvailable {
                Text("Police : Inter")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Link("Installer Inter pour une meilleure typographie",
                     destination: URL(string: "https://rsms.me/inter/")!)
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(Color(red: 55/255, green: 138/255, blue: 221/255))
            }
            Spacer()
            Text("v0.1.0")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}
