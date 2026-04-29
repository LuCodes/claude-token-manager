import Foundation

public struct ActivityEvent {
    public let date: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public var exactCost: Double {
        let pricing = Pricing.forModel(model)
        return Double(inputTokens) / 1_000_000 * pricing.input
            + Double(outputTokens) / 1_000_000 * pricing.output
            + Double(cacheCreationTokens) / 1_000_000 * pricing.cacheWrite
            + Double(cacheReadTokens) / 1_000_000 * pricing.cacheRead
    }
}

/// Scans ~/.claude/projects/*/*.jsonl and aggregates token usage per project.
///
/// Per-file results are cached by `(mtime, size)`: a file whose modification
/// time and size haven't changed since the last scan is not re-read or
/// re-parsed. With dozens of projects and JSONL files in the hundreds of MB
/// range, this drops a continuously-active baseline of ~50% CPU to a few %.
public final class LogScanner: @unchecked Sendable {

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
        ClaudeProjectsPathResolver.resolve()
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude")
                .appendingPathComponent("projects")
    }

    // MARK: - Per-file parse cache

    private struct ParsedFile {
        var events: [ActivityEvent] = []
        var sessionId: String? = nil
        var lastActivity: Date? = nil
    }

    private struct CachedParse {
        var mtime: Date
        var fileSize: UInt64        // file size at last check
        var bytesProcessed: UInt64  // offset up to which lines have been parsed
        var parsed: ParsedFile
    }

    private let cacheLock = NSLock()
    private var fileCache: [URL: CachedParse] = [:]

    // MARK: - Scan

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
        var activityEvents: [ActivityEvent] = []
        var weekByModel: [String: ModelUsage] = [:]
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600)

        let projectDirs = (try? fileManager.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var seenFiles: Set<URL> = []

        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let projectKey = projectDir.lastPathComponent
            let projectDisplay = ProjectNameDecoder.humanReadable(from: projectKey)

            var project = projects[projectKey] ?? ProjectUsage(
                id: projectKey,
                displayName: projectDisplay
            )

            let jsonlFiles = (try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "jsonl" } ?? []

            for jsonlFile in jsonlFiles {
                seenFiles.insert(jsonlFile)
                let parsed = cachedParse(jsonlFile)
                aggregate(
                    parsed: parsed,
                    projectKey: projectKey,
                    projectDisplay: projectDisplay,
                    startOfToday: startOfToday,
                    startOfMonth: startOfMonth,
                    startOfWeek: startOfWeek,
                    twentyFourHoursAgo: twentyFourHoursAgo,
                    project: &project,
                    sessionsMap: &sessionsMap,
                    activityDates: &activityDates,
                    activityEvents: &activityEvents,
                    weekByModel: &weekByModel
                )
            }

            projects[projectKey] = project
        }

        evictDeletedFiles(stillPresent: seenFiles)

        snapshot.projects = projects.values
            .filter { $0.lastActivity != nil }
            .sorted { a, b in
                if a.isActive != b.isActive { return a.isActive }
                return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
            }

        snapshot.activeSessions = sessionsMap.values
            .filter { $0.isActive }
            .sorted { $0.lastActivity > $1.lastActivity }

        snapshot.recentActivityDates = activityDates
        snapshot.historyEvents = activityEvents
        snapshot.weekByModel = weekByModel

        if let session = LimitCalculator.currentSessionWindow(activityDates: activityDates, now: now),
           case .session(let sStart, _) = session {
            snapshot.sessionStart = sStart
            snapshot.sessionEnd = sStart.addingTimeInterval(5 * 3600)

            let inWindow = activityEvents.filter { $0.date >= sStart && $0.date <= now }
            snapshot.sessionTokens = inWindow.reduce(0) { $0 + $1.totalTokens }
            snapshot.sessionCost = inWindow.reduce(0) { $0 + $1.exactCost }
        }

        snapshot.lastUpdate = Date()
        return snapshot
    }

    // MARK: - Parse cache

    private func cachedParse(_ url: URL) -> ParsedFile {
        // Resolve mtime + size first; if either is missing the file may be
        // mid-rotation, so fall back to a fresh parse without caching it.
        guard let attrs = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ), let mtime = attrs.contentModificationDate else {
            return parseFromScratch(url)
        }
        let currentSize = UInt64(attrs.fileSize ?? 0)

        cacheLock.lock()
        let entry = fileCache[url]
        cacheLock.unlock()

        // Same mtime+size: cache hit, return as-is.
        if let e = entry, e.mtime == mtime, e.fileSize == currentSize {
            return e.parsed
        }

        // File shrunk: rotated/truncated, throw away the cache for it.
        var startingPoint = entry
        if let e = entry, currentSize < e.bytesProcessed {
            startingPoint = nil
        }

        var parsed = startingPoint?.parsed ?? ParsedFile()
        let fromOffset = startingPoint?.bytesProcessed ?? 0
        let newOffset = appendNewLines(url: url, fromOffset: fromOffset, into: &parsed)

        cacheLock.lock()
        fileCache[url] = CachedParse(
            mtime: mtime,
            fileSize: currentSize,
            bytesProcessed: newOffset,
            parsed: parsed
        )
        cacheLock.unlock()
        return parsed
    }

    private func evictDeletedFiles(stillPresent: Set<URL>) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        for url in fileCache.keys where !stillPresent.contains(url) {
            fileCache.removeValue(forKey: url)
        }
    }

    /// Reads bytes from `fromOffset` to EOF, parses any complete lines (i.e.
    /// up to the last newline), and appends the resulting events into
    /// `parsed`. Returns the new safe offset — partial trailing data without
    /// a terminating newline stays unparsed and gets retried on the next call.
    private func appendNewLines(url: URL, fromOffset: UInt64, into parsed: inout ParsedFile) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return fromOffset }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: fromOffset)
        } catch {
            // Seek past EOF — caller will recompute next round.
            return fromOffset
        }

        let newData = handle.readDataToEndOfFile()
        if newData.isEmpty { return fromOffset }

        let newline: UInt8 = 0x0A
        var lastNewline: Int = -1
        for i in stride(from: newData.count - 1, through: 0, by: -1) {
            if newData[i] == newline { lastNewline = i; break }
        }
        guard lastNewline >= 0 else {
            // No complete line in the new chunk yet — leave offset where it is.
            return fromOffset
        }

        let parseable = newData.subdata(in: 0..<(lastNewline + 1))
        let decoder = JSONDecoder()

        var lineStart = 0
        for i in 0..<parseable.count {
            if parseable[i] == newline {
                if i > lineStart {
                    let lineData = parseable.subdata(in: lineStart..<i)
                    consumeLine(lineData, decoder: decoder, into: &parsed)
                }
                lineStart = i + 1
            }
        }

        return fromOffset + UInt64(lastNewline + 1)
    }

    private func consumeLine(_ lineData: Data, decoder: JSONDecoder, into parsed: inout ParsedFile) {
        guard let entry = try? decoder.decode(ClaudeLogEntry.self, from: lineData) else { return }

        if parsed.sessionId == nil, let sid = entry.sessionId {
            parsed.sessionId = sid
        }

        guard let timestamp = entry.timestamp,
              let date = parseDate(timestamp) else { return }

        if parsed.lastActivity == nil || date > parsed.lastActivity! {
            parsed.lastActivity = date
        }

        guard entry.message?.role == "assistant",
              let usage = entry.message?.usage,
              let model = entry.message?.model else { return }

        let input = usage.inputTokens ?? 0
        let output = usage.outputTokens ?? 0
        let cacheWrite = usage.cacheCreationInputTokens ?? 0
        let cacheRead = usage.cacheReadInputTokens ?? 0

        parsed.events.append(ActivityEvent(
            date: date, model: model,
            inputTokens: input, outputTokens: output,
            cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead
        ))
    }

    /// Bypass for files we can't stat — parse the whole content once,
    /// without caching, so the snapshot stays correct.
    private func parseFromScratch(_ url: URL) -> ParsedFile {
        var parsed = ParsedFile()
        _ = appendNewLines(url: url, fromOffset: 0, into: &parsed)
        return parsed
    }

    // MARK: - Aggregation

    private func aggregate(
        parsed: ParsedFile,
        projectKey: String,
        projectDisplay: String,
        startOfToday: Date,
        startOfMonth: Date,
        startOfWeek: Date,
        twentyFourHoursAgo: Date,
        project: inout ProjectUsage,
        sessionsMap: inout [String: SessionInfo],
        activityDates: inout [Date],
        activityEvents: inout [ActivityEvent],
        weekByModel: inout [String: ModelUsage]
    ) {
        let sessionStartedToday = (parsed.lastActivity.map { $0 >= startOfToday }) ?? false
        var sessionMessagesToday = 0
        var sessionTokens = 0

        for event in parsed.events {
            sessionTokens += event.totalTokens

            activityEvents.append(event)

            if event.date >= twentyFourHoursAgo {
                activityDates.append(event.date)
            }

            let modelKey = normalizedModelKey(event.model)

            if event.date >= startOfToday {
                sessionMessagesToday += 1
                addUsage(to: &project.todayByModel, key: modelKey, model: event.model,
                         input: event.inputTokens, output: event.outputTokens,
                         cacheWrite: event.cacheCreationTokens, cacheRead: event.cacheReadTokens)
            }

            if event.date >= startOfMonth {
                addUsage(to: &project.monthByModel, key: modelKey, model: event.model,
                         input: event.inputTokens, output: event.outputTokens,
                         cacheWrite: event.cacheCreationTokens, cacheRead: event.cacheReadTokens)
            }

            if event.date >= startOfWeek {
                addUsage(to: &weekByModel, key: modelKey, model: event.model,
                         input: event.inputTokens, output: event.outputTokens,
                         cacheWrite: event.cacheCreationTokens, cacheRead: event.cacheReadTokens)
            }
        }

        if let last = parsed.lastActivity {
            if project.lastActivity == nil || last > project.lastActivity! {
                project.lastActivity = last
            }
        }

        if sessionStartedToday {
            project.sessionsToday += 1
            project.messagesToday += sessionMessagesToday
        }

        if let sid = parsed.sessionId, let last = parsed.lastActivity {
            sessionsMap[sid] = SessionInfo(
                id: sid, projectKey: projectKey, projectName: projectDisplay,
                lastActivity: last, totalTokens: sessionTokens, messageCount: parsed.events.count
            )
        }
    }

    private func addUsage(
        to dict: inout [String: ModelUsage], key: String, model: String,
        input: Int, output: Int, cacheWrite: Int, cacheRead: Int
    ) {
        var usage = dict[key] ?? ModelUsage(id: key, model: model)
        usage.inputTokens += input
        usage.outputTokens += output
        usage.cacheCreationTokens += cacheWrite
        usage.cacheReadTokens += cacheRead
        usage.messageCount += 1
        dict[key] = usage
    }

    // Distinct model strings are few (e.g. "claude-opus-4-5", "claude-sonnet-4-6")
    // but `aggregate` runs `normalizedModelKey` for every event in every scan.
    // The lowercased + contains chain is the dominant bg-thread cost during a
    // streaming session because Foundation's case-folding String.contains takes
    // microseconds per call. Memoizing collapses thousands of calls per scan
    // into a dictionary lookup.
    private var modelKeyCache: [String: String] = [:]

    private func normalizedModelKey(_ model: String) -> String {
        cacheLock.lock()
        if let cached = modelKeyCache[model] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let lower = model.lowercased()
        let result: String
        if lower.contains("opus") { result = "opus" }
        else if lower.contains("sonnet") { result = "sonnet" }
        else if lower.contains("haiku") { result = "haiku" }
        else { result = lower }

        cacheLock.lock()
        modelKeyCache[model] = result
        cacheLock.unlock()
        return result
    }

    private func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}
