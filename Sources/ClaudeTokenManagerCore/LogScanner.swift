import Foundation

/// Scans ~/.claude/projects/*/*.jsonl and aggregates token usage per project.
public final class LogScanner {

    public static let shared = LogScanner()

    private let fileManager = FileManager.default
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public var claudeProjectsDir: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    public func scan() -> UsageSnapshot {
        var snapshot = UsageSnapshot()

        guard fileManager.fileExists(atPath: claudeProjectsDir.path) else {
            return snapshot
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        let weekWindow = LimitCalculator.currentWeekWindow(now: now, calendar: calendar)
        let startOfWeek: Date
        if case .week(let s, _) = weekWindow { startOfWeek = s } else { startOfWeek = startOfToday }

        var sessionsMap: [String: SessionInfo] = [:]
        var projects: [String: ProjectUsage] = [:]
        var activityDates: [Date] = []
        var activityTokenPairs: [(Date, Int)] = []
        var weekByModel: [String: ModelUsage] = [:]
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)

        // For 30-day peak computation: collect all (date, tokens, modelKey) tuples
        var allEvents30d: [(date: Date, tokens: Int, modelKey: String)] = []

        let projectDirs = (try? fileManager.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let projectKey = projectDir.lastPathComponent
            let projectDisplay = ProjectNameDecoder.humanReadable(from: projectKey)

            var project = projects[projectKey] ?? ProjectUsage(
                id: projectKey,
                displayName: projectDisplay
            )

            let jsonlFiles = (try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "jsonl" } ?? []

            for jsonlFile in jsonlFiles {
                processFile(
                    jsonlFile,
                    projectKey: projectKey,
                    projectDisplay: projectDisplay,
                    startOfToday: startOfToday,
                    startOfMonth: startOfMonth,
                    startOfWeek: startOfWeek,
                    twentyFourHoursAgo: twentyFourHoursAgo,
                    thirtyDaysAgo: thirtyDaysAgo,
                    project: &project,
                    sessionsMap: &sessionsMap,
                    activityDates: &activityDates,
                    activityTokenPairs: &activityTokenPairs,
                    weekByModel: &weekByModel,
                    allEvents30d: &allEvents30d
                )
            }

            projects[projectKey] = project
        }

        snapshot.projects = projects.values
            .filter { !$0.todayByModel.isEmpty || !$0.monthByModel.isEmpty }
            .sorted { a, b in
                if a.isActive != b.isActive { return a.isActive }
                return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
            }

        snapshot.activeSessions = sessionsMap.values
            .filter { $0.isActive }
            .sorted { $0.lastActivity > $1.lastActivity }

        snapshot.recentActivityDates = activityDates
        snapshot.weekByModel = weekByModel

        if let session = LimitCalculator.currentSessionWindow(activityDates: activityDates, now: now),
           case .session(let sStart, let sEnd) = session {
            snapshot.sessionStart = sStart
            snapshot.sessionEnd = sEnd
            snapshot.sessionTokensRaw = activityTokenPairs.reduce(0) { acc, pair in
                (pair.0 >= sStart && pair.0 <= now) ? acc + pair.1 : acc
            }
        }

        // Compute 30-day peaks
        computePeaks(events: allEvents30d, now: now, calendar: calendar, snapshot: &snapshot)

        snapshot.lastUpdate = Date()
        return snapshot
    }

    // MARK: - 30-day peak computation

    private func computePeaks(
        events: [(date: Date, tokens: Int, modelKey: String)],
        now: Date,
        calendar: Calendar,
        snapshot: inout UsageSnapshot
    ) {
        // --- Session peak: sliding 5h windows ---
        // Sort events by date, then find the max total tokens in any 5h window.
        let sorted = events.sorted { $0.date < $1.date }
        let fiveHours: TimeInterval = 5 * 3600

        if !sorted.isEmpty {
            var windowStart = 0
            var windowTotal = 0
            var maxSessionTotal = 0

            for end in 0..<sorted.count {
                windowTotal += sorted[end].tokens
                // Shrink window from the left if it exceeds 5h
                while sorted[end].date.timeIntervalSince(sorted[windowStart].date) > fiveHours {
                    windowTotal -= sorted[windowStart].tokens
                    windowStart += 1
                }
                maxSessionTotal = max(maxSessionTotal, windowTotal)
            }
            snapshot.sessionPeak30d = maxSessionTotal
        }

        // --- Weekly peaks: group events by calendar week (Mon 09:00 -> Mon 09:00) ---
        // Build a mapping from week-start -> totals per model
        var weekBuckets: [Date: (total: Int, opus: Int, sonnet: Int, haiku: Int)] = [:]

        for event in sorted {
            let weekStart = weekStartFor(date: event.date, calendar: calendar)
            var bucket = weekBuckets[weekStart] ?? (0, 0, 0, 0)
            bucket.total += event.tokens
            switch event.modelKey {
            case "opus":   bucket.opus += event.tokens
            case "sonnet": bucket.sonnet += event.tokens
            case "haiku":  bucket.haiku += event.tokens
            default: break
            }
            weekBuckets[weekStart] = bucket
        }

        for bucket in weekBuckets.values {
            snapshot.weeklyTotalPeak30d = max(snapshot.weeklyTotalPeak30d, bucket.total)
            snapshot.weeklyOpusPeak30d = max(snapshot.weeklyOpusPeak30d, bucket.opus)
            snapshot.weeklySonnetPeak30d = max(snapshot.weeklySonnetPeak30d, bucket.sonnet)
            snapshot.weeklyHaikuPeak30d = max(snapshot.weeklyHaikuPeak30d, bucket.haiku)
        }
    }

    /// Returns the Monday 09:00 that starts the week containing `date`.
    private func weekStartFor(date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let mondayMidnight = cal.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let mondayMorning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: mondayMidnight) ?? mondayMidnight

        if date < mondayMorning {
            return cal.date(byAdding: .day, value: -7, to: mondayMorning) ?? mondayMorning
        }
        return mondayMorning
    }

    // MARK: - File processing

    private func processFile(
        _ fileURL: URL,
        projectKey: String,
        projectDisplay: String,
        startOfToday: Date,
        startOfMonth: Date,
        startOfWeek: Date,
        twentyFourHoursAgo: Date,
        thirtyDaysAgo: Date,
        project: inout ProjectUsage,
        sessionsMap: inout [String: SessionInfo],
        activityDates: inout [Date],
        activityTokenPairs: inout [(Date, Int)],
        weekByModel: inout [String: ModelUsage],
        allEvents30d: inout [(date: Date, tokens: Int, modelKey: String)]
    ) {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        let decoder = JSONDecoder()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var sessionId: String?
        var lastActivity: Date?
        var sessionTokens = 0
        var sessionMessages = 0
        var sessionStartedToday = false
        var sessionMessagesToday = 0

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(ClaudeLogEntry.self, from: lineData) else {
                continue
            }

            if sessionId == nil, let sid = entry.sessionId {
                sessionId = sid
            }

            guard let timestamp = entry.timestamp,
                  let date = parseDate(timestamp) else {
                continue
            }

            if lastActivity == nil || date > lastActivity! {
                lastActivity = date
            }

            if date >= startOfToday {
                sessionStartedToday = true
            }

            guard entry.message?.role == "assistant",
                  let usage = entry.message?.usage,
                  let model = entry.message?.model else {
                continue
            }

            let modelKey = normalizedModelKey(model)
            let input = usage.inputTokens ?? 0
            let output = usage.outputTokens ?? 0
            let cacheWrite = usage.cacheCreationInputTokens ?? 0
            let cacheRead = usage.cacheReadInputTokens ?? 0
            let total = input + output + cacheWrite + cacheRead

            sessionTokens += total
            sessionMessages += 1

            // Collect events from the last 30 days for peak computation
            if date >= thirtyDaysAgo {
                allEvents30d.append((date: date, tokens: total, modelKey: modelKey))
            }

            if date >= twentyFourHoursAgo {
                activityDates.append(date)
                activityTokenPairs.append((date, total))
            }

            if date >= startOfToday {
                sessionMessagesToday += 1
                addUsage(
                    to: &project.todayByModel,
                    key: modelKey,
                    model: model,
                    input: input,
                    output: output,
                    cacheWrite: cacheWrite,
                    cacheRead: cacheRead
                )
            }

            if date >= startOfMonth {
                addUsage(
                    to: &project.monthByModel,
                    key: modelKey,
                    model: model,
                    input: input,
                    output: output,
                    cacheWrite: cacheWrite,
                    cacheRead: cacheRead
                )
            }

            if date >= startOfWeek {
                addUsage(
                    to: &weekByModel,
                    key: modelKey,
                    model: model,
                    input: input,
                    output: output,
                    cacheWrite: cacheWrite,
                    cacheRead: cacheRead
                )
            }
        }

        if let last = lastActivity {
            if project.lastActivity == nil || last > project.lastActivity! {
                project.lastActivity = last
            }
        }

        if sessionStartedToday {
            project.sessionsToday += 1
            project.messagesToday += sessionMessagesToday
        }

        if let sid = sessionId, let last = lastActivity {
            sessionsMap[sid] = SessionInfo(
                id: sid,
                projectKey: projectKey,
                projectName: projectDisplay,
                lastActivity: last,
                totalTokens: sessionTokens,
                messageCount: sessionMessages
            )
        }
    }

    private func addUsage(
        to dict: inout [String: ModelUsage],
        key: String,
        model: String,
        input: Int,
        output: Int,
        cacheWrite: Int,
        cacheRead: Int
    ) {
        var usage = dict[key] ?? ModelUsage(id: key, model: model)
        usage.inputTokens += input
        usage.outputTokens += output
        usage.cacheCreationTokens += cacheWrite
        usage.cacheReadTokens += cacheRead
        usage.messageCount += 1
        dict[key] = usage
    }

    private func normalizedModelKey(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "opus" }
        if lower.contains("sonnet") { return "sonnet" }
        if lower.contains("haiku") { return "haiku" }
        return lower
    }

    private func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}
