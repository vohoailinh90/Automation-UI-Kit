#if os(iOS)
import IdeaLabCore
import UIKit
import UserNotifications

/// What this phone's settings let dose alerts do.
public enum DoseAlertAccess: Hashable, Sendable {
    /// iOS has not asked yet. Explain first (`PermissionPrimerScreen`), then
    /// ask (`DoseNotifications.requestAccess()`): iOS asks only once.
    case notAsked
    /// Notifications are off for the app: only Settings turns them back on.
    case off
    /// They arrive, but may not interrupt: delivered quietly, or held back by
    /// a Focus or the scheduled summary, since Time Sensitive is off for the
    /// app. Settings turns it on.
    case quiet
    /// They show as soon as they are due, and go through any Focus that lets
    /// Time Sensitive alerts through — a Focus's own setting no app can read.
    case on
}

/// Schedules the alerts of a `DoseAlertPlan` as local notifications, Time
/// Sensitive: a dose due or late "requires immediate attention", so the
/// scheduled summary does not hold it back, nor a Focus that lets such
/// alerts through. `access()` reports when the app's own Time Sensitive
/// switch is off. Apple's rule for the level: only about something happening
/// now or within the hour, never marketing.
///
/// The app needs the Time Sensitive Notifications capability (entitlement
/// `com.apple.developer.usernotifications.time-sensitive`); without it iOS
/// shows the alerts as ordinary ones.
public enum DoseNotifications {
    /// Makes this phone's alerts match `plan`: schedules what is missing or
    /// changed, cancels the plan's other scheduled alerts, and takes alerts
    /// that are no longer true off the screen. Every other notification is
    /// left alone.
    ///
    /// Plan with the current time, just before: an alert whose moment passed
    /// since shows at once.
    public static func apply(_ plan: DoseAlertPlan, center: UNUserNotificationCenter = .current()) async throws {
        let wanted = Dictionary(plan.upcoming.map { ($0.id, $0) }) { first, _ in first }
        var scheduled: Set<String> = []
        var cancelled: [String] = []
        for request in await center.pendingNotificationRequests() where request.identifier.hasPrefix(plan.prefix) {
            if let alert = wanted[request.identifier] {
                // Changed, it is replaced below: a request with the same id
                // takes the place of the one scheduled.
                if matches(request, alert) { scheduled.insert(alert.id) }
            } else if !plan.current.contains(request.identifier) {
                // Answered, stopped, or past the plan's limit. One still true
                // is due this moment: iOS is about to show it.
                cancelled.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: cancelled)
        let outdated = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(plan.prefix) && !plan.current.contains($0) }
        center.removeDeliveredNotifications(withIdentifiers: outdated)
        for alert in plan.upcoming where !scheduled.contains(alert.id) {
            try await center.add(request(for: alert))
        }
    }

    /// What this phone's settings let dose alerts do. Read it again when the
    /// app comes back to the foreground: Settings may have changed it.
    public static func access(center: UNUserNotificationCenter = .current()) async -> DoseAlertAccess {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notAsked
        case .denied:
            return .off
        case .provisional:
            return .quiet
        case .authorized, .ephemeral:
            // `.notSupported`: no setting would change it.
            return settings.timeSensitiveSetting == .disabled ? .quiet : .on
        @unknown default:
            return .on
        }
    }

    /// Asks iOS for permission — after the person has seen why — and returns
    /// what it allows. iOS shows its question once; after that this only
    /// reads the answer.
    public static func requestAccess(center: UNUserNotificationCenter = .current()) async -> DoseAlertAccess {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await access(center: center)
    }

    /// Opens the app's notification settings, where alerts and Time Sensitive
    /// are turned back on.
    @MainActor
    public static func openSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Where a request keeps its alert's moment, to tell whether it changed.
    private static let dateKey = "idealab.meds.date"

    private static func matches(_ request: UNNotificationRequest, _ alert: DoseAlert) -> Bool {
        let content = request.content
        return content.title == alert.title
            && content.body == alert.body
            && content.threadIdentifier == alert.threadID
            && content.interruptionLevel == .timeSensitive
            && (content.userInfo[dateKey] as? Double) == alert.date.timeIntervalSinceReferenceDate
    }

    private static func request(for alert: DoseAlert) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.threadID
        content.interruptionLevel = .timeSensitive
        content.userInfo = [dateKey: alert.date.timeIntervalSinceReferenceDate]
        // A span of time, not a time of day: a calendar trigger moves with
        // the phone's time zone, and the alert belongs to a moment of the
        // parent's day wherever this phone is.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alert.date.timeIntervalSinceNow), repeats: false)
        return UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
    }
}
#endif
