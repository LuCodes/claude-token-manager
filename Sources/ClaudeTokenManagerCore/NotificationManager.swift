import Foundation
import UserNotifications
import AppKit

/// Sends budget threshold notifications and claude.ai bar alerts.
public final class NotificationManager {

    public static let shared = NotificationManager()

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

    public func requestAuthorizationIfNeeded() async -> Bool {
        guard let center = notificationCenter() else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    /// Evaluate daily budget and fire notifications at 80% and 95%.
    public func evaluate(currentValue: Double, budget: Double?, isMoney: Bool) {
        guard let budget = budget, budget > 0 else { return }
        let percent = Int((currentValue / budget * 100).rounded(.down))
        let today = Calendar.current.startOfDay(for: Date())

        for threshold in Threshold.allCases where percent >= threshold.rawValue {
            let key = "budget-\(threshold.rawValue)-\(Int(today.timeIntervalSince1970))"
            if firedAlerts[key] != nil { continue }

            fireBudgetNotification(
                currentValue: currentValue, budget: budget,
                isMoney: isMoney, threshold: threshold
            )
            var updated = firedAlerts
            updated[key] = Date()
            firedAlerts = updated
        }
        pruneOldEntries()
    }

    /// Evaluate a claude.ai progress bar and fire notification if it crosses a threshold.
    public func evaluateProgressBar(_ bar: RemoteProgressBar) {
        let percent = Int(bar.clampedPercent.rounded(.down))
        let today = Calendar.current.startOfDay(for: Date())
        let windowEnd = bar.resetsAt ?? today.addingTimeInterval(24 * 3600)

        for threshold in Threshold.allCases where percent >= threshold.rawValue {
            let key = "bar-\(bar.id)-\(threshold.rawValue)-\(Int(windowEnd.timeIntervalSince1970))"
            if firedAlerts[key] != nil { continue }
            fireProgressBarNotification(bar: bar, percent: percent, threshold: threshold)
            var updated = firedAlerts
            updated[key] = Date()
            firedAlerts = updated
        }
        pruneOldEntries()
    }

    /// Check if a notification has already been fired for a given bar+threshold combo.
    internal func hasFired(barId: String, threshold: Threshold, windowEnd: Date) -> Bool {
        let key = "bar-\(barId)-\(threshold.rawValue)-\(Int(windowEnd.timeIntervalSince1970))"
        return firedAlerts[key] != nil
    }

    public func clearAllFiredAlerts() {
        UserDefaults.standard.removeObject(forKey: dedupKey)
    }

    // MARK: - Private

    /// Returns UNUserNotificationCenter only when running as an app bundle.
    /// Returns nil in test/CLI environments where it would crash.
    private func notificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    private func fireBudgetNotification(currentValue: Double, budget: Double, isMoney: Bool, threshold: Threshold) {
        let content = UNMutableNotificationContent()
        content.title = "Budget quotidien \u{00E0} \(threshold.label)"

        if isMoney {
            let remaining = max(0, budget - currentValue)
            content.body = "\(CostFormatter.format(currentValue)) sur \(CostFormatter.format(budget)) \u{00B7} il reste \(CostFormatter.format(remaining))"
        } else {
            let used = TokenFormatter.compact(Int(currentValue))
            let total = TokenFormatter.compact(Int(budget))
            let remaining = TokenFormatter.compact(max(0, Int(budget - currentValue)))
            content.body = "\(used) sur \(total) tokens \u{00B7} il reste \(remaining)"
        }
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter()?.add(request) { _ in }
    }

    private func fireProgressBarNotification(bar: RemoteProgressBar, percent: Int, threshold: Threshold) {
        let content = UNMutableNotificationContent()
        content.title = "\(bar.label) \u{00E0} \(threshold.label)"
        if let resetsAt = bar.resetsAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "EEE HH:mm"
            content.body = "R\u{00E9}initialisation \(formatter.string(from: resetsAt))"
        } else {
            content.body = "\(percent) % atteints"
        }
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter()?.add(request) { _ in }
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var current = firedAlerts
        current = current.filter { $0.value > cutoff }
        firedAlerts = current
    }
}
