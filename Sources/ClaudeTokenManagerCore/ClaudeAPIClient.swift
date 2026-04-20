import Foundation

/// HTTP client for Anthropic's internal claude.ai API.
/// v0.3.0: skeleton only — returns mock data for testing.
/// v0.3.1+: will issue actual requests using a session cookie stored in Keychain.
public final class ClaudeAPIClient {
    public static let shared = ClaudeAPIClient()

    // Endpoints discovered from claude.ai web inspection.
    // Kept here so they can be updated in one place if Anthropic changes them.
    public struct Endpoints {
        public static let baseURL = "https://claude.ai/api"
        public static let usageReport = "/organizations/{orgId}/usage"
        public static let me = "/bootstrap/me"
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch the current usage report.
    /// v0.3.0: always throws `.notAvailable`. v0.3.1 will implement the real call.
    public func fetchUsageReport(sessionToken: String) async throws -> RemoteUsageReport {
        throw DataSourceError.notAvailable(reason: "ClaudeAPIClient not yet implemented")
    }
}

/// Shape of what Anthropic's internal API returns for usage.
/// Fields inferred from the claude.ai settings page — subject to change.
public struct RemoteUsageReport: Codable {
    public let sessionUsagePercent: Double
    public let sessionResetAt: Date
    public let weeklyAllModelsPercent: Double
    public let weeklySonnetPercent: Double
    public let weeklyOpusPercent: Double?
    public let weeklyResetAt: Date
    public let planName: String
}
