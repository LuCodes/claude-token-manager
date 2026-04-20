import Foundation

/// Data source backed by Claude Code's local JSONL logs at ~/.claude/projects.
/// Wraps the existing LogScanner behind the DataSource protocol.
public final class LocalLogsDataSource: DataSource {
    public let id = "local-logs"
    public let displayName = "Claude Code logs (local)"

    public init() {}

    public var isAvailable: Bool {
        let url = LogScanner.shared.claudeProjectsDir
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func fetch() async throws -> UsageSnapshot {
        guard isAvailable else {
            throw DataSourceError.notAvailable(
                reason: "~/.claude/projects directory not found"
            )
        }
        return LogScanner.shared.scan()
    }
}
