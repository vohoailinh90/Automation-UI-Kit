import Foundation

/// A notification about doses: the parent's reminder that a dose is due, or
/// the family's alert that it is late. Plain data, the same on every
/// platform; `DoseNotifications` (IdeaLabUI) schedules it with iOS, as Time
/// Sensitive.
public struct DoseAlert: Identifiable, Hashable, Sendable {
    /// The same whenever a plan has an alert at this moment for this phone,
    /// whatever it says: planning again replaces the alert instead of adding
    /// a second one.
    public let id: String
    /// When it shows.
    public let date: Date
    /// The doses it is about, earliest first.
    public let doses: [DoseID]
    public let title: String
    public let body: String
    /// The same for every alert of a plan, so one person's alerts stay
    /// together in Notification Center.
    public let threadID: String
}

/// The alerts a phone should have, from `DoseAlerts.plan`: those to schedule,
/// and those already shown that are still true.
public struct DoseAlertPlan: Hashable, Sendable {
    /// Every alert for the plan's audience and scope has an id starting with
    /// this, and no other does: applying a plan leaves the app's other
    /// notifications alone, and the alerts about anyone else.
    public let prefix: String
    /// What to schedule, soonest first: at most the plan's limit, since iOS
    /// keeps an app's 64 soonest notifications and drops the rest.
    public let upcoming: [DoseAlert]
    /// The alerts whose moment has come and that are still true: on screen,
    /// or showing this very moment, so not to be cancelled. On the parent's
    /// phone, those about doses still waiting for an answer. On a family
    /// phone, those about doses that turned late and were never answered,
    /// since yesterday: the family keeps that news after the parent's screen
    /// has moved on. Any other alert with the prefix that has shown is out of
    /// date — answered, or no longer asked about — and should go.
    public let current: Set<String>
}

/// Which notifications a phone should have about the parent's doses, so the
/// app can schedule them ahead and take back the ones an answer makes wrong.
///
/// The parent's phone reminds when doses are due, and again when the grace
/// period (`DoseSchedule.grace`, 30 minutes, as Apple Health's follow-up
/// reminder) ends with no answer. A family member's phone is told at that
/// same moment, when the dose turns late: the moment `CaregiverScreen` turns
/// amber. Doses due at the same moment share one alert, so two pills at 07:00
/// buzz once.
///
/// Only doses with no answer in the log count, so plan again whenever the
/// log or the medicines change — an answer from any phone, an undo — and
/// whenever the app runs: iOS shows scheduled alerts on time with the app
/// closed, but only the app can take one back. A family phone knows what
/// the parent's phone has sent: its alert says "chưa xác nhận" (not
/// confirmed), and, given `updatedAt`, when that news arrived.
public enum DoseAlerts {
    /// Whose phone the alerts are for.
    public enum Audience: Hashable, Sendable {
        /// The person taking the medicines.
        case parent
        /// Someone watching over `personName` — "Mẹ", "Bố" — told when a
        /// dose goes late.
        case family(personName: String)
    }

    /// How many notifications iOS keeps scheduled for an app: its 64
    /// soonest; the rest are dropped.
    public static let systemLimit = 64

    /// How many days ahead a plan looks, when its limit does not stop it
    /// sooner: a month.
    private static let horizon = 31

    /// The alerts `audience`'s phone should have at `now`.
    ///
    /// - Parameters:
    ///   - scope: tells apart the people one phone keeps alerts for: the
    ///     person's id, say, on a phone watching over both parents. Plans
    ///     with another scope or audience have their own ids.
    ///   - calendar: the parent's, as on every screen: it decides the days
    ///     and the times the alerts name ("07:00"). The alerts' dates are
    ///     absolute, so they show at the parent's 07:00 on a phone abroad.
    ///   - updatedAt: for the family: when the log last arrived from the
    ///     parent's phone, as `CaregiverScreen` takes it.
    ///   - limit: this plan's share of the 64 notifications iOS keeps for an
    ///     app. Leave room for the app's other notifications, and split it
    ///     between the people a phone keeps alerts for.
    public static func plan(
        for audience: Audience,
        scope: String = "",
        medications: [Medication],
        log: DoseLog,
        now: Date,
        calendar: Calendar,
        updatedAt: Date? = nil,
        limit: Int = systemLimit
    ) -> DoseAlertPlan {
        let prefix = Self.prefix(for: audience, scope: scope)
        let isParent = audience == .parent
        // Unanswered doses by the second their alert shows at: one alert each.
        var moments: [Int64: Moment] = [:]
        let today = calendar.startOfDay(for: now)
        // From yesterday: the 23:45 pill turns late at 00:15.
        for offset in -1...horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for dose in DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar) where log[dose.id] == nil {
                if isParent, dose.time > now {
                    moments[second(dose.time), default: Moment(date: dose.time)].due.append(dose)
                }
                // A dose whose wait ends first never turns late: the next one
                // of its medicine is due by then, or it was stopped.
                let late = dose.time.addingTimeInterval(DoseSchedule.grace)
                if late < dose.waitsUntil, late > now {
                    moments[second(late), default: Moment(date: late)].late.append(dose)
                }
            }
            // Later days' doses come after this day ends, and so do their
            // alerts: the ones before are all in, and enough of them ends it.
            guard let next = calendar.date(byAdding: .day, value: offset + 1, to: today) else { continue }
            let end = calendar.startOfDay(for: next)
            if moments.values.count(where: { $0.date < end }) >= limit { break }
        }
        let threadID = String(prefix.dropLast())
        let upcoming = moments.sorted { $0.key < $1.key }.prefix(max(0, limit)).map { key, moment in
            alert(moment, id: prefix + String(key), threadID: threadID, for: audience, calendar: calendar, updatedAt: updatedAt)
        }
        // The alerts that have come and are still true, of yesterday's doses
        // and today's with no answer.
        var current: Set<String> = []
        for offset in -1...0 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for dose in DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar) where log[dose.id] == nil {
                let late = dose.time.addingTimeInterval(DoseSchedule.grace)
                if isParent {
                    // Still asked about: its time has come, and its follow-up's
                    // once the grace period is over.
                    guard DoseSchedule.status(of: dose, in: log, now: now).isWaiting else { continue }
                    current.insert(prefix + String(second(dose.time)))
                    if late <= now {
                        current.insert(prefix + String(second(late)))
                    }
                } else if late < dose.waitsUntil, late <= now {
                    // It turned late, and nobody answered since.
                    current.insert(prefix + String(second(late)))
                }
            }
        }
        return DoseAlertPlan(prefix: prefix, upcoming: Array(upcoming), current: current)
    }

    /// The doses one alert is about: due at its moment, or turning late then.
    private struct Moment {
        let date: Date
        var due: [ScheduledDose] = []
        var late: [ScheduledDose] = []
    }

    /// "idealab.meds.<scope>.<audience>.", with the scope percent-encoded: it
    /// has no dot then, so no scope's prefix starts another's.
    private static func prefix(for audience: Audience, scope: String) -> String {
        let encoded = scope.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let role = switch audience {
        case .parent: "parent"
        case .family: "family"
        }
        return "idealab.meds.\(encoded).\(role)."
    }

    private static func second(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    private static func alert(
        _ moment: Moment, id: String, threadID: String, for audience: Audience, calendar: Calendar, updatedAt: Date?
    ) -> DoseAlert {
        let title: String
        var lines: [String]
        // Late doses were due a grace period before the due ones.
        let lateTime = moment.late.first.map { clock($0.time, calendar) } ?? ""
        switch audience {
        case .parent where moment.due.isEmpty:
            title = "Nhắc lại: thuốc lúc \(lateTime)"
            lines = moment.late.map(detail) + ["Uống rồi thì bấm ĐÃ UỐNG."]
        case .parent:
            title = "Đến giờ uống thuốc"
            lines = moment.due.map(detail)
            if !moment.late.isEmpty {
                lines.append("Nhắc lại thuốc lúc \(lateTime): \(names(moment.late))")
            }
        case let .family(personName):
            title = "\(personName) chưa xác nhận thuốc lúc \(lateTime)"
            lines = [names(moment.late)]
            if let updatedAt {
                lines.append("Máy của \(personName) cập nhật lần cuối lúc \(stamp(updatedAt, before: moment.date, calendar)).")
            }
        }
        return DoseAlert(
            id: id,
            date: moment.date,
            doses: (moment.late + moment.due).map(\.id),
            title: title,
            body: lines.joined(separator: "\n"),
            threadID: threadID
        )
    }

    /// "Thuốc huyết áp: 1 viên · Sau ăn sáng", as the parent's screen shows it.
    private static func detail(_ dose: ScheduledDose) -> String {
        let medication = dose.medication
        let details = [medication.dose, medication.instructions].filter { !$0.isEmpty }.joined(separator: " · ")
        return details.isEmpty ? medication.name : "\(medication.name): \(details)"
    }

    private static func names(_ doses: [ScheduledDose]) -> String {
        doses.map(\.medication.name).joined(separator: ", ")
    }

    /// "07:00" on the parent's clock.
    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0).description
    }

    /// "06:58" on the alert's day, "21:03 hôm qua" the day before, and
    /// "21:03 ngày 22/9" before that: old news shows its age.
    private static func stamp(_ date: Date, before moment: Date, _ calendar: Calendar) -> String {
        let time = clock(date, calendar)
        if calendar.isDate(date, inSameDayAs: moment) { return time }
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: moment), calendar.isDate(date, inSameDayAs: dayBefore) {
            return "\(time) hôm qua"
        }
        let parts = calendar.dateComponents([.day, .month], from: date)
        return "\(time) ngày \(parts.day ?? 0)/\(parts.month ?? 0)"
    }
}
