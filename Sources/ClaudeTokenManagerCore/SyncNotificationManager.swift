import Foundation
import UserNotifications

/// Sends a single macOS notification when the claude.ai live sync goes
/// down for an extended period (currently 3 consecutive refresh failures
/// per UsageStore). Identifier is fixed so the system replaces any
/// previous notification of the same type rather than stacking them.
@MainActor
public final class SyncNotificationManager {

    public static let shared = SyncNotificationManager()
    private init() {}

    private let notificationIdentifier = "com.lucas.claude-token-manager.sync-unavailable"

    /// Ask for authorization once. No-op if the user has already granted
    /// or refused — we never re-prompt, which would be intrusive.
    public func requestAuthorization() async {
        guard let center = notificationCenter() else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func sendSyncUnavailableNotification(since: Date) async {
        guard let center = notificationCenter() else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeStr = formatter.string(from: since)

        let content = UNMutableNotificationContent()
        content.title = "Claude Token Manager"
        content.body = "Live sync unavailable — last updated at \(timeStr)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    public func cancelSyncUnavailableNotification() {
        guard let center = notificationCenter() else { return }
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    /// UNUserNotificationCenter crashes when the process isn't an app
    /// bundle (CLI / test runner). Mirror NotificationManager's guard.
    private func notificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }
}
