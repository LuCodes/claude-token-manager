import SwiftUI
import ClaudeTokenManagerCore

struct DropdownView: View {
    @EnvironmentObject var store: UsageStore
    @StateObject private var webSession = ClaudeWebSession.shared
    @State private var showingPreferences = false

    private let bg = Color(red: 31/255, green: 31/255, blue: 30/255)
    private let fg = Color(red: 241/255, green: 239/255, blue: 232/255)

    var body: some View {
        Group {
            if showingPreferences {
                PreferencesView(onClose: { showingPreferences = false })
                    .environmentObject(store)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    mainContent
                }
                .padding(16)
                .background(bg)
                .foregroundColor(fg)
            }
        }
        .focusable(false)
    }

    // MARK: - Main

    @ViewBuilder
    private var mainContent: some View {
        header
        Spacer().frame(height: 8)

        if webSession.isAuthenticated {
            connectedStatusBadge
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
            Text("Live data from claude.ai")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 29/255, green: 158/255, blue: 117/255).opacity(0.1))
        .cornerRadius(6)
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
                    Text("Weekly limits")
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
                Text("\(percent)% used")
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
        if interval < 0 { return "Resets imminently" }
        if interval < 24 * 3600 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            if h > 0 { return "Resets in \(h) h \(m) min" }
            return "Resets in \(m) min"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE HH:mm"
        return "Resets \(formatter.string(from: date))"
    }

    // MARK: - Local detail (compact, shown below remote bars)

    private var localDetailSection: some View {
        let tokens = store.selectedProject.todayTotalTokens
        let cost = store.selectedProject.todayTotalCost

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Local detail (Claude Code)")
                    .font(AppFont.inter(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            HStack(spacing: 12) {
                compactMetric(label: "API equiv. cost", value: CostFormatter.format(cost))
                compactMetric(label: "Tokens", value: "\(TokenFormatter.compact(tokens)) tokens")
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

    // MARK: - Local main layout

    @ViewBuilder
    private var localMainLayout: some View {
        sectionTitle("Today")
        Spacer().frame(height: 8)
        todayBigCard
        Spacer().frame(height: 12)
        sectionTitle("Breakdown by model")
        Spacer().frame(height: 8)
        modelCards
        Spacer().frame(height: 12)
        sectionTitle("Active session (5h)")
        Spacer().frame(height: 8)
        sessionCard
        Spacer().frame(height: 12)
        sectionTitle("This week")
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
                Image(nsImage: {
                    let img = NSImage(contentsOf: Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf")!)!
                    img.isTemplate = true
                    return img
                }())
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
                    .contentShape(Rectangle())
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    // MARK: - Project picker

    private var projectMenu: some View {
        Menu {
            Button(action: { store.selectedProjectId = UsageSnapshot.allProjectsId }) {
                if store.selectedProjectId == UsageSnapshot.allProjectsId {
                    Label("All projects", systemImage: "checkmark")
                } else { Text("All projects") }
            }
            if !store.availableProjects.isEmpty {
                Divider()
                ForEach(store.availableProjects) { project in
                    Button(action: { store.selectedProjectId = project.rawName }) {
                        if project.rawName == store.selectedProjectId {
                            Label(project.displayName, systemImage: "checkmark")
                        } else { Text(project.displayName) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Project: \(selectedProjectDisplayName)")
                    .font(AppFont.inter(size: 11)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }

    private var selectedProjectDisplayName: String {
        if store.selectedProjectId == UsageSnapshot.allProjectsId {
            return "All projects"
        }
        return store.availableProjects.first { $0.rawName == store.selectedProjectId }?.displayName
            ?? store.selectedProjectId
    }

    // MARK: - Today big card

    private var todayBigCard: some View {
        let cost = store.snapshot.todayTotalCost
        let tokens = store.snapshot.todayTotalTokens

        return card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(CostFormatter.format(cost))
                            .font(AppFont.inter(size: 22, weight: .semibold))
                            .monospacedDigit()
                        Text("\u{00B7}")
                            .foregroundColor(.white.opacity(0.3))
                        Text("\(TokenFormatter.compact(tokens)) tokens")
                            .font(AppFont.inter(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                    Text("API equivalent")
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
                Text(costStr)
                    .font(AppFont.inter(size: 14, weight: .semibold))
                    .foregroundColor(hasCost ? fg : .white.opacity(0.25))
                    .monospacedDigit()
                Text(tokStr)
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

        return card {
            HStack {
                Text(costStr)
                    .font(AppFont.inter(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("\u{00B7}")
                    .foregroundColor(.white.opacity(0.3))
                Text("\(tokStr) tokens")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.5))
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

        return card {
            HStack {
                Text(costStr)
                    .font(AppFont.inter(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("\u{00B7}")
                    .foregroundColor(.white.opacity(0.3))
                Text("\(tokStr) tokens")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.5))
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
            Text("Top project: \(name)")
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
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: { store.refresh() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text("Refresh").font(AppFont.inter(size: 11))
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
                Text("Quit").font(AppFont.inter(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

}
