import Foundation

/// claude.ai data source. v3+: backed by ClaudeWebSession (WKWebView)
/// instead of URLSession + Keychain. All credential management is handled
/// by WebKit's cookie store.
public final class ClaudeAIDataSource: DataSource, @unchecked Sendable {
    public let id = "claude-ai"
    public let displayName = "claude.ai"

    public init() {}

    public var isAvailable: Bool {
        // Marked as available even when not signed in — UsageStore decides
        // whether to actually pick this source based on isAuthenticated.
        true
    }

    public func fetch() async throws -> UsageSnapshot {
        let session = await ClaudeWebSession.shared
        let raw: RawUsageReport
        do {
            raw = try await session.fetchUsage()
        } catch ClaudeWebError.notAuthenticated {
            throw DataSourceError.authenticationRequired
        } catch let err as ClaudeWebError {
            throw DataSourceError.networkError(underlying: err)
        }
        return Self.convert(raw: raw)
    }

    // MARK: - Snapshot conversion (preserved verbatim from v2.x)

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
