import Foundation
import SwiftUI
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published public var snapshot: UsageSnapshot = UsageSnapshot()
    @Published public var isLoading: Bool = true
    @Published public var selectedProjectId: String {
        didSet {
            UserDefaults.standard.set(selectedProjectId, forKey: Self.selectedProjectKey)
        }
    }
    @Published public var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Self.notificationsKey)
            if notificationsEnabled {
                Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
            } else {
                NotificationManager.shared.clearAllFiredAlerts()
            }
        }
    }
    @Published public var launchAtLoginEnabled: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLoginEnabled, forKey: Self.launchAtLoginKey)
        }
    }

    private var refreshTask: Task<Void, Never>?
    private var fileWatcher: FileWatcher?
    private static let selectedProjectKey = "selectedProjectId"
    private static let notificationsKey = "notificationsEnabled"
    private static let launchAtLoginKey = "launchAtLoginEnabled"

    public let accentColor = Color(red: 217/255, green: 119/255, blue: 87/255)

    public init() {
        self.selectedProjectId = UserDefaults.standard.string(forKey: Self.selectedProjectKey)
            ?? UsageSnapshot.allProjectsId

        if UserDefaults.standard.object(forKey: Self.notificationsKey) == nil {
            self.notificationsEnabled = true
            UserDefaults.standard.set(true, forKey: Self.notificationsKey)
        } else {
            self.notificationsEnabled = UserDefaults.standard.bool(forKey: Self.notificationsKey)
        }

        if UserDefaults.standard.object(forKey: Self.launchAtLoginKey) == nil {
            self.launchAtLoginEnabled = true
            UserDefaults.standard.set(true, forKey: Self.launchAtLoginKey)
        } else {
            self.launchAtLoginEnabled = UserDefaults.standard.bool(forKey: Self.launchAtLoginKey)
        }

        refresh()
        startWatching()
        startPeriodicRefresh()

        if notificationsEnabled {
            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    public func refresh() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let newSnapshot = LogScanner.shared.scan()
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.snapshot = newSnapshot
                self.isLoading = false
                if self.selectedProjectId != UsageSnapshot.allProjectsId,
                   !newSnapshot.projects.contains(where: { $0.id == self.selectedProjectId }) {
                    self.selectedProjectId = UsageSnapshot.allProjectsId
                }
                self.evaluateNotifications()
            }
        }
    }

    private func evaluateNotifications() {
        guard notificationsEnabled else { return }
        let weekEnd: Date? = {
            let window = LimitCalculator.currentWeekWindow()
            if case .week(_, let end) = window { return end }
            return nil
        }()

        NotificationManager.shared.evaluate(progress: sessionProgress, windowEnd: snapshot.sessionEnd)
        NotificationManager.shared.evaluate(progress: weeklyTotalProgress, windowEnd: weekEnd)
        NotificationManager.shared.evaluate(progress: weeklyOpusProgress, windowEnd: weekEnd)
        NotificationManager.shared.evaluate(progress: weeklySonnetProgress, windowEnd: weekEnd)
        if let haiku = weeklyHaikuProgress {
            NotificationManager.shared.evaluate(progress: haiku, windowEnd: weekEnd)
        }
    }

    private func startPeriodicRefresh() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    private func startWatching() {
        let url = LogScanner.shared.claudeProjectsDir
        fileWatcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        fileWatcher?.start()
    }

    // MARK: - Scoped view the UI reads

    public var selectedProject: ProjectUsage {
        snapshot.scoped(to: selectedProjectId)
    }

    public var hottestProgress: LimitProgress {
        var all: [LimitProgress] = [
            sessionProgress,
            weeklyTotalProgress,
            weeklyOpusProgress,
            weeklySonnetProgress
        ]
        if let haiku = weeklyHaikuProgress { all.append(haiku) }
        return all.max(by: { $0.percent < $1.percent }) ?? sessionProgress
    }

    public var compactLabel: String {
        let pct = Int((hottestProgress.clampedPercent * 100).rounded(.down))
        return "\(pct)%"
    }

    public var menuBarTint: Color {
        let pct = hottestProgress.clampedPercent
        if pct >= 0.95 { return Color(red: 216/255, green: 90/255, blue: 48/255) }
        if pct >= 0.80 { return Color(red: 239/255, green: 159/255, blue: 39/255) }
        return Color.primary
    }

    // MARK: - Progress (peak-based)

    public var sessionProgress: LimitProgress {
        let used = snapshot.sessionTokensRaw
        let total = snapshot.effectiveSessionPeak
        return makeProgress(
            id: "session",
            label: "Session actuelle",
            sublabel: sessionResetSublabel,
            used: used,
            total: total
        )
    }

    public var weeklyTotalProgress: LimitProgress {
        let used = snapshot.weekByModel.values.reduce(0) { $0 + $1.totalTokens }
        let total = snapshot.effectiveWeeklyTotalPeak
        return makeProgress(
            id: "week-all",
            label: "Cette semaine \u{00B7} total",
            sublabel: weeklyResetSublabel,
            used: used,
            total: total
        )
    }

    public var weeklyOpusProgress: LimitProgress {
        let used = snapshot.weekByModel["opus"]?.totalTokens ?? 0
        let total = snapshot.effectiveWeeklyOpusPeak
        return makeProgress(
            id: "week-opus",
            label: "Dont Opus",
            sublabel: weeklyResetSublabel,
            used: used,
            total: total
        )
    }

    public var weeklySonnetProgress: LimitProgress {
        let used = snapshot.weekByModel["sonnet"]?.totalTokens ?? 0
        let total = snapshot.effectiveWeeklySonnetPeak
        return makeProgress(
            id: "week-sonnet",
            label: "Dont Sonnet",
            sublabel: weeklyResetSublabel,
            used: used,
            total: total
        )
    }

    /// Only shown if user actually used Haiku this week.
    public var weeklyHaikuProgress: LimitProgress? {
        let used = snapshot.weekByModel["haiku"]?.totalTokens ?? 0
        guard used > 0 else { return nil }
        let total = snapshot.effectiveWeeklyHaikuPeak
        return makeProgress(
            id: "week-haiku",
            label: "Dont Haiku",
            sublabel: weeklyResetSublabel,
            used: used,
            total: total
        )
    }

    private func makeProgress(
        id: String,
        label: String,
        sublabel: String,
        used: Int,
        total: Int
    ) -> LimitProgress {
        let pct = total > 0 ? Double(used) / Double(total) : 0
        let hue: LimitProgress.Hue
        if pct >= 0.90 { hue = .orange }
        else if pct >= 0.70 { hue = .orange }
        else if id.contains("sonnet") { hue = .green }
        else if id.contains("opus") { hue = .orange }
        else if id.contains("haiku") { hue = .gray }
        else { hue = .blue }
        return LimitProgress(
            id: id,
            label: label,
            sublabel: sublabel,
            percent: pct,
            used: used,
            total: total,
            accentHue: hue
        )
    }

    private var sessionResetSublabel: String {
        guard let end = snapshot.sessionEnd else {
            return "Pas de session active"
        }
        let remaining = end.timeIntervalSince(Date())
        if remaining <= 0 { return "Réinitialisée" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "Réinitialisation dans \(hours) h \(minutes) min"
        }
        return "Réinitialisation dans \(minutes) min"
    }

    private var weeklyResetSublabel: String {
        let window = LimitCalculator.currentWeekWindow()
        guard case .week(_, let end) = window else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE HH:mm"
        return "Réinitialisation \(formatter.string(from: end))"
    }
}

// MARK: - Token formatting helper

public enum TokenFormatter {
    public static func compact(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = Double(tokens) / 1_000_000
            return String(format: "%.1fM", m)
        }
        if tokens >= 1_000 {
            let k = Double(tokens) / 1_000
            return String(format: "%.0fk", k)
        }
        return "\(tokens)"
    }
}

// MARK: - File system watcher using FSEvents

final class FileWatcher {
    private let url: URL
    private let callback: () -> Void
    private var stream: FSEventStreamRef?

    init(url: URL, callback: @escaping () -> Void) {
        self.url = url
        self.callback = callback
    }

    func start() {
        let pathsToWatch = [url.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, _, _, _, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.callback()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        )

        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
