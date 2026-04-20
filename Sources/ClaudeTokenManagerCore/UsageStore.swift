import Foundation
import SwiftUI
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published public var snapshot: UsageSnapshot = UsageSnapshot()
    @Published public var isLoading: Bool = true
    @Published public var selectedProjectId: String {
        didSet { UserDefaults.standard.set(selectedProjectId, forKey: "selectedProjectId") }
    }
    @Published public var displayFormat: DisplayFormat {
        didSet { UserDefaults.standard.set(displayFormat.rawValue, forKey: "displayFormat") }
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
    @Published public var dailyBudgetIsMoney: Bool {
        didSet { UserDefaults.standard.set(dailyBudgetIsMoney, forKey: "dailyBudgetIsMoney") }
    }
    @Published public var launchAtLoginEnabled: Bool {
        didSet { UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled") }
    }

    // MARK: - Claude.ai sync

    @Published public private(set) var claudeAIModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(claudeAIModeEnabled, forKey: "claudeAIModeEnabled")
            refreshDataSources()
        }
    }

    @Published public private(set) var claudeAIConnectionStatus: ConnectionStatus = .unknown

    public enum ConnectionStatus: Equatable {
        case unknown
        case testing
        case connected
        case expired
        case error(String)
    }

    // MARK: - Data sources

    private var primaryDataSource: any DataSource = LocalLogsDataSource()
    private let fallbackDataSource: any DataSource = LocalLogsDataSource()

    @Published public private(set) var activeSourceId: String = "local-logs"

    private var refreshTask: Task<Void, Never>?
    private var fileWatcher: FileWatcher?

    public let accentColor = Color(red: 217/255, green: 119/255, blue: 87/255)

    public init() {
        self.selectedProjectId = UserDefaults.standard.string(forKey: "selectedProjectId")
            ?? UsageSnapshot.allProjectsId

        let fmtRaw = UserDefaults.standard.string(forKey: "displayFormat") ?? DisplayFormat.cost.rawValue
        self.displayFormat = DisplayFormat(rawValue: fmtRaw) ?? .cost

        if UserDefaults.standard.object(forKey: "dailyBudgetValue") != nil {
            self.dailyBudgetValue = UserDefaults.standard.double(forKey: "dailyBudgetValue")
        } else {
            self.dailyBudgetValue = nil
        }
        self.dailyBudgetIsMoney = UserDefaults.standard.object(forKey: "dailyBudgetIsMoney") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "dailyBudgetIsMoney")

        if UserDefaults.standard.object(forKey: "launchAtLoginEnabled") == nil {
            self.launchAtLoginEnabled = true
            UserDefaults.standard.set(true, forKey: "launchAtLoginEnabled")
        } else {
            self.launchAtLoginEnabled = UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
        }

        self.claudeAIModeEnabled = UserDefaults.standard.bool(forKey: "claudeAIModeEnabled")

        refreshDataSources()
        pruneStaleCredentialsIfNeeded()
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
                   !newSnapshot.projects.contains(where: { $0.id == self.selectedProjectId }) {
                    self.selectedProjectId = UsageSnapshot.allProjectsId
                }
                self.evaluateBudgetNotifications()
                if sourceId == "claude-ai" {
                    UserDefaults.standard.set(
                        Date().timeIntervalSince1970,
                        forKey: "claudeAILastSuccessfulFetch"
                    )
                }
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

    // MARK: - Data source management

    private func refreshDataSources() {
        if claudeAIModeEnabled && ClaudeAIDataSource.hasStoredCredentials() {
            primaryDataSource = ClaudeAIDataSource()
        } else {
            primaryDataSource = LocalLogsDataSource()
        }
    }

    public func setClaudeAIMode(enabled: Bool) {
        claudeAIModeEnabled = enabled
        refresh()
    }

    public func testAndSaveClaudeAICredentials(
        orgId: String,
        sessionKey: String
    ) async {
        await MainActor.run { self.claudeAIConnectionStatus = .testing }
        do {
            try ClaudeAIDataSource.saveCredentials(orgId: orgId, sessionKey: sessionKey)
            let ds = ClaudeAIDataSource()
            _ = try await ds.fetch()
            await MainActor.run {
                self.claudeAIConnectionStatus = .connected
                self.refreshDataSources()
                self.refresh()
            }
        } catch let err as DataSourceError {
            ClaudeAIDataSource.clearCredentials()
            let isAuth: Bool
            switch err {
            case .authenticationExpired, .authenticationRequired: isAuth = true
            default: isAuth = false
            }
            await MainActor.run {
                self.claudeAIConnectionStatus = isAuth
                    ? .expired
                    : .error("Connection failed")
            }
        } catch {
            ClaudeAIDataSource.clearCredentials()
            await MainActor.run {
                self.claudeAIConnectionStatus = .error(error.localizedDescription)
            }
        }
    }

    public func clearClaudeAICredentials() {
        ClaudeAIDataSource.clearCredentials()
        claudeAIConnectionStatus = .unknown
        refreshDataSources()
    }

    public func pruneStaleCredentialsIfNeeded() {
        let key = "claudeAILastSuccessfulFetch"
        let now = Date()
        let cutoff: TimeInterval = 30 * 24 * 3600

        guard ClaudeAIDataSource.hasStoredCredentials() else { return }

        let lastFetch = UserDefaults.standard.double(forKey: key)
        guard lastFetch > 0 else {
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
            return
        }

        if now.timeIntervalSince1970 - lastFetch > cutoff {
            clearClaudeAICredentials()
            NSLog("Claude Token Manager: auto-cleared stale claude.ai credentials after 30 days of inactivity")
        }
    }

    // MARK: - Notifications

    private func evaluateBudgetNotifications() {
        guard let budget = dailyBudgetValue, budget > 0 else { return }
        let currentValue: Double
        if dailyBudgetIsMoney {
            currentValue = snapshot.todayTotalCost
        } else {
            currentValue = Double(snapshot.todayTotalTokens)
        }
        NotificationManager.shared.evaluate(
            currentValue: currentValue, budget: budget, isMoney: dailyBudgetIsMoney
        )
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

    // MARK: - Scoped view

    public var selectedProject: ProjectUsage {
        snapshot.scoped(to: selectedProjectId)
    }

    // MARK: - Menu bar label

    public var compactLabel: String {
        switch displayFormat {
        case .cost:  return CostFormatter.format(snapshot.todayTotalCost)
        case .tokens: return TokenFormatter.compact(snapshot.todayTotalTokens)
        }
    }

    public var menuBarTint: Color {
        guard let budget = dailyBudgetValue, budget > 0 else { return Color.primary }
        let current: Double = dailyBudgetIsMoney
            ? snapshot.todayTotalCost
            : Double(snapshot.todayTotalTokens)
        let pct = current / budget
        if pct >= 0.95 { return Color(red: 216/255, green: 90/255, blue: 48/255) }
        if pct >= 0.80 { return Color(red: 239/255, green: 159/255, blue: 39/255) }
        return Color.primary
    }

    // MARK: - Session info

    public var sessionResetLabel: String {
        guard let end = snapshot.sessionEnd else { return "Pas de session active" }
        let remaining = end.timeIntervalSince(Date())
        if remaining <= 0 { return "R\u{00E9}initialis\u{00E9}e" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "reset dans \(hours) h \(minutes) min" }
        return "reset dans \(minutes) min"
    }

    public var weeklyResetLabel: String {
        let window = LimitCalculator.currentWeekWindow()
        guard case .week(_, let end) = window else { return "\u{2014}" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE HH:mm"
        return "reset \(formatter.string(from: end))"
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
