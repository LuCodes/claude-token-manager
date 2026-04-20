import Foundation

/// Anything that can produce a UsageSnapshot.
/// Abstraction layer between UsageStore and the actual data providers.
public protocol DataSource: Sendable {
    /// Unique identifier used by UsageStore to track which source is active.
    var id: String { get }

    /// Human-readable name shown in UI diagnostic strings.
    var displayName: String { get }

    /// Fetch a fresh snapshot. Should not block the main thread for long.
    /// Throws DataSourceError on failure — UsageStore handles fallback.
    func fetch() async throws -> UsageSnapshot

    /// Whether this data source is currently usable.
    /// For local logs: true if ~/.claude/projects exists.
    /// For claude.ai: true if a valid token is stored.
    var isAvailable: Bool { get }
}

/// Typed errors that DataSources can throw.
/// Each case carries enough context for UsageStore to decide between
/// retry, fallback to another source, or surfacing an error to the user.
public enum DataSourceError: Error, LocalizedError {
    case notAvailable(reason: String)
    case authenticationRequired
    case authenticationExpired
    case rateLimited(retryAfter: TimeInterval?)
    case networkError(underlying: Error)
    case apiChanged(details: String)
    case parseError(details: String)
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .notAvailable(let r):          return "Data source unavailable: \(r)"
        case .authenticationRequired:        return "Authentication required"
        case .authenticationExpired:         return "Session expired"
        case .rateLimited(let retry):        return "Rate limited. Retry after: \(retry ?? 60)s"
        case .networkError(let e):           return "Network error: \(e.localizedDescription)"
        case .apiChanged(let d):             return "API format changed: \(d)"
        case .parseError(let d):             return "Parse error: \(d)"
        case .unknown(let e):                return "Unknown error: \(e)"
        }
    }
}
