import SwiftUI
import ClaudeTokenManagerCore

struct DropdownView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showingPreferences = false

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
        .background(Color(red: 31/255, green: 31/255, blue: 30/255))
        .foregroundColor(Color(red: 241/255, green: 239/255, blue: 232/255))
        .animation(.easeInOut(duration: 0.15), value: showingPreferences)
    }

    // MARK: - Main view

    @ViewBuilder
    private var mainContent: some View {
        header
        Spacer().frame(height: 12)
        planAndProjectPickers
        Spacer().frame(height: 12)
        sessionLimitCard
        Spacer().frame(height: 12)
        weeklyHeader
        Spacer().frame(height: 8)
        progressRow(store.weeklyAllModelsProgress)
        Spacer().frame(height: 8)
        progressRow(store.weeklySonnetProgress)
        Spacer().frame(height: 8)
        if let opus = store.weeklyOpusProgress {
            progressRow(opus, emphasized: opus.isHot)
        } else {
            Text("Opus non inclus dans ce forfait")
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 12)
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
                    .foregroundColor(Color(red: 241/255, green: 239/255, blue: 232/255))
                Text("Limites d'utilisation")
                    .font(AppFont.inter(size: 13, weight: .medium))
            }
            Spacer()
            Text(store.selectedPlan.rawValue)
                .font(AppFont.inter(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

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

    // MARK: - Pickers

    private var planAndProjectPickers: some View {
        HStack(spacing: 8) {
            planMenu
            projectMenu
        }
    }

    private var planMenu: some View {
        Menu {
            ForEach(ClaudePlan.allCases) { plan in
                Button(action: { store.selectedPlan = plan }) {
                    if plan == store.selectedPlan {
                        Label(plan.rawValue, systemImage: "checkmark")
                    } else {
                        Text(plan.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Forfait : \(store.selectedPlan.rawValue)")
                    .font(AppFont.inter(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var projectMenu: some View {
        Menu {
            Button(action: { store.selectedProjectId = UsageSnapshot.allProjectsId }) {
                if store.selectedProjectId == UsageSnapshot.allProjectsId {
                    Label("Tous les projets", systemImage: "checkmark")
                } else {
                    Text("Tous les projets")
                }
            }
            if !store.snapshot.projects.isEmpty {
                Divider()
                ForEach(store.snapshot.projects) { project in
                    Button(action: { store.selectedProjectId = project.id }) {
                        let marker = project.isActive ? "● " : ""
                        let title = "\(marker)\(project.displayName)"
                        if project.id == store.selectedProjectId {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if store.selectedProjectId != UsageSnapshot.allProjectsId,
                   store.selectedProject.isActive {
                    Circle()
                        .fill(Color(red: 151/255, green: 196/255, blue: 89/255))
                        .frame(width: 6, height: 6)
                }
                Text("Projet : \(store.selectedProject.displayName)")
                    .font(AppFont.inter(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Session + weekly

    private var sessionLimitCard: some View {
        progressRow(store.sessionProgress, emphasized: true)
    }

    private var weeklyHeader: some View {
        HStack {
            Text("Limites hebdomadaires")
                .font(AppFont.inter(size: 13, weight: .medium))
            Spacer()
            Text(relativeTime(store.snapshot.lastUpdate))
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Progress row

    private func progressRow(_ progress: LimitProgress, emphasized: Bool = false) -> some View {
        let percent = Int((progress.clampedPercent * 100).rounded(.down))
        let (barColor, textColor): (Color, Color) = {
            if progress.clampedPercent >= 0.95 {
                let c = Color(red: 216/255, green: 90/255, blue: 48/255)
                return (c, c)
            }
            if progress.clampedPercent >= 0.80 {
                let c = Color(red: 239/255, green: 159/255, blue: 39/255)
                return (c, c)
            }
            return (hueColor(progress.accentHue), Color(red: 241/255, green: 239/255, blue: 232/255))
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.label)
                    .font(AppFont.inter(size: 12, weight: .medium))
                Spacer()
                Text("\(percent) % utilisés")
                    .font(AppFont.inter(size: 11, weight: .medium))
                    .foregroundColor(textColor)
                    .monospacedDigit()
            }
            Text(progress.sublabel)
                .font(AppFont.inter(size: 10))
                .foregroundColor(.white.opacity(0.4))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: emphasized ? 6 : 5)
                    RoundedRectangle(cornerRadius: 999)
                        .fill(barColor)
                        .frame(
                            width: max(2, geo.size.width * progress.clampedPercent),
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
                    (emphasized && progress.clampedPercent >= 0.70)
                        ? barColor.opacity(0.35)
                        : Color.clear,
                    lineWidth: 0.5
                )
        )
    }

    private func hueColor(_ hue: LimitProgress.Hue) -> Color {
        switch hue {
        case .blue:   return Color(red: 55/255, green: 138/255, blue: 221/255)
        case .green:  return Color(red: 29/255, green: 158/255, blue: 117/255)
        case .orange: return Color(red: 217/255, green: 119/255, blue: 87/255)
        case .gray:   return Color.gray
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: { store.refresh() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text("Actualiser").font(AppFont.inter(size: 11))
                }.foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)

            Button(action: openLogsFolder) {
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.system(size: 10))
                    Text("Logs").font(AppFont.inter(size: 11))
                }.foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Text("Quitter")
                    .font(AppFont.inter(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "à l'instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86400 { return "il y a \(Int(seconds / 3600))h" }
        return "il y a \(Int(seconds / 86400))j"
    }

    private func openLogsFolder() {
        NSWorkspace.shared.open(LogScanner.shared.claudeProjectsDir)
    }
}
