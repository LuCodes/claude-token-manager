import Foundation
import SwiftUI
import Combine

public struct ProjectDisplayInfo: Hashable, Identifiable {
    public let rawName: String
    public let displayName: String
    public var id: String { rawName }

    public init(rawName: String) {
        self.rawName = rawName
        self.displayName = Self.extractDisplayName(from: rawName)
    }

    private static func extractDisplayName(from rawName: String) -> String {
        guard rawName.hasPrefix("-") else { return rawName }

        // Read cwd from jsonl files in this project folder
        if let projectsDir = ClaudeProjectsPathResolver.resolve() {
            let projectDir = projectsDir.appendingPathComponent(rawName)
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ), let firstJsonl = contents.first(where: { $0.pathExtension == "jsonl" }),
               let data = try? Data(contentsOf: firstJsonl, options: .mappedIfSafe),
               let content = String(data: data, encoding: .utf8) {
                // Search first 50 lines for a "cwd" field
                for line in content.split(separator: "\n").prefix(50) {
                    guard let json = try? JSONSerialization.jsonObject(
                        with: Data(line.utf8)) as? [String: Any],
                          let cwd = json["cwd"] as? String, !cwd.isEmpty else {
                        continue
                    }
                    return (cwd as NSString).lastPathComponent
                }
            }
        }

        // Fallback: last segment (imprecise for names with hyphens)
        let trimmed = rawName.hasPrefix("-") ? String(rawName.dropFirst()) : rawName
        let parts = trimmed.split(separator: "-").map(String.init)
        return parts.last ?? rawName
    }
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published public var snapshot: UsageSnapshot = UsageSnapshot()
    @Published public var isLoading: Bool = true
    @Published public var availableProjects: [ProjectDisplayInfo] = []
    @Published public var selectedProjectId: String {
        didSet { UserDefaults.standard.set(selectedProjectId, forKey: "selectedProjectId") }
    }
    @Published public var dailyBudgetValue: Double? {
        didSet {
            if let v = dailyBudgetValue {
                UserDefaults.standard.set(v, forKey: "dailyBudgetValue")
            } else {
                UserDefaults.standard.removeObject(forKey: "dailyBudgetValue")
            }
        }
    }
    @Published public var launchAtLoginEnabled: Bool {
        didSet { UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled") }
    }

    @Published public private(set) var isClaudeCodeActive: Bool = false
    private var activityInactivityTimer: Timer?
    private let activityTimeoutSeconds: TimeInterval = 5.0

    public func notifyClaudeCodeActivity() {
        isClaudeCodeActive = true
        activityInactivityTimer?.invalidate()
        activityInactivityTimer = Timer.scheduledTimer(
            withTimeInterval: activityTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isClaudeCodeActive = false
            }
        }
    }

    // MARK: - Data sources

    private var primaryDataSource: any DataSource = LocalLogsDataSource()
    private let fallbackDataSource: any DataSource = LocalLogsDataSource()

    @Published public private(set) var activeSourceId: String = "local-logs"

    private var refreshTask: Task<Void, Never>?
    private var fileWatcher: FileWatcher?
    private var authCancellable: AnyCancellable?

    public let accentColor = Color(red: 217/255, green: 119/255, blue: 87/255)

    public init() {
        self.selectedProjectId = UserDefaults.standard.string(forKey: "selectedProjectId")
            ?? UsageSnapshot.allProjectsId

        if UserDefaults.standard.object(forKey: "dailyBudgetValue") != nil {
            self.dailyBudgetValue = UserDefaults.standard.double(forKey: "dailyBudgetValue")
        } else {
            self.dailyBudgetValue = nil
        }
        if UserDefaults.standard.object(forKey: "launchAtLoginEnabled") == nil {
            self.launchAtLoginEnabled = true
            UserDefaults.standard.set(true, forKey: "launchAtLoginEnabled")
        } else {
            self.launchAtLoginEnabled = UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
        }

        migrateLegacyBudgetIfNeeded()
        refreshDataSources()

        // React to login / logout: switch primary source and re-fetch.
        // @Published emits via willSet, so reading
        // ClaudeWebSession.shared.isAuthenticated inside the sink returns the
        // OLD value. Use the parameter (the new value) instead.
        authCancellable = ClaudeWebSession.shared.$isAuthenticated
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                self.applyAuthState(authenticated: newValue)
            }

        refresh()
        startWatching()
        startPeriodicRefresh()

        if dailyBudgetValue != nil {
            Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        }
    }

    deinit { refreshTask?.cancel() }

    // MARK: - Refresh

    public func refresh() {
        refreshAvailableProjects()
        let primary = primaryDataSource
        let fallback = fallbackDataSource
        Task.detached(priority: .userInitiated) {
            let (newSnapshot, sourceId) = await Self.fetchWithFallback(
                primary: primary, fallback: fallback
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.snapshot = newSnapshot
                self.activeSourceId = sourceId
                self.isLoading = false
                if self.selectedProjectId != UsageSnapshot.allProjectsId,
                   !self.availableProjects.contains(where: { $0.rawName == self.selectedProjectId }) {
                    self.selectedProjectId = UsageSnapshot.allProjectsId
                }
                self.evaluateAllNotifications()
            }
        }
    }

    private static func fetchWithFallback(
        primary: any DataSource, fallback: any DataSource
    ) async -> (UsageSnapshot, String) {
        do {
            let snapshot = try await primary.fetch()
            return (snapshot, primary.id)
        } catch {
            NSLog("Primary data source failed: \(error.localizedDescription)")
        }

        if primary.id != fallback.id {
            do {
                let snapshot = try await fallback.fetch()
                return (snapshot, fallback.id)
            } catch {
                NSLog("Fallback data source also failed: \(error.localizedDescription)")
            }
        }

        return (UsageSnapshot(), "none")
    }

    // MARK: - Available projects (always from local filesystem)

    private func refreshAvailableProjects() {
        guard let projectsDir = ClaudeProjectsPathResolver.resolve() else {
            availableProjects = []
            return
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let projects = contents.compactMap { url -> ProjectDisplayInfo? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            // Check has at least one jsonl
            let jsonls = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ))?.contains { $0.pathExtension == "jsonl" } ?? false
            guard jsonls else { return nil }
            return ProjectDisplayInfo(rawName: url.lastPathComponent)
        }

        availableProjects = projects.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    // MARK: - Data source management

    private func refreshDataSources() {
        applyAuthState(authenticated: ClaudeWebSession.shared.isAuthenticated)
    }

    private func applyAuthState(authenticated: Bool) {
        if authenticated {
            primaryDataSource = ClaudeAIDataSource()
        } else {
            primaryDataSource = LocalLogsDataSource()
        }
        refresh()
    }

    // MARK: - Notifications

    private func evaluateAllNotifications() {
        // Progress bar notifications (claude.ai mode)
        for bar in snapshot.remoteProgressBars {
            NotificationManager.shared.evaluateProgressBar(bar)
        }
        // Budget notifications (local mode)
        evaluateBudgetNotifications()
    }

    private func evaluateBudgetNotifications() {
        guard let budget = dailyBudgetValue, budget > 0 else { return }
        NotificationManager.shared.evaluate(
            currentValue: snapshot.todayTotalCost, budget: budget, isMoney: true
        )
    }

    private func migrateLegacyBudgetIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "budget.migratedToV141"
        if defaults.bool(forKey: migrationKey) { return }

        // Migrate old key if it exists
        if defaults.object(forKey: "dailyBudgetValue") != nil {
            let old = defaults.double(forKey: "dailyBudgetValue")
            if old > 0 { defaults.set(old, forKey: "dailyBudgetValue") }
        }

        // Clean up deprecated keys
        defaults.removeObject(forKey: "dailyBudgetIsMoney")
        defaults.set(true, forKey: migrationKey)
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

    public func startWatching() {
        fileWatcher?.stop()
        let url = LogScanner.shared.claudeProjectsDir
        fileWatcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in
                self?.notifyClaudeCodeActivity()
                self?.refresh()
            }
        }
        fileWatcher?.start()
    }

    // MARK: - Scoped view

    public var selectedProject: ProjectUsage {
        snapshot.scoped(to: selectedProjectId)
    }

    // MARK: - Menu bar label

    public var compactLabel: String {
        CostFormatter.format(snapshot.todayTotalCost)
    }

    public var menuBarTint: Color {
        guard let budget = dailyBudgetValue, budget > 0 else { return Color.primary }
        let pct = snapshot.todayTotalCost / budget
        if pct >= 0.95 { return Color(red: 216/255, green: 90/255, blue: 48/255) }
        if pct >= 0.80 { return Color(red: 239/255, green: 159/255, blue: 39/255) }
        return Color.primary
    }

    // MARK: - Session info

    public var sessionResetLabel: String {
        guard let end = snapshot.sessionEnd else { return "No active session" }
        let remaining = end.timeIntervalSince(Date())
        if remaining <= 0 { return "Reset" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "resets in \(hours) h \(minutes) min" }
        return "resets in \(minutes) min"
    }

    public var weeklyResetLabel: String {
        let window = LimitCalculator.currentWeekWindow()
        guard case .week(_, let end) = window else { return "\u{2014}" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE HH:mm"
        return "resets \(formatter.string(from: end))"
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
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, _, _, _, _) in
                guard let info else { return }
                Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().callback()
            },
            &context, pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
