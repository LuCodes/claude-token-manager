import SwiftUI
import ClaudeTokenManagerCore

struct DropdownView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showingPreferences = false

    private let bg = Color(red: 31/255, green: 31/255, blue: 30/255)
    private let fg = Color(red: 241/255, green: 239/255, blue: 232/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingPreferences {
                PreferencesView(isOpen: $showingPreferences)
                    .environmentObject(store)
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(bg)
        .foregroundColor(fg)
        .animation(.easeInOut(duration: 0.15), value: showingPreferences)
    }

    // MARK: - Main

    @ViewBuilder
    private var mainContent: some View {
        header
        if store.claudeAIModeEnabled && store.claudeAIConnectionStatus == .connected {
            Spacer().frame(height: 6)
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 29/255, green: 158/255, blue: 117/255))
                    .frame(width: 6, height: 6)
                Text("Chiffres r\u{00E9}els claude.ai")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(red: 29/255, green: 158/255, blue: 117/255).opacity(0.1))
            .cornerRadius(6)
        } else if store.claudeAIModeEnabled && store.claudeAIConnectionStatus == .expired {
            Spacer().frame(height: 6)
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 216/255, green: 90/255, blue: 48/255))
                    .frame(width: 6, height: 6)
                Text("Session claude.ai expir\u{00E9}e")
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(Color(red: 216/255, green: 90/255, blue: 48/255))
            }
        }
        Spacer().frame(height: 12)
        projectMenu
        Spacer().frame(height: 14)
        sectionTitle("Aujourd'hui")
        Spacer().frame(height: 8)
        todayBigCard
        Spacer().frame(height: 12)
        sectionTitle("R\u{00E9}partition par mod\u{00E8}le")
        Spacer().frame(height: 8)
        modelCards
        Spacer().frame(height: 12)
        sectionTitle("Session active (5h)")
        Spacer().frame(height: 8)
        sessionCard
        Spacer().frame(height: 12)
        sectionTitle("Cette semaine")
        Spacer().frame(height: 8)
        weekCard
        if let top = store.snapshot.topProjectToday {
            Spacer().frame(height: 10)
            topProjectRow(name: top.name, cost: top.cost)
        }
        Spacer().frame(height: 12)
        Divider().background(Color.white.opacity(0.08))
        Spacer().frame(height: 8)
        footer
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image("MenuBarIcon", bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(fg)
                Text("Claude Token Manager")
                    .font(AppFont.inter(size: 13, weight: .medium))
            }
            Spacer()
            Button(action: { showingPreferences = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Project picker

    private var projectMenu: some View {
        Menu {
            Button(action: { store.selectedProjectId = UsageSnapshot.allProjectsId }) {
                if store.selectedProjectId == UsageSnapshot.allProjectsId {
                    Label("Tous les projets", systemImage: "checkmark")
                } else { Text("Tous les projets") }
            }
            if !store.snapshot.projects.isEmpty {
                Divider()
                ForEach(store.snapshot.projects) { project in
                    Button(action: { store.selectedProjectId = project.id }) {
                        let marker = project.isActive ? "\u{25CF} " : ""
                        let title = "\(marker)\(project.displayName)"
                        if project.id == store.selectedProjectId {
                            Label(title, systemImage: "checkmark")
                        } else { Text(title) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if store.selectedProjectId != UsageSnapshot.allProjectsId,
                   store.selectedProject.isActive {
                    Circle().fill(Color(red: 151/255, green: 196/255, blue: 89/255)).frame(width: 6, height: 6)
                }
                Text("Projet : \(store.selectedProject.displayName)")
                    .font(AppFont.inter(size: 11)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Today big card

    private var todayBigCard: some View {
        let cost = store.snapshot.todayTotalCost
        let tokens = store.snapshot.todayTotalTokens
        let primary: String
        let secondary: String
        if store.displayFormat == .cost {
            primary = CostFormatter.format(cost)
            secondary = "\(TokenFormatter.compact(tokens)) tokens"
        } else {
            primary = "\(TokenFormatter.compact(tokens)) tokens"
            secondary = CostFormatter.format(cost)
        }

        return card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primary)
                            .font(AppFont.inter(size: 22, weight: .semibold))
                            .monospacedDigit()
                        Text("\u{00B7}")
                            .foregroundColor(.white.opacity(0.3))
                        Text(secondary)
                            .font(AppFont.inter(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                    Text("\u{00C9}quivalent API")
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
            }
        }
    }

    // MARK: - Model cards

    private var modelCards: some View {
        let today = store.snapshot.todayByModel
        return HStack(spacing: 8) {
            modelCard(key: "opus", label: "Opus", color: Color(red: 83/255, green: 74/255, blue: 183/255), usage: today["opus"])
            modelCard(key: "sonnet", label: "Sonnet", color: Color(red: 29/255, green: 158/255, blue: 117/255), usage: today["sonnet"])
            modelCard(key: "haiku", label: "Haiku", color: Color(red: 186/255, green: 117/255, blue: 23/255), usage: today["haiku"])
        }
    }

    private func modelCard(key: String, label: String, color: Color, usage: ModelUsage?) -> some View {
        let hasCost = (usage?.estimatedCost ?? 0) > 0
        let costStr = hasCost ? CostFormatter.format(usage!.estimatedCost) : "\u{2014}"
        let tokStr = hasCost ? "\(TokenFormatter.compact(usage!.totalTokens)) tk" : "\u{2014}"
        let primary: String
        let secondary: String
        if store.displayFormat == .cost {
            primary = costStr
            secondary = tokStr
        } else {
            primary = tokStr
            secondary = costStr
        }

        return card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(hasCost ? color : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(label)
                        .font(AppFont.inter(size: 11, weight: .medium))
                        .foregroundColor(hasCost ? fg : .white.opacity(0.35))
                }
                Text(primary)
                    .font(AppFont.inter(size: 14, weight: .semibold))
                    .foregroundColor(hasCost ? fg : .white.opacity(0.25))
                    .monospacedDigit()
                Text(secondary)
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(hasCost ? .white.opacity(0.45) : .white.opacity(0.2))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Session card

    private var sessionCard: some View {
        let costStr = CostFormatter.format(store.snapshot.sessionCost)
        let tokStr = TokenFormatter.compact(store.snapshot.sessionTokens)
        let primary = store.displayFormat == .cost ? costStr : "\(tokStr) tokens"

        return card {
            HStack {
                Text(primary)
                    .font(AppFont.inter(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("\u{00B7}")
                    .foregroundColor(.white.opacity(0.3))
                Text(store.sessionResetLabel)
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    // MARK: - Week card

    private var weekCard: some View {
        let costStr = CostFormatter.format(store.snapshot.weekTotalCost)
        let tokStr = TokenFormatter.compact(store.snapshot.weekTotalTokens)
        let primary = store.displayFormat == .cost ? costStr : "\(tokStr) tokens"

        return card {
            HStack {
                Text(primary)
                    .font(AppFont.inter(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("\u{00B7}")
                    .foregroundColor(.white.opacity(0.3))
                Text(store.weeklyResetLabel)
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    // MARK: - Top project

    private func topProjectRow(name: String, cost: Double) -> some View {
        HStack(spacing: 4) {
            Text("Top projet : \(name)")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
            Text("\u{00B7}")
                .foregroundColor(.white.opacity(0.2))
            Text(CostFormatter.format(cost))
                .font(AppFont.inter(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .monospacedDigit()
        }
    }

    // MARK: - Section title

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.inter(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.45))
    }

    // MARK: - Card helper

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: { store.refresh() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text("Actualiser").font(AppFont.inter(size: 11))
                }.foregroundColor(.white.opacity(0.6))
            }.buttonStyle(.plain)

            Button(action: { NSWorkspace.shared.open(LogScanner.shared.claudeProjectsDir) }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.system(size: 10))
                    Text("Logs").font(AppFont.inter(size: 11))
                }.foregroundColor(.white.opacity(0.6))
            }.buttonStyle(.plain)

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quitter").font(AppFont.inter(size: 11)).foregroundColor(.white.opacity(0.5))
            }.buttonStyle(.plain)
        }
    }
}
