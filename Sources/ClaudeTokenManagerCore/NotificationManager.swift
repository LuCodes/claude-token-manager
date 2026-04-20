import Foundation
import UserNotifications
import AppKit

/// Schedules discreet macOS banner notifications when a usage bar crosses a threshold.
public final class NotificationManager {

    public static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let dedupKey = "firedAlerts_v1"

    public enum Threshold: Int, CaseIterable {
        case warning = 80
        case critical = 95

        public var label: String {
            switch self {
            case .warning: return "80 %"
            case .critical: return "95 %"
            }
        }
    }

    private var firedAlerts: [String: Date] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: dedupKey) as? [String: TimeInterval] ?? [:]
            return raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set {
            let raw = newValue.mapValues { $0.timeIntervalSince1970 }
            UserDefaults.standard.set(raw, forKey: dedupKey)
        }
    }

    // MARK: - Public API

    public func requestAuthorizationIfNeeded() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert])
            return granted
        } catch {
            return false
        }
    }

    public func evaluate(progress: LimitProgress, windowEnd: Date?) {
        guard let windowEnd = windowEnd else { return }
        let percent = Int((progress.clampedPercent * 100).rounded(.down))

        for threshold in Threshold.allCases where percent >= threshold.rawValue {
            let key = dedupKey(for: progress.id, threshold: threshold, windowEnd: windowEnd)
            if firedAlerts[key] != nil { continue }

            fireNotification(progress: progress, threshold: threshold)
            var updated = firedAlerts
            updated[key] = Date()
            firedAlerts = updated
        }

        pruneOldEntries()
    }

    public func clearAllFiredAlerts() {
        UserDefaults.standard.removeObject(forKey: dedupKey)
    }

    // MARK: - Private

    private func fireNotification(progress: LimitProgress, threshold: Threshold) {
        let content = UNMutableNotificationContent()
        content.title = "\(progress.label) à \(threshold.label)"
        content.body = progress.sublabel
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }

    private func dedupKey(for limitId: String, threshold: Threshold, windowEnd: Date) -> String {
        let epoch = Int(windowEnd.timeIntervalSince1970)
        return "\(limitId)|\(threshold.rawValue)|\(epoch)"
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        var current = firedAlerts
        current = current.filter { $0.value > cutoff }
        firedAlerts = current
    }
}
