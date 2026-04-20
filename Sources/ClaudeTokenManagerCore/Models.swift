import Foundation

// MARK: - JSONL record structure from ~/.claude/projects/*/*.jsonl

struct ClaudeLogEntry: Decodable {
    let type: String?
    let timestamp: String?
    let sessionId: String?
    let cwd: String?
    let message: LogMessage?

    struct LogMessage: Decodable {
        let role: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }

        var totalInput: Int {
            (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
        }
    }
}

// MARK: - Aggregated usage data

public struct ModelUsage: Identifiable, Hashable {
    public let id: String
    public let model: String
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var messageCount: Int = 0

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public var displayName: String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    public var estimatedCost: Double {
        let pricing = Pricing.forModel(model)
        let inputCost = Double(inputTokens) / 1_000_000 * pricing.input
        let outputCost = Double(outputTokens) / 1_000_000 * pricing.output
        let cacheWriteCost = Double(cacheCreationTokens) / 1_000_000 * pricing.cacheWrite
        let cacheReadCost = Double(cacheReadTokens) / 1_000_000 * pricing.cacheRead
        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    public init(id: String, model: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationTokens: Int = 0, cacheReadTokens: Int = 0, messageCount: Int = 0) {
        self.id = id
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.messageCount = messageCount
    }
}

public struct Pricing {
    public let input: Double
    public let output: Double
    public let cacheWrite: Double
    public let cacheRead: Double

    public static func forModel(_ model: String) -> Pricing {
        let lower = model.lowercased()
        if lower.contains("opus") {
            return Pricing(input: 15.0, output: 75.0, cacheWrite: 18.75, cacheRead: 1.50)
        }
        if lower.contains("sonnet") {
            return Pricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
        }
        if lower.contains("haiku") {
            return Pricing(input: 0.80, output: 4.0, cacheWrite: 1.0, cacheRead: 0.08)
        }
        return Pricing(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
    }
}

public struct SessionInfo: Identifiable {
    public let id: String
    public let projectKey: String
    public let projectName: String
    public let lastActivity: Date
    public let totalTokens: Int
    public let messageCount: Int

    public var isActive: Bool {
        Date().timeIntervalSince(lastActivity) < 300
    }

    public init(id: String, projectKey: String, projectName: String, lastActivity: Date, totalTokens: Int, messageCount: Int) {
        self.id = id
        self.projectKey = projectKey
        self.projectName = projectName
        self.lastActivity = lastActivity
        self.totalTokens = totalTokens
        self.messageCount = messageCount
    }
}

/// Per-project rollup of usage.
public struct ProjectUsage: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public var todayByModel: [String: ModelUsage] = [:]
    public var monthByModel: [String: ModelUsage] = [:]
    public var sessionsToday: Int = 0
    public var messagesToday: Int = 0
    public var lastActivity: Date?

    public var todayTotalTokens: Int {
        todayByModel.values.reduce(0) { $0 + $1.totalTokens }
    }
    public var todayTotalCost: Double {
        todayByModel.values.reduce(0) { $0 + $1.estimatedCost }
    }
    public var monthTotalCost: Double {
        monthByModel.values.reduce(0) { $0 + $1.estimatedCost }
    }
    public var isActive: Bool {
        guard let last = lastActivity else { return false }
        return Date().timeIntervalSince(last) < 300
    }

    public init(id: String, displayName: String, todayByModel: [String: ModelUsage] = [:], monthByModel: [String: ModelUsage] = [:], sessionsToday: Int = 0, messagesToday: Int = 0, lastActivity: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.todayByModel = todayByModel
        self.monthByModel = monthByModel
        self.sessionsToday = sessionsToday
        self.messagesToday = messagesToday
        self.lastActivity = lastActivity
    }
}

public struct UsageSnapshot {
    public var projects: [ProjectUsage] = []
    public var activeSessions: [SessionInfo] = []
    public var lastUpdate: Date = Date()

    public var recentActivityDates: [Date] = []

    /// Weekly totals across all projects (Monday 09:00 -> next Monday 09:00).
    public var weekByModel: [String: ModelUsage] = [:]

    public static let allProjectsId = "__all__"

    public var todayByModel: [String: ModelUsage] {
        var out: [String: ModelUsage] = [:]
        for project in projects {
            for (key, usage) in project.todayByModel {
                merge(&out, key: key, adding: usage)
            }
        }
        return out
    }

    public var monthByModel: [String: ModelUsage] {
        var out: [String: ModelUsage] = [:]
        for project in projects {
            for (key, usage) in project.monthByModel {
                merge(&out, key: key, adding: usage)
            }
        }
        return out
    }

    public var todayTotalTokens: Int {
        todayByModel.values.reduce(0) { $0 + $1.totalTokens }
    }
    public var todayTotalCost: Double {
        todayByModel.values.reduce(0) { $0 + $1.estimatedCost }
    }
    public var weekTotalTokens: Int {
        weekByModel.values.reduce(0) { $0 + $1.totalTokens }
    }
    public var weekTotalCost: Double {
        weekByModel.values.reduce(0) { $0 + $1.estimatedCost }
    }
    public var monthTotalCost: Double {
        monthByModel.values.reduce(0) { $0 + $1.estimatedCost }
    }
    public var totalSessionsToday: Int {
        projects.reduce(0) { $0 + $1.sessionsToday }
    }
    public var totalMessagesToday: Int {
        projects.reduce(0) { $0 + $1.messagesToday }
    }

    public var sessionTokens: Int = 0
    public var sessionCost: Double = 0
    public var sessionStart: Date?
    public var sessionEnd: Date?

    public func scoped(to projectId: String) -> ProjectUsage {
        if projectId == Self.allProjectsId {
            return ProjectUsage(
                id: Self.allProjectsId,
                displayName: "Tous les projets",
                todayByModel: todayByModel,
                monthByModel: monthByModel,
                sessionsToday: totalSessionsToday,
                messagesToday: totalMessagesToday,
                lastActivity: projects.compactMap(\.lastActivity).max()
            )
        }
        return projects.first { $0.id == projectId }
            ?? ProjectUsage(id: projectId, displayName: projectId)
    }

    /// Top project by cost today.
    public var topProjectToday: (name: String, cost: Double)? {
        guard let top = projects.max(by: { $0.todayTotalCost < $1.todayTotalCost }),
              top.todayTotalCost > 0 else { return nil }
        return (top.displayName, top.todayTotalCost)
    }

    public init() {}

    private func merge(_ dict: inout [String: ModelUsage], key: String, adding other: ModelUsage) {
        var existing = dict[key] ?? ModelUsage(id: key, model: other.model)
        existing.inputTokens += other.inputTokens
        existing.outputTokens += other.outputTokens
        existing.cacheCreationTokens += other.cacheCreationTokens
        existing.cacheReadTokens += other.cacheReadTokens
        existing.messageCount += other.messageCount
        dict[key] = existing
    }
}

public enum ProjectNameDecoder {
    public static func humanReadable(from encoded: String) -> String {
        let trimmed = encoded.hasPrefix("-") ? String(encoded.dropFirst()) : encoded
        let parts = trimmed.split(separator: "-").map(String.init)
        return parts.last ?? encoded
    }
}

// MARK: - Window computation

public enum LimitWindow {
    case session(start: Date, end: Date)
    case week(start: Date, end: Date)
}

public enum LimitCalculator {

    public static func currentSessionWindow(activityDates: [Date], now: Date = Date()) -> LimitWindow? {
        let fiveHours: TimeInterval = 5 * 3600
        let recent = activityDates.filter { now.timeIntervalSince($0) < fiveHours }
        guard let earliest = recent.min() else { return nil }
        let end = earliest.addingTimeInterval(fiveHours)
        return .session(start: earliest, end: end)
    }

    public static func currentWeekWindow(now: Date = Date(), calendar: Calendar = .current) -> LimitWindow {
        var cal = calendar
        cal.firstWeekday = 2

        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let mondayMidnight = cal.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let mondayMorning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: mondayMidnight) ?? mondayMidnight

        let start: Date
        if now < mondayMorning {
            start = cal.date(byAdding: .day, value: -7, to: mondayMorning) ?? mondayMorning
        } else {
            start = mondayMorning
        }
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return .week(start: start, end: end)
    }
}

// MARK: - Display format

public enum DisplayFormat: String, CaseIterable {
    case cost = "cost"
    case tokens = "tokens"

    public var label: String {
        switch self {
        case .cost: return "Co\u{00FB}t \u{00E9}quivalent API"
        case .tokens: return "Tokens"
        }
    }
}

// MARK: - Formatters

public enum CostFormatter {
    private static let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    public static func format(_ value: Double) -> String {
        fmt.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

public enum TokenFormatter {
    public static func compact(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
