import Foundation

/// What the parent's widget shows at a moment, on the Home Screen and the
/// Lock Screen: the dose waiting for an answer, else today's next one, else
/// how the day went and tomorrow's first. Computed ahead for every moment
/// that changes it (`DoseWidgetTimeline`), from what the app shares
/// (`DoseWidgetSnapshot`).
public struct DoseWidgetEntry: Hashable, Sendable {
    public enum Headline: Hashable, Sendable {
        /// Time to take it, within the grace period.
        case due(ScheduledDose)
        /// Past the grace period, and still asked about.
        case late(ScheduledDose)
        /// Nothing waiting: today's next dose.
        case next(ScheduledDose)
        /// Nothing more today, or no dose at all today: tomorrow's first
        /// dose, if there is one.
        case dayOver(tomorrow: ScheduledDose?)
        /// No medicine added yet.
        case noMedicines
    }

    /// When the widget starts showing this.
    public var date: Date
    public var headline: Headline
    /// Doses waiting for an answer besides the headline's.
    public var alsoWaiting: Int
    /// Today's doses after the headline's that are not due yet, earliest
    /// first, at most three: what the larger widget lists.
    public var laterToday: [ScheduledDose]
    /// Today's doses taken.
    public var taken: Int
    /// Today's doses, all of them.
    public var total: Int

    public init(
        date: Date, headline: Headline, alsoWaiting: Int = 0, laterToday: [ScheduledDose] = [], taken: Int = 0, total: Int = 0
    ) {
        self.date = date
        self.headline = headline
        self.alsoWaiting = alsoWaiting
        self.laterToday = laterToday
        self.taken = taken
        self.total = total
    }

    /// The dose the headline is about, if any.
    public var dose: ScheduledDose? {
        switch headline {
        case let .due(dose), let .late(dose), let .next(dose): dose
        case let .dayOver(tomorrow): tomorrow
        case .noMedicines: nil
        }
    }

    /// Whether the widget shows the same as `other`, whenever each starts.
    func showsSame(as other: DoseWidgetEntry) -> Bool {
        var moved = other
        moved.date = date
        return moved == self
    }
}

/// The widget's timeline: what it shows now, then at each moment that
/// changes it with no one answering. The app asks WidgetKit for a new one
/// when a dose is answered or the medicines change (`DoseWidgetStore.save`).
public enum DoseWidgetTimeline {
    /// How many of today's later doses an entry lists.
    public static let laterTodayLimit = 3

    /// What the widget shows at `date`, on `calendar`'s clock, the parent's:
    /// the earliest dose waiting for an answer, the day before's included
    /// (at 00:30 the 21:00 pill is still asked about); else today's next
    /// dose; else tomorrow's first. A medicine that ended or was stopped
    /// still counts as added: "no dose today", not "no medicine yet".
    public static func entry(at date: Date, medications: [Medication], log: DoseLog, calendar: Calendar) -> DoseWidgetEntry {
        let today = DoseSchedule.doses(of: medications, onDayOf: date, calendar: calendar)
        let summary = DoseSchedule.summary(of: today, in: log, now: date)
        let waiting = DoseSchedule.waiting(of: medications, in: log, now: date, calendar: calendar)
        let upcoming = today.filter { DoseSchedule.status(of: $0, in: log, now: date) == .upcoming }
        let headline: DoseWidgetEntry.Headline
        var later = upcoming
        if let first = waiting.first {
            headline = DoseSchedule.status(of: first, in: log, now: date) == .due ? .due(first) : .late(first)
        } else if let next = upcoming.first {
            headline = .next(next)
            later.removeFirst()
        } else {
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            let tomorrow = tomorrowStart.flatMap { DoseSchedule.doses(of: medications, onDayOf: $0, calendar: calendar).first }
            headline = medications.isEmpty ? .noMedicines : .dayOver(tomorrow: tomorrow)
        }
        return DoseWidgetEntry(
            date: date, headline: headline, alsoWaiting: max(waiting.count - 1, 0),
            laterToday: Array(later.prefix(laterTodayLimit)), taken: summary.taken, total: summary.total
        )
    }

    /// The entries from `now` until `end(from:calendar:)`: now, then each
    /// moment a dose falls due, turns late (`DoseSchedule.grace`) or stops
    /// waiting (`ScheduledDose.waitsUntil`), and midnight, when the day's
    /// count starts over. A moment that changes nothing on the widget adds
    /// no entry.
    public static func entries(from now: Date, medications: [Medication], log: DoseLog, calendar: Calendar) -> [DoseWidgetEntry] {
        let today = calendar.startOfDay(for: now)
        let end = Self.end(from: now, calendar: calendar)
        var moments: Set<Date> = []
        if let midnight = calendar.date(byAdding: .day, value: 1, to: today) {
            moments.insert(midnight)
        }
        for day in (-1...1).compactMap({ calendar.date(byAdding: .day, value: $0, to: today) }) {
            for dose in DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar) {
                moments.formUnion([dose.time, dose.time.addingTimeInterval(DoseSchedule.grace), dose.waitsUntil])
            }
        }
        var entries: [DoseWidgetEntry] = []
        for moment in [now] + moments.filter({ $0 > now && $0 < end }).sorted() {
            let next = entry(at: moment, medications: medications, log: log, calendar: calendar)
            if let last = entries.last, last.showsSame(as: next) { continue }
            entries.append(next)
        }
        return entries
    }

    /// Where the entries from `now` stop: the end of tomorrow, on
    /// `calendar`'s clock. Nothing on the widget changes between the last
    /// entry and then, and then the day's count starts over: when WidgetKit
    /// should ask for the next timeline (`TimelineReloadPolicy.after`). Not
    /// right after the last entry, which may be `now` itself.
    public static func end(from now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(2 * 86_400)
    }
}

/// What the app shares with its widget: the medicines, the recent answers,
/// and the parent's time zone, on whose clock the doses fall. The widget
/// reads it to make its timeline.
public struct DoseWidgetSnapshot: Hashable, Sendable, Codable {
    public var medications: [Medication]
    public var records: [DoseRecord]
    public var timeZoneID: String

    /// - Parameter now: when the app shares it. Answers for doses before
    ///   yesterday are left out: the widget shows no dose that old, and the
    ///   log grows every day while the widget reads it at each reload.
    public init(medications: [Medication], log: DoseLog, timeZone: TimeZone, now: Date) {
        self.medications = medications
        timeZoneID = timeZone.identifier
        records = []
        let calendar = self.calendar
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        records = log.records.filter { $0.dose.time >= yesterday }
    }

    public var log: DoseLog { DoseLog(records) }

    /// The parent's calendar: Gregorian, in their time zone.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }

    /// The widget's entries from `now` (`DoseWidgetTimeline`).
    public func entries(from now: Date) -> [DoseWidgetEntry] {
        DoseWidgetTimeline.entries(from: now, medications: medications, log: log, calendar: calendar)
    }

    /// When the entries from `now` stop, and WidgetKit should ask for the
    /// next ones (`DoseWidgetTimeline.end`).
    public func timelineEnd(from now: Date) -> Date {
        DoseWidgetTimeline.end(from: now, calendar: calendar)
    }
}

/// Where the app keeps the snapshot for its widget: the defaults of an App
/// Group the app and its widget extension both belong to.
public struct DoseWidgetStore {
    private let defaults: UserDefaults?
    private let key: String

    /// - Parameter defaults: `UserDefaults(suiteName:)` with the App Group,
    ///   `nil` when there is none.
    public init(defaults: UserDefaults?, key: String = "IdeaLabMeds.widget") {
        self.defaults = defaults
        self.key = key
    }

    /// What the app last shared; `nil` before it shared anything.
    public var snapshot: DoseWidgetSnapshot? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(DoseWidgetSnapshot.self, from: $0) }
    }

    /// Shares `snapshot`. Returns whether it changed what the widget reads:
    /// only then should the app ask WidgetKit for a new timeline, as reloads
    /// have a daily budget.
    @discardableResult
    public func save(_ snapshot: DoseWidgetSnapshot) -> Bool {
        // Compared as read back, not as bytes: JSON keeps no fixed key order.
        guard let defaults, self.snapshot != snapshot, let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// The widget's words, in one place.
public enum DoseWidgetCopy {
    /// "Đến giờ uống thuốc", "Chưa uống thuốc", "Liều tiếp theo", "Đã uống đủ
    /// hôm nay", "Hôm nay đã uống 2/3 liều".
    public static func title(for entry: DoseWidgetEntry) -> String {
        switch entry.headline {
        case .due: "Đến giờ uống thuốc"
        case .late: "Chưa uống thuốc"
        case .next: "Liều tiếp theo"
        case .dayOver:
            if entry.total == 0 {
                "Hôm nay không có liều nào"
            } else if entry.taken == entry.total {
                "Đã uống đủ hôm nay"
            } else {
                "Hôm nay đã uống \(entry.taken)/\(entry.total) liều"
            }
        case .noMedicines: "Chưa có thuốc nào"
        }
    }

    /// When the headline's dose is, on the parent's clock: "07:00", "21:00
    /// hôm qua" for the day before's, "Mai 07:00" for tomorrow's first.
    public static func time(for entry: DoseWidgetEntry, calendar: Calendar) -> String? {
        guard let dose = entry.dose else { return nil }
        let clock = LedgerExport.time(dose.time, calendar)
        if case .dayOver = entry.headline {
            return "Mai \(clock)"
        }
        return calendar.isDate(dose.time, inSameDayAs: entry.date) ? clock : "\(clock) hôm qua"
    }

    /// "Thuốc huyết áp · 1 viên": the medicine and how much.
    public static func medicine(_ dose: ScheduledDose) -> String {
        let medication = dose.medication
        return medication.dose.isEmpty ? medication.name : "\(medication.name) · \(medication.dose)"
    }

    /// "+1 liều khác chưa uống", while other doses wait too.
    public static func alsoWaiting(for entry: DoseWidgetEntry) -> String? {
        entry.alsoWaiting > 0 ? "+\(entry.alsoWaiting) liều khác chưa uống" : nil
    }

    /// "Hôm nay 1/4 liều": today's doses taken. `nil` on a day with none.
    public static func progress(for entry: DoseWidgetEntry) -> String? {
        entry.total > 0 ? "Hôm nay \(entry.taken)/\(entry.total) liều" : nil
    }

    /// One short line above the Lock Screen's clock, with no medicine's
    /// name, as it shows while the phone is locked: "Uống thuốc 07:00",
    /// "Chưa uống thuốc 07:00", "Thuốc lúc 12:00", "Đã uống đủ thuốc",
    /// "Hôm nay 2/3 liều", "Thuốc mai lúc 07:00", "Hôm nay không có thuốc".
    public static func inline(for entry: DoseWidgetEntry, calendar: Calendar) -> String {
        let clock = entry.dose.map { LedgerExport.time($0.time, calendar) } ?? ""
        switch entry.headline {
        case .due: return "Uống thuốc \(clock)"
        case .late: return "Chưa uống thuốc \(clock)"
        case .next: return "Thuốc lúc \(clock)"
        case .dayOver:
            if entry.total > 0 {
                return entry.taken == entry.total ? "Đã uống đủ thuốc" : "Hôm nay \(entry.taken)/\(entry.total) liều"
            }
            return entry.dose == nil ? "Hôm nay không có thuốc" : "Thuốc mai lúc \(clock)"
        case .noMedicines: return "Chưa có thuốc nào"
        }
    }

    /// What VoiceOver reads for the whole widget, in sentences: "Đến giờ
    /// uống thuốc, 07:00: Thuốc huyết áp, 1 viên. Còn 1 liều khác chưa uống.
    /// Hôm nay đã uống 1 trong 4 liều."
    public static func spoken(for entry: DoseWidgetEntry, calendar: Calendar) -> String {
        let title = title(for: entry)
        func what(_ dose: ScheduledDose) -> String {
            dose.medication.dose.isEmpty ? dose.medication.name : "\(dose.medication.name), \(dose.medication.dose)"
        }
        var sentences: [String] = []
        switch entry.headline {
        case .due(let dose), .late(let dose), .next(let dose):
            sentences.append("\(title), \(time(for: entry, calendar: calendar) ?? ""): \(what(dose)).")
            if entry.alsoWaiting > 0 {
                sentences.append("Còn \(entry.alsoWaiting) liều khác chưa uống.")
            }
            if entry.total > 0 {
                sentences.append("Hôm nay đã uống \(entry.taken) trong \(entry.total) liều.")
            }
        case .dayOver(let tomorrow):
            sentences.append("\(title).")
            if let tomorrow {
                sentences.append("Ngày mai, \(LedgerExport.time(tomorrow.time, calendar)): \(what(tomorrow)).")
            }
        case .noMedicines:
            sentences.append("\(title).")
        }
        return sentences.joined(separator: " ")
    }
}
