import Foundation

/// What the family's widget shows at a moment (`CaregiverWidgetTimeline`),
/// as their screen (`CaregiverScreen`) does: the parent's doses so far,
/// how many were taken, the ones late, and when the parent's phone last
/// sent its log, so old news does not look fresh.
public struct CaregiverWidgetEntry: Hashable, Sendable {
    public var date: Date
    /// How the family calls the parent: "Mẹ", "Bố", "Bà nội".
    public var personName: String
    /// Whether the parent has any medicine added, ended ones included.
    public var hasMedicines: Bool
    /// The doses due so far, today's and the day before's still waiting
    /// (at 00:30 the 21:00 pill still counts), and how many were taken.
    public var soFar: Int
    public var taken: Int
    /// The doses late at `date`, the grace period past with no answer
    /// (`DoseSchedule.grace`), earliest first.
    public var late: [ScheduledDose]
    /// When the parent's phone last sent its log; `nil` when unknown.
    public var updatedAt: Date?
    /// The start of `date`'s day on the parent's clock: the same log reads
    /// differently a day later ("21:00 hôm qua", "Cập nhật 24/9 21:00").
    public var day: Date

    public init(
        date: Date, personName: String, hasMedicines: Bool, soFar: Int, taken: Int, late: [ScheduledDose],
        updatedAt: Date?, day: Date
    ) {
        self.date = date
        self.personName = personName
        self.hasMedicines = hasMedicines
        self.soFar = soFar
        self.taken = taken
        self.late = late
        self.updatedAt = updatedAt
        self.day = day
    }

    /// Whether every dose due so far was taken, and one was.
    public var allTaken: Bool { soFar > 0 && taken == soFar }

    /// Whether `other` shows the same, whatever its date: no entry for it.
    func showsSame(as other: CaregiverWidgetEntry) -> Bool {
        var moved = other
        moved.date = date
        return moved == self
    }
}

/// The family's widget's timeline: what it shows now, then at each moment
/// that changes it while no news comes from the parent's phone: a dose
/// falls due, turns late, stops being asked about, and the day starts over
/// at midnight. The app asks WidgetKit for a new one when news comes
/// (`CaregiverWidgetStore.save`).
public enum CaregiverWidgetTimeline {
    /// What the widget shows at `date`, on `calendar`'s clock, the parent's.
    public static func entry(
        at date: Date, personName: String, medications: [Medication], log: DoseLog, updatedAt: Date?, calendar: Calendar
    ) -> CaregiverWidgetEntry {
        let today = DoseSchedule.doses(of: medications, onDayOf: date, calendar: calendar)
        let waiting = DoseSchedule.waiting(of: medications, in: log, now: date, calendar: calendar)
        // Last night's dose still unanswered after midnight counts, as on the
        // family's screen.
        let carried = waiting.filter { !calendar.isDate($0.time, inSameDayAs: date) }
        let summary = DoseSchedule.summary(of: carried + today, in: log, now: date)
        let late = waiting.filter {
            if case .late = DoseSchedule.status(of: $0, in: log, now: date) { true } else { false }
        }
        return CaregiverWidgetEntry(
            date: date, personName: personName, hasMedicines: !medications.isEmpty, soFar: summary.soFar,
            taken: summary.taken, late: late, updatedAt: updatedAt, day: calendar.startOfDay(for: date)
        )
    }

    /// The entries from `now` until `end(from:calendar:)`: now, then each
    /// moment a dose falls due, turns late or stops waiting
    /// (`ScheduledDose.waitsUntil`), and each midnight. A moment that
    /// changes nothing on the widget adds no entry.
    public static func entries(
        from now: Date, personName: String, medications: [Medication], log: DoseLog, updatedAt: Date?, calendar: Calendar
    ) -> [CaregiverWidgetEntry] {
        let today = calendar.startOfDay(for: now)
        let end = Self.end(from: now, calendar: calendar)
        var moments: Set<Date> = []
        for offset in 1...2 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: today) {
                moments.insert(midnight)
            }
        }
        for day in (-1...1).compactMap({ calendar.date(byAdding: .day, value: $0, to: today) }) {
            for dose in DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar) {
                moments.formUnion([dose.time, dose.time.addingTimeInterval(DoseSchedule.grace), dose.waitsUntil])
            }
        }
        var entries: [CaregiverWidgetEntry] = []
        for moment in [now] + moments.filter({ $0 > now && $0 < end }).sorted() {
            let next = entry(
                at: moment, personName: personName, medications: medications, log: log, updatedAt: updatedAt, calendar: calendar
            )
            if let last = entries.last, last.showsSame(as: next) { continue }
            entries.append(next)
        }
        return entries
    }

    /// Where the entries from `now` stop, when WidgetKit should ask for the
    /// next ones: the end of tomorrow, as for the parent's widget
    /// (`DoseWidgetTimeline.end`).
    public static func end(from now: Date, calendar: Calendar) -> Date {
        DoseWidgetTimeline.end(from: now, calendar: calendar)
    }
}

/// What the family's app shares with its widget: the parent's medicines,
/// their recent answers, when their phone last sent them, and the parent's
/// time zone, on whose clock the doses fall.
public struct CaregiverWidgetSnapshot: Hashable, Sendable, Codable {
    public var personName: String
    public var medications: [Medication]
    public var records: [DoseRecord]
    public var updatedAt: Date?
    public var timeZoneID: String

    /// - Parameter now: when the app shares it. Answers for doses before
    ///   yesterday are left out, as the widget shows none that old
    ///   (`DoseWidgetSnapshot`).
    public init(personName: String, medications: [Medication], log: DoseLog, updatedAt: Date?, timeZone: TimeZone, now: Date) {
        self.personName = personName
        self.medications = medications
        self.updatedAt = updatedAt
        timeZoneID = timeZone.identifier
        records = []
        records = DoseWidgetSnapshot.recent(log.records, now: now, calendar: calendar)
    }

    public var log: DoseLog { DoseLog(records) }

    /// The parent's calendar: Gregorian, in their time zone.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }

    /// The widget's entries from `now` (`CaregiverWidgetTimeline`).
    public func entries(from now: Date) -> [CaregiverWidgetEntry] {
        CaregiverWidgetTimeline.entries(
            from: now, personName: personName, medications: medications, log: log, updatedAt: updatedAt, calendar: calendar
        )
    }

    /// When the entries from `now` stop (`CaregiverWidgetTimeline.end`).
    public func timelineEnd(from now: Date) -> Date {
        CaregiverWidgetTimeline.end(from: now, calendar: calendar)
    }
}

/// Where the family's app and its widget meet: the defaults of an App
/// Group both belong to. Only the app writes, when news comes from the
/// parent's phone; the widget reads.
public struct CaregiverWidgetStore {
    private let defaults: UserDefaults?
    private let key: String

    /// - Parameter defaults: `UserDefaults(suiteName:)` with the App Group,
    ///   `nil` when there is none.
    public init(defaults: UserDefaults?, key: String = "IdeaLabMeds.caregiverWidget") {
        self.defaults = defaults
        self.key = key
    }

    /// What the app last shared; `nil` before it shared anything.
    public var snapshot: CaregiverWidgetSnapshot? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(CaregiverWidgetSnapshot.self, from: $0) }
    }

    /// Shares `snapshot`. Returns whether it changed what the widget reads:
    /// only then should the app ask WidgetKit for a new timeline, as reloads
    /// have a daily budget.
    @discardableResult
    public func save(_ snapshot: CaregiverWidgetSnapshot) -> Bool {
        // Compared as read back, not as bytes: JSON keeps no fixed key order.
        guard let defaults, self.snapshot != snapshot, let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// The family's widget's words, in one place. No medicine is named on the
/// Lock Screen: anyone near the phone can read it.
public enum CaregiverWidgetCopy {
    /// The headline: "07:00 chưa xác nhận" while a dose is late ("21:00 hôm
    /// qua chưa xác nhận" for last night's), else "Đã uống 1/3 liều" once a
    /// dose was due, "Chưa đến giờ uống thuốc" before, and "Chưa có thuốc
    /// nào" with no medicine added.
    public static func title(for entry: CaregiverWidgetEntry, calendar: Calendar) -> String {
        if let first = entry.late.first {
            return "\(DoseWidgetCopy.clock(of: first, on: entry.date, calendar: calendar)) chưa xác nhận"
        }
        if !entry.hasMedicines { return "Chưa có thuốc nào" }
        if entry.soFar == 0 { return "Chưa đến giờ uống thuốc" }
        return "Đã uống \(entry.taken)/\(entry.soFar) liều"
    }

    /// "+1 liều trễ khác", while more than one dose is late.
    public static func moreLate(for entry: CaregiverWidgetEntry) -> String? {
        entry.late.count > 1 ? "+\(entry.late.count - 1) liều trễ khác" : nil
    }

    /// "Cập nhật 07:05", or with the day, "Cập nhật 24/9 21:00", when the
    /// parent's phone last sent its log on another day than the entry's.
    /// `nil` when unknown.
    public static func updated(for entry: CaregiverWidgetEntry, calendar: Calendar) -> String? {
        guard let updatedAt = entry.updatedAt else { return nil }
        return "Cập nhật \(moment(updatedAt, on: entry.date, calendar: calendar))"
    }

    /// One short line above the Lock Screen's clock: "Mẹ: 07:00 chưa xác
    /// nhận", "Mẹ đã uống 1/3 liều", "Mẹ chưa đến giờ uống thuốc".
    public static func inline(for entry: CaregiverWidgetEntry, calendar: Calendar) -> String {
        if entry.late.isEmpty {
            let title = title(for: entry, calendar: calendar)
            return "\(entry.personName) \(title.prefix(1).lowercased())\(title.dropFirst())"
        }
        return "\(entry.personName): \(title(for: entry, calendar: calendar))"
    }

    /// What VoiceOver reads for the whole widget, in sentences: "Mẹ chưa
    /// xác nhận Thuốc huyết áp lúc 07:00. Đã uống 1 trong 3 liều đến giờ.
    /// Cập nhật lúc 07:05."
    ///
    /// - Parameter namingMedicines: whether to name the medicines late, as
    ///   the Home Screen's widget does. The Lock Screen's do not, as they
    ///   show none: VoiceOver may read them while the phone is locked, to
    ///   anyone near. "Mẹ chưa xác nhận liều 07:00."
    public static func spoken(for entry: CaregiverWidgetEntry, calendar: Calendar, namingMedicines: Bool = true) -> String {
        var sentences: [String] = []
        for dose in entry.late {
            let clock = DoseWidgetCopy.clock(of: dose, on: entry.date, calendar: calendar)
            let which = namingMedicines ? "\(dose.medication.name) lúc \(clock)" : "liều \(clock)"
            sentences.append("\(entry.personName) chưa xác nhận \(which).")
        }
        if !entry.hasMedicines {
            sentences.append("\(entry.personName) chưa có thuốc nào.")
        } else if entry.soFar == 0 {
            sentences.append("\(entry.personName) chưa đến giờ uống thuốc.")
        } else {
            let who = entry.late.isEmpty ? "\(entry.personName) đã uống" : "Đã uống"
            sentences.append("\(who) \(entry.taken) trong \(entry.soFar) liều đến giờ.")
        }
        if let updatedAt = entry.updatedAt {
            sentences.append("Cập nhật lúc \(moment(updatedAt, on: entry.date, calendar: calendar)).")
        }
        return sentences.joined(separator: " ")
    }

    /// "07:05" on `date`'s day, else "24/9 21:00", on the parent's clock,
    /// Gregorian whatever `calendar` is, as `LedgerExport` writes days.
    private static func moment(_ time: Date, on date: Date, calendar: Calendar) -> String {
        let clock = LedgerExport.time(time, calendar)
        guard !calendar.isDate(time, inSameDayAs: date) else { return clock }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.day, .month], from: time)
        return "\(parts.day ?? 0)/\(parts.month ?? 0) \(clock)"
    }
}
