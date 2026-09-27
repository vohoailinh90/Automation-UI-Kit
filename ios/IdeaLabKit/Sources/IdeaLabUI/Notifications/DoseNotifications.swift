#if os(iOS)
import IdeaLabCore
import UIKit
import UserNotifications

/// What this phone's settings let dose alerts do.
public enum DoseAlertAccess: Hashable, Sendable {
    /// iOS has not asked yet. Explain first (`PermissionPrimerScreen`), then
    /// ask (`DoseNotifications.requestAccess()`): iOS asks only once.
    case notAsked
    /// Notifications are off for the app, or allowed but shown nowhere: no
    /// Lock Screen, Notification Center or banners. Only Settings brings
    /// them back.
    case off
    /// They arrive, but may not interrupt: delivered quietly, without
    /// banners, or without Time Sensitive, so a Focus or the scheduled
    /// summary can hold them back. Time Sensitive is off in Settings, or not
    /// available at all: the app lacks the capability, a build to fix, which
    /// this makes plain.
    case quiet
    /// They show as banners as soon as they are due, and go through any
    /// Focus that lets Time Sensitive alerts through — a Focus's own setting
    /// no app can read.
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
    /// that are no longer true off the screen. One on screen that is still
    /// true but covers fewer doses — one of them answered since — shows
    /// again in its new words, quietly: an update, not news. Every other
    /// notification is left alone.
    ///
    /// Plan with the current time, just before: an alert whose moment passed
    /// since shows at once.
    public static func apply(_ plan: DoseAlertPlan, center: UNUserNotificationCenter = .current()) async throws {
        let upcoming = Dictionary(plan.upcoming.map { ($0.id, $0) }) { first, _ in first }
        let current = Dictionary(plan.current.map { ($0.id, $0) }) { first, _ in first }
        var scheduled: Set<String> = []
        var reworded: [DoseAlert] = []
        var cancelled: [String] = []
        for request in await center.pendingNotificationRequests() where request.identifier.hasPrefix(plan.prefix) {
            if let alert = upcoming[request.identifier] {
                // Changed, it is replaced below: a request with the same id
                // takes the place of the one scheduled.
                if matches(request, alert) { scheduled.insert(alert.id) }
            } else if let alert = current[request.identifier] {
                // Due this moment and still true: iOS is about to show it.
                // A dose of it answered since leaves its words.
                if !matches(request, alert) { reworded.append(alert) }
            } else {
                // Answered, stopped, or past the plan's limit.
                cancelled.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: cancelled)
        var shown: Set<String> = []
        var outdated: [String] = []
        var restated: [DoseAlert] = []
        for notification in await center.deliveredNotifications() where notification.request.identifier.hasPrefix(plan.prefix) {
            let id = notification.request.identifier
            shown.insert(id)
            if let alert = current[id] {
                // Its doses, not its words: the family's "cập nhật lần cuối"
                // line changes with every sync, and is news of its moment.
                if doses(of: notification.request) != keys(alert.doses) {
                    outdated.append(id)
                    restated.append(alert)
                }
            } else {
                outdated.append(id)
            }
        }
        center.removeDeliveredNotifications(withIdentifiers: outdated)
        for alert in plan.upcoming where !scheduled.contains(alert.id) {
            try await center.add(request(for: alert))
        }
        // Shown meanwhile, it is restated quietly instead: adding it here
        // would ring twice.
        for alert in reworded where !shown.contains(alert.id) {
            try await center.add(request(for: alert))
        }
        for alert in restated {
            try await center.add(quietRequest(for: alert))
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
            let presented = [settings.alertSetting, settings.lockScreenSetting, settings.notificationCenterSetting]
            guard presented.contains(.enabled) else { return .off }
            return settings.alertSetting == .enabled && settings.timeSensitiveSetting == .enabled ? .on : .quiet
        @unknown default:
            // Not known to show them: say so, rather than promise.
            return .quiet
        }
    }

    /// Asks iOS for permission — after the person has seen why — and returns
    /// what it allows. iOS shows its question once; after that this only
    /// reads the answer.
    public static func requestAccess(center: UNUserNotificationCenter = .current()) async -> DoseAlertAccess {
        // No `.timeSensitive` option: Apple deprecated it in iOS 15.0, the
        // version that brought it, for the entitlement ("Use time-sensitive
        // entitlement"). The capability is what lets these alerts through.
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

    /// Where a request keeps its alert's moment and doses, to tell whether
    /// they changed.
    private static let dateKey = "idealab.meds.date"
    private static let dosesKey = "idealab.meds.doses"

    private static func keys(_ doses: [DoseID]) -> [String] {
        doses.map { "\($0.medicationID.uuidString) \($0.time.timeIntervalSinceReferenceDate)" }
    }

    private static func doses(of request: UNNotificationRequest) -> [String]? {
        request.content.userInfo[dosesKey] as? [String]
    }

    private static func matches(_ request: UNNotificationRequest, _ alert: DoseAlert) -> Bool {
        let content = request.content
        return content.title == alert.title
            && content.body == alert.body
            && content.threadIdentifier == alert.threadID
            && content.interruptionLevel == .timeSensitive
            && (content.userInfo[dateKey] as? Double) == alert.date.timeIntervalSinceReferenceDate
            && doses(of: request) == keys(alert.doses)
    }

    private static func content(for alert: DoseAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = alert.threadID
        content.userInfo = [dateKey: alert.date.timeIntervalSinceReferenceDate, dosesKey: keys(alert.doses)]
        return content
    }

    private static func request(for alert: DoseAlert) -> UNNotificationRequest {
        let content = Self.content(for: alert)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        // A span of time, not a time of day: a calendar trigger moves with
        // the phone's time zone, and the alert belongs to a moment of the
        // parent's day wherever this phone is.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alert.date.timeIntervalSinceNow), repeats: false)
        return UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
    }

    /// An alert shown again in new words, at once: without a sound, and
    /// without lighting the screen.
    private static func quietRequest(for alert: DoseAlert) -> UNNotificationRequest {
        let content = Self.content(for: alert)
        content.interruptionLevel = .passive
        return UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
    }
}
#endif
