import Foundation
import Combine

/// Detects Claude Code turn boundaries by parsing new lines appended to
/// `~/.claude/projects/**/*.jsonl` incrementally.
///
/// - Start-of-turn: `type == "user"` + `message.content` is a String + `isSidechain == false`
/// - End-of-turn:   `type == "assistant"` + `message.stop_reason != nil && != "tool_use"`
///                  + `isSidechain == false`
/// - Safety: if `isWorking` stays true for more than 5 min of file quiescence,
///           reset to false (covers a crashed CLI that never wrote `end_turn`).
///
/// Runs its own FSEventStream; independent from `LogScanner` which keeps its
/// token-counting responsibilities untouched.
@MainActor
public final class TurnActivityMonitor: ObservableObject {

    public static let shared = TurnActivityMonitor()

    @Published public private(set) var isAnyWorking: Bool = false

    private struct FileState {
        var byteOffset: UInt64 = 0
        var isWorking: Bool = false
    }

    private var fileStates: [URL: FileState] = [:]
    private var safetyTimer: Timer?
    private let safetyTimeout: TimeInterval = 300       // 5 min
    private let catchUpHorizon: TimeInterval = 600      // 10 min
    private var eventStream: FSEventStreamRef?

    private init() {}

    // MARK: - Public API

    public func start(watchedDirectories: [URL]) {
        stopEventStream()

        for dir in watchedDirectories {
            catchUpExistingFiles(in: dir)
        }

        startEventStream(for: watchedDirectories)
        startSafetyTimer()
        updatePublishedState()
    }

    public func stop() {
        stopEventStream()
        safetyTimer?.invalidate()
        safetyTimer = nil
    }

    // MARK: - Catch-up

    private func catchUpExistingFiles(in directory: URL) {
        let fm = FileManager.default
        let now = Date()

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let attrs = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ), let mtime = attrs.contentModificationDate else { continue }

            if now.timeIntervalSince(mtime) > catchUpHorizon { continue }

            fileStates[fileURL] = FileState(byteOffset: 0, isWorking: false)
            readNewLines(from: fileURL)
        }
    }

    // MARK: - Reading new lines

    /// Called from the FSEvents callback when a file changes.
    fileprivate func handleFileChange(_ url: URL) {
        guard url.pathExtension == "jsonl" else { return }

        if fileStates[url] == nil {
            fileStates[url] = FileState(byteOffset: 0, isWorking: false)
        }

        readNewLines(from: url)
        updatePublishedState()
    }

    private func readNewLines(from url: URL) {
        guard var state = fileStates[url] else { return }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            fileStates.removeValue(forKey: url)
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.byteOffset)
        } catch {
            // Offset past EOF (file truncated / rotated): reset from start.
            state.byteOffset = 0
            do { try handle.seek(toOffset: 0) } catch {
                fileStates.removeValue(forKey: url)
                return
            }
        }

        let newData = handle.readDataToEndOfFile()
        if newData.isEmpty {
            fileStates[url] = state
            return
        }

        let newline: UInt8 = 0x0A
        var lastCompleteLineEnd: Int = -1
        var lineStart = 0

        for i in 0..<newData.count {
            if newData[i] == newline {
                let lineData = newData.subdata(in: lineStart..<i)
                processLine(lineData, state: &state)
                lastCompleteLineEnd = i
                lineStart = i + 1
            }
        }

        if lastCompleteLineEnd >= 0 {
            state.byteOffset += UInt64(lastCompleteLineEnd + 1)
        }

        fileStates[url] = state
    }

    private func processLine(_ line: Data, state: inout FileState) {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }

        if (obj["isSidechain"] as? Bool) == true { return }

        guard let type = obj["type"] as? String,
              let msg = obj["message"] as? [String: Any]
        else { return }

        switch type {
        case "user":
            if msg["content"] is String {
                state.isWorking = true
            }
        case "assistant":
            if let stop = msg["stop_reason"] as? String, stop != "tool_use" {
                state.isWorking = false
            }
        default:
            break
        }
    }

    // MARK: - Safety timer

    private func startSafetyTimer() {
        safetyTimer?.invalidate()
        safetyTimer = Timer.scheduledTimer(
            withTimeInterval: 60, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runSafetyCheck()
            }
        }
    }

    private func runSafetyCheck() {
        let now = Date()
        var changed = false

        for (url, state) in fileStates where state.isWorking {
            guard let attrs = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ), let mtime = attrs.contentModificationDate else { continue }

            if now.timeIntervalSince(mtime) > safetyTimeout {
                var updated = state
                updated.isWorking = false
                fileStates[url] = updated
                changed = true
            }
        }

        if changed { updatePublishedState() }
    }

    // MARK: - Aggregation

    private func updatePublishedState() {
        let anyWorking = fileStates.values.contains { $0.isWorking }
        if anyWorking != isAnyWorking {
            isAnyWorking = anyWorking
        }
    }

    // MARK: - FSEventStream

    private func startEventStream(for directories: [URL]) {
        guard !directories.isEmpty else { return }

        let paths = directories.map { $0.path } as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: { infoPtr -> UnsafeRawPointer? in
                guard let infoPtr else { return nil }
                _ = Unmanaged<TurnActivityMonitor>.fromOpaque(infoPtr).retain()
                return UnsafeRawPointer(infoPtr)
            },
            release: { infoPtr in
                guard let infoPtr else { return }
                Unmanaged<TurnActivityMonitor>.fromOpaque(infoPtr).release()
            },
            copyDescription: nil
        )

        // Callback runs on DispatchQueue.main (configured below). With
        // kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArrayRef of
        // CFStringRef (without this flag it would be a raw `char **`, which
        // would crash when cast as CFArray).
        let callback: FSEventStreamCallback = { (_, info, numEvents, pathsPtr, _, _) in
            guard let info else { return }
            let monitor = Unmanaged<TurnActivityMonitor>
                .fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>
                .fromOpaque(pathsPtr).takeUnretainedValue() as NSArray

            var urls: [URL] = []
            urls.reserveCapacity(numEvents)
            for i in 0..<numEvents {
                if let pathStr = array[i] as? String {
                    urls.append(URL(fileURLWithPath: pathStr))
                }
            }

            // We are already on main queue; call directly on main actor
            // instead of spawning a Task to avoid latency / reordering.
            if #available(macOS 14.0, *) {
                MainActor.assumeIsolated {
                    for url in urls { monitor.handleFileChange(url) }
                }
            } else {
                Task { @MainActor in
                    for url in urls { monitor.handleFileChange(url) }
                }
            }
        }

        eventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    private func stopEventStream() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }
}
