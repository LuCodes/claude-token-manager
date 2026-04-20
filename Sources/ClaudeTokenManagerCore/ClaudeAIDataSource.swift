import Foundation

public final class ClaudeAIDataSource: DataSource, @unchecked Sendable {
    public let id = "claude-ai"
    public let displayName = "claude.ai"

    public static let sessionKeyKey = "claude-ai-session-key"
    public static let orgIdKey = "claudeAiOrgId"

    private let client: ClaudeAPIClient

    public init(client: ClaudeAPIClient = .shared) {
        self.client = client
    }

    public var isAvailable: Bool {
        guard hasOrgId() else { return false }
        return hasSessionKey()
    }

    public func fetch() async throws -> UsageSnapshot {
        guard let orgId = Self.loadOrgId(), !orgId.isEmpty else {
            throw DataSourceError.notAvailable(reason: "organization ID missing")
        }
        let sessionKey = try Self.loadSessionKey()

        let raw = try await client.fetchUsageReport(
            organizationId: orgId,
            sessionKey: sessionKey
        )
        return Self.convert(raw: raw)
    }

    // MARK: - Credentials management (called by UI)

    public static func saveCredentials(orgId: String, sessionKey: String) throws {
        UserDefaults.standard.set(orgId, forKey: orgIdKey)
        try KeychainStore.setSensitive(sessionKey, for: sessionKeyKey)
    }

    public static func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: orgIdKey)
        try? KeychainStore.delete(sessionKeyKey)
    }

    public static func loadOrgId() -> String? {
        UserDefaults.standard.string(forKey: orgIdKey)
    }

    public static func hasStoredCredentials() -> Bool {
        guard let orgId = loadOrgId(), !orgId.isEmpty else { return false }
        let hasKey = (try? KeychainStore.get(sessionKeyKey)) ?? nil
        return hasKey?.isEmpty == false
    }

    // MARK: - Internal helpers

    private func hasOrgId() -> Bool {
        guard let id = Self.loadOrgId() else { return false }
        return !id.isEmpty
    }

    private func hasSessionKey() -> Bool {
        guard let key = try? KeychainStore.get(Self.sessionKeyKey),
              !key.isEmpty else {
            return false
        }
        return true
    }

    private static func loadSessionKey() throws -> SessionKey {
        guard let raw = try KeychainStore.get(sessionKeyKey),
              !raw.isEmpty else {
            throw DataSourceError.authenticationRequired
        }
        return SessionKey(raw)
    }

    // MARK: - Snapshot conversion

    public static func convert(raw: RawUsageReport) -> UsageSnapshot {
        var snapshot = UsageSnapshot()

        if let pool = raw.fiveHour {
            snapshot.sessionEnd = pool.resetsAt
            snapshot.sessionStart = pool.resetsAt.addingTimeInterval(-5 * 3600)
            snapshot.sessionTokens = Int(pool.utilization * 100_000)
            snapshot.sessionCost = pool.utilization
        }

        var week: [String: ModelUsage] = [:]
        let entries: [(String, RawUsageReport.Pool?)] = [
            ("all", raw.sevenDay),
            ("sonnet", raw.sevenDaySonnet),
            ("opus", raw.sevenDayOpus),
            ("design", raw.sevenDayOmelette),
            ("cowork", raw.sevenDayCowork),
            ("oauth", raw.sevenDayOauthApps)
        ]
        for (key, pool) in entries {
            guard let pool = pool else { continue }
            var usage = ModelUsage(id: key, model: key)
            usage.inputTokens = Int(pool.utilization * 100_000)
            week[key] = usage
        }
        snapshot.weekByModel = week

        // Build remote progress bars for the UI
        var bars: [RemoteProgressBar] = []
        if let pool = raw.fiveHour {
            bars.append(RemoteProgressBar(id: "session", label: "Current session", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        if let pool = raw.sevenDay {
            bars.append(RemoteProgressBar(id: "all", label: "All models", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        if let pool = raw.sevenDaySonnet {
            bars.append(RemoteProgressBar(id: "sonnet", label: "Sonnet only", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        if let pool = raw.sevenDayOpus {
            bars.append(RemoteProgressBar(id: "opus", label: "Opus", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        if let pool = raw.sevenDayOmelette {
            bars.append(RemoteProgressBar(id: "design", label: "Claude Design", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        if let pool = raw.sevenDayCowork {
            bars.append(RemoteProgressBar(id: "cowork", label: "Cowork", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        if let pool = raw.sevenDayOauthApps {
            bars.append(RemoteProgressBar(id: "oauth", label: "OAuth integrations", percent: pool.utilization, resetsAt: pool.resetsAt))
        }
        snapshot.remoteProgressBars = bars

        snapshot.lastUpdate = Date()
        return snapshot
    }
}
