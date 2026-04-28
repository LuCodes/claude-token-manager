import Foundation

public struct DailyBucket: Codable, Identifiable, Equatable, Sendable {
    public var id: String { date }
    public let date: String         // ISO yyyy-MM-dd
    public var totalTokens: Int
    public var totalCostUSD: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationTokens: Int
    public var cacheReadTokens: Int

    public init(
        date: String,
        totalTokens: Int,
        totalCostUSD: Double,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) {
        self.date = date
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }

    // Backward-compat: v1 buckets persisted in UserDefaults don't have the
    // breakdown fields. Default them to 0 so old data still decodes; the
    // next ingest replaces these days with full breakdown anyway.
    private enum CodingKeys: String, CodingKey {
        case date, totalTokens, totalCostUSD
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try c.decode(String.self, forKey: .date)
        self.totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        self.totalCostUSD = try c.decode(Double.self, forKey: .totalCostUSD)
        self.inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        self.cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
    }
}

public struct HourlyBucket: Identifiable, Equatable, Sendable {
    public var id: Int { hour }
    public let hour: Int            // 0-23
    public var totalTokens: Int
    public var totalCostUSD: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationTokens: Int
    public var cacheReadTokens: Int

    public init(
        hour: Int,
        totalTokens: Int,
        totalCostUSD: Double,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0
    ) {
        self.hour = hour
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

/// Folds raw `ActivityEvent`s into per-day and per-hour-of-today buckets.
/// Daily totals are persisted in UserDefaults so the History window has
/// data ready even before the first refresh of the session. Hourly today
/// is in-memory only — recomputed each ingest.
@MainActor
public final class HistoryAggregator: ObservableObject {

    public static let shared = HistoryAggregator()

    @Published public private(set) var dailyBuckets: [DailyBucket] = []
    @Published public private(set) var hourlyTodayBuckets: [HourlyBucket] = []

    private static let udKey = "ctm.dailyBuckets.v1"

    private init() {
        load()
        hourlyTodayBuckets = (0..<24).map {
            HourlyBucket(hour: $0, totalTokens: 0, totalCostUSD: 0)
        }
    }

    /// Replace per-day totals from the supplied events. Days the scan did
    /// not cover (e.g. JSONL files rotated away) keep their previous
    /// totals — the JSONL files are append-only so a re-scan that covers
    /// today necessarily contains every event for today.
    public func ingest(events: [ActivityEvent]) {
        guard !events.isEmpty else { return }

        let dayFormatter = Self.dayKeyFormatter
        var freshDaily: [String: DailyBucket] = [:]
        for e in events {
            let key = dayFormatter.string(from: e.date)
            var bucket = freshDaily[key]
                ?? DailyBucket(date: key, totalTokens: 0, totalCostUSD: 0)
            bucket.totalTokens += e.totalTokens
            bucket.totalCostUSD += e.exactCost
            bucket.inputTokens += e.inputTokens
            bucket.outputTokens += e.outputTokens
            bucket.cacheCreationTokens += e.cacheCreationTokens
            bucket.cacheReadTokens += e.cacheReadTokens
            freshDaily[key] = bucket
        }

        var merged: [String: DailyBucket] = Dictionary(
            uniqueKeysWithValues: dailyBuckets.map { ($0.date, $0) }
        )
        for (k, v) in freshDaily { merged[k] = v }
        dailyBuckets = merged.values.sorted { $0.date < $1.date }
        save()

        hourlyTodayBuckets = Self.computeHourlyToday(events: events)
    }

    /// Daily history bounded to the most recent `days` days, sorted oldest → newest.
    public func recentDailyHistory(days: Int) -> [DailyBucket] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: Calendar.current.startOfDay(for: Date()))
            ?? .distantPast
        let cutoffKey = Self.dayKeyFormatter.string(from: cutoff)
        return dailyBuckets.filter { $0.date >= cutoffKey }
    }

    // MARK: - Internals

    private static func computeHourlyToday(events: [ActivityEvent]) -> [HourlyBucket] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var buckets = (0..<24).map {
            HourlyBucket(hour: $0, totalTokens: 0, totalCostUSD: 0)
        }
        for e in events where e.date >= startOfToday {
            let h = calendar.component(.hour, from: e.date)
            guard h >= 0 && h < 24 else { continue }
            buckets[h].totalTokens += e.totalTokens
            buckets[h].totalCostUSD += e.exactCost
            buckets[h].inputTokens += e.inputTokens
            buckets[h].outputTokens += e.outputTokens
            buckets[h].cacheCreationTokens += e.cacheCreationTokens
            buckets[h].cacheReadTokens += e.cacheReadTokens
        }
        return buckets
    }

    private static var dayKeyFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(dailyBuckets) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.udKey),
            let buckets = try? JSONDecoder().decode([DailyBucket].self, from: data)
        else { return }
        dailyBuckets = buckets.sorted { $0.date < $1.date }
    }
}
