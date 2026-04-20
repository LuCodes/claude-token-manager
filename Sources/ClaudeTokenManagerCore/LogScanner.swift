import Foundation

/// Scans ~/.claude/projects/*/*.jsonl and aggregates token usage per project.
/// Works on API, Pro, and Max plans — Claude Code writes these logs regardless.
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

        let weekWindow = LimitCalculator.currentWeekWindow(now: now, calendar: calendar)
        let startOfWeek: Date
        if case .week(let s, _) = weekWindow { startOfWeek = s } else { startOfWeek = startOfToday }

        var sessionsMap: [String: SessionInfo] = [:]
        var projects: [String: ProjectUsage] = [:]
        var activityDates: [Date] = []
        var activityTokenPairs: [(Date, Int)] = []
        var weekByModel: [String: ModelUsage] = [:]
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)

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
                    project: &project,
                    sessionsMap: &sessionsMap,
                    activityDates: &activityDates,
                    activityTokenPairs: &activityTokenPairs,
                    weekByModel: &weekByModel
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

        snapshot.lastUpdate = Date()
        return snapshot
    }

    private func processFile(
        _ fileURL: URL,
        projectKey: String,
        projectDisplay: String,
        startOfToday: Date,
        startOfMonth: Date,
        startOfWeek: Date,
        twentyFourHoursAgo: Date,
        project: inout ProjectUsage,
        sessionsMap: inout [String: SessionInfo],
        activityDates: inout [Date],
        activityTokenPairs: inout [(Date, Int)],
        weekByModel: inout [String: ModelUsage]
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
