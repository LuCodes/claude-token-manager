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
        Spacer().frame(height: 8)

        if store.claudeAIModeEnabled && store.claudeAIConnectionStatus == .connected {
            connectedStatusBadge
            Spacer().frame(height: 10)
        } else if store.claudeAIModeEnabled && store.claudeAIConnectionStatus == .expired {
            expiredStatusBadge
            Spacer().frame(height: 10)
        }

        projectMenu
        Spacer().frame(height: 14)

        if !store.snapshot.remoteProgressBars.isEmpty {
            remoteBarsSection
            Spacer().frame(height: 14)
            localDetailSection
        } else {
            localMainLayout
        }

        Spacer().frame(height: 12)
        Divider().background(Color.white.opacity(0.08))
        Spacer().frame(height: 8)
        footer
    }

    private var connectedStatusBadge: some View {
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
    }

    private var expiredStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(red: 216/255, green: 90/255, blue: 48/255))
                .frame(width: 6, height: 6)
            Text("Session claude.ai expir\u{00E9}e")
                .font(AppFont.inter(size: 10))
                .foregroundColor(Color(red: 216/255, green: 90/255, blue: 48/255))
        }
    }

    // MARK: - Remote bars (claude.ai mode)

    private var remoteBarsSection: some View {
        let bars = store.snapshot.remoteProgressBars
        let sessionBars = bars.filter { $0.id == "session" }
        let weeklyBars = bars.filter { $0.id != "session" }

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(sessionBars) { bar in
                remoteBarCard(bar, emphasized: true)
            }

            if !weeklyBars.isEmpty {
                HStack {
                    Text("Limites hebdomadaires")
                        .font(AppFont.inter(size: 13, weight: .medium))
                    Spacer()
                    Text(relativeTime(store.snapshot.lastUpdate))
                        .font(AppFont.inter(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                VStack(spacing: 8) {
                    ForEach(weeklyBars) { bar in
                        remoteBarCard(bar, emphasized: false)
                    }
                }
            }
        }
    }

    private func remoteBarCard(_ bar: RemoteProgressBar, emphasized: Bool) -> some View {
        let percent = Int(bar.clampedPercent.rounded(.down))
        let color = colorForHue(bar.hue)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.label)
                    .font(AppFont.inter(size: emphasized ? 13 : 12, weight: .medium))
                Spacer()
                Text("\(percent) % utilis\u{00E9}s")
                    .font(AppFont.inter(size: 11, weight: .medium))
                    .foregroundColor(bar.percent >= 80 ? color : .white.opacity(0.85))
                    .monospacedDigit()
            }
            if let reset = bar.resetsAt {
                Text(resetLabel(for: reset))
                    .font(AppFont.inter(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: emphasized ? 6 : 5)
                    RoundedRectangle(cornerRadius: 999)
                        .fill(color)
                        .frame(
                            width: max(2, geo.size.width * (bar.clampedPercent / 100)),
                            height: emphasized ? 6 : 5
                        )
                }
            }
            .frame(height: emphasized ? 6 : 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    (emphasized && bar.percent >= 70) ? color.opacity(0.35) : .clear,
                    lineWidth: 0.5
                )
        )
    }

    private func colorForHue(_ hue: RemoteProgressBar.Hue) -> Color {
        switch hue {
        case .blue:   return Color(red: 55/255, green: 138/255, blue: 221/255)
        case .green:  return Color(red: 29/255, green: 158/255, blue: 117/255)
        case .coral:  return Color(red: 216/255, green: 90/255, blue: 48/255)
        case .amber:  return Color(red: 239/255, green: 159/255, blue: 39/255)
        case .purple: return Color(red: 83/255, green: 74/255, blue: 183/255)
        case .gray:   return Color.gray.opacity(0.7)
        }
    }

    private func resetLabel(for date: Date) -> String {
        let interval = date.timeIntervalSince(Date())
        if interval < 0 { return "R\u{00E9}initialisation imminente" }
        if interval < 24 * 3600 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            if h > 0 { return "R\u{00E9}initialisation dans \(h) h \(m) min" }
            return "R\u{00E9}initialisation dans \(m) min"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE HH:mm"
        return "R\u{00E9}initialisation \(formatter.string(from: date))"
    }

    // MARK: - Local detail (compact, shown below remote bars)

    private var localDetailSection: some View {
        let tokens = store.selectedProject.todayTotalTokens
        let cost = store.selectedProject.todayTotalCost
        let primaryLabel: String
        let primaryValue: String
        let secondaryLabel: String
        let secondaryValue: String
        if store.displayFormat == .cost {
            primaryLabel = "Co\u{00FB}t \u{00E9}quiv. API"
            primaryValue = CostFormatter.format(cost)
            secondaryLabel = "Tokens"
            secondaryValue = "\(TokenFormatter.compact(tokens)) tokens"
        } else {
            primaryLabel = "Tokens"
            primaryValue = "\(TokenFormatter.compact(tokens)) tokens"
            secondaryLabel = "Co\u{00FB}t \u{00E9}quiv. API"
            secondaryValue = CostFormatter.format(cost)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("D\u{00E9}tail local (Claude Code)")
                    .font(AppFont.inter(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            HStack(spacing: 12) {
                compactMetric(label: primaryLabel, value: primaryValue)
                compactMetric(label: secondaryLabel, value: secondaryValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func compactMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(AppFont.inter(size: 12, weight: .medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Local main layout (unchanged from v1.0.1)

    @ViewBuilder
    private var localMainLayout: some View {
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

    private func relativeTime(_ date: Date?) -> String {
        guard let date = date else { return "\u{2014}" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "\u{00E0} l'instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86400 { return "il y a \(Int(seconds / 3600))h" }
        return "il y a \(Int(seconds / 86400))j"
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
