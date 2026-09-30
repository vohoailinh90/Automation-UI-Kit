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
    /// A dose taken on the widget a moment ago (`DoseWidgetTimeline.answeredFor`):
    /// the Home Screen widget shows it, with "Hoàn tác", before moving on,
    /// so a second tap cannot answer the next dose by mistake.
    public var answered: Answered?

    /// A dose taken on the widget, and when.
    public struct Answered: Hashable, Sendable {
        public var dose: ScheduledDose
        public var at: Date

        public init(dose: ScheduledDose, at: Date) {
            self.dose = dose
            self.at = at
        }
    }

    /// The button the widget offers: "Hoàn tác" for the dose just taken on
    /// it, else "ĐÃ UỐNG" for the dose waiting. None for a dose not due yet.
    public var answer: DoseWidgetAnswer?

    public init(
        date: Date, headline: Headline, alsoWaiting: Int = 0, laterToday: [ScheduledDose] = [], taken: Int = 0, total: Int = 0,
        answered: Answered? = nil, answer: DoseWidgetAnswer? = nil
    ) {
        self.date = date
        self.headline = headline
        self.alsoWaiting = alsoWaiting
        self.laterToday = laterToday
        self.taken = taken
        self.total = total
        self.answered = answered
        self.answer = answer
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

/// What a button on the widget does to a dose: the app's intent records it
/// (`action`, `DoseWidgetStore.record`).
public enum DoseWidgetAnswer: Hashable, Sendable {
    /// "ĐÃ UỐNG": taken, now. `over`: what the log held for the dose when
    /// the widget was drawn, nothing or an answer undone.
    case take(ScheduledDose, over: DoseRecord?)
    /// "Hoàn tác": `answer`, given on the widget, undone; the dose is asked
    /// about again, as after the app's own "Hoàn tác".
    case undo(ScheduledDose, answer: DoseRecord)

    public var dose: ScheduledDose {
        switch self {
        case let .take(dose, _), let .undo(dose, _): dose
        }
    }

    /// What it records.
    public var outcome: DoseRecord.Outcome {
        switch self {
        case .take: .taken
        case .undo: .cleared
        }
    }

    /// What the button carries to the app's intent.
    public var action: DoseWidgetAction {
        switch self {
        case let .take(dose, over): DoseWidgetAction(dose: dose.id, outcome: .taken, drawnOver: over)
        case let .undo(dose, answer): DoseWidgetAction(dose: dose.id, outcome: .cleared, drawnOver: answer)
        }
    }
}

/// A widget button's answer as the app's intent carries it (`encoded`, one
/// App Intent parameter): the dose, what to record, and what the log held
/// for the dose when the widget was drawn. `DoseWidgetStore.record` applies
/// it only while the log still holds that: a button drawn before the app
/// answered the dose, which WidgetKit has not reloaded yet, must not
/// overwrite that answer, and a second tap before the reload records
/// nothing more.
public struct DoseWidgetAction: Hashable, Sendable, Codable {
    public var dose: DoseID
    public var outcome: DoseRecord.Outcome
    public var drawnOver: DoseRecord?

    public init(dose: DoseID, outcome: DoseRecord.Outcome, drawnOver: DoseRecord?) {
        self.dose = dose
        self.outcome = outcome
        self.drawnOver = drawnOver
    }

    /// As one string, for an App Intent parameter.
    public var encoded: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// From `encoded`; `nil` for anything else.
    public init?(encoded: String) {
        guard let data = encoded.data(using: .utf8), let action = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = action
    }
}

/// An answer given on the widget: the record the log keeps, and when the
/// button was tapped, on the phone's clock. The record's own stamp can be
/// later: `DoseLog.record` stamps it after the dose's last answer, which
/// another phone's clock may have put ahead. How long the widget shows the
/// answer counts from the tap.
public struct DoseWidgetTap: Hashable, Sendable, Codable {
    public var record: DoseRecord
    public var at: Date

    public init(record: DoseRecord, at: Date) {
        self.record = record
        self.at = at
    }
}

/// The widget's timeline: what it shows now, then at each moment that
/// changes it with no one answering. The app asks WidgetKit for a new one
/// when a dose is answered or the medicines change (`DoseWidgetStore.save`).
public enum DoseWidgetTimeline {
    /// How many of today's later doses an entry lists.
    public static let laterTodayLimit = 3

    /// How long a dose taken on the widget stays on it, with "Hoàn tác",
    /// before the widget moves on: five minutes, as WidgetKit asks a
    /// timeline's entries to be about that far apart.
    public static let answeredFor: TimeInterval = 5 * 60

    /// What the widget shows at `date`, on `calendar`'s clock, the parent's:
    /// the earliest dose waiting for an answer, the day before's included
    /// (at 00:30 the 21:00 pill is still asked about); else today's next
    /// dose; else tomorrow's first. A medicine that ended or was stopped
    /// still counts as added: "no dose today", not "no medicine yet".
    ///
    /// - Parameter answered: the latest answer given on the widget
    ///   (`DoseWidgetStore`), shown for `answeredFor` from its tap: a dose
    ///   taken, still the log's answer for its dose.
    public static func entry(
        at date: Date, medications: [Medication], log: DoseLog, calendar: Calendar, answered: DoseWidgetTap? = nil
    ) -> DoseWidgetEntry {
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
        let shown = shown(answered, at: date, medications: medications, log: log, calendar: calendar)
        let answer: DoseWidgetAnswer?
        if let shown, let tap = answered {
            answer = .undo(shown.dose, answer: tap.record)
        } else if case let .due(dose) = headline {
            answer = .take(dose, over: log.storedRecord(for: dose.id))
        } else if case let .late(dose) = headline {
            answer = .take(dose, over: log.storedRecord(for: dose.id))
        } else {
            answer = nil
        }
        return DoseWidgetEntry(
            date: date, headline: headline, alsoWaiting: max(waiting.count - 1, 0),
            laterToday: Array(later.prefix(laterTodayLimit)), taken: summary.taken, total: summary.total,
            answered: shown, answer: answer
        )
    }

    /// The widget's answer as the entry at `date` shows it, if it does.
    private static func shown(
        _ tap: DoseWidgetTap?, at date: Date, medications: [Medication], log: DoseLog, calendar: Calendar
    ) -> DoseWidgetEntry.Answered? {
        guard let tap, tap.record.outcome == .taken, log.storedRecord(for: tap.record.dose) == tap.record,
              date < tap.at.addingTimeInterval(answeredFor)
        else { return nil }
        let id = tap.record.dose
        let dose = DoseSchedule.doses(of: medications, onDayOf: id.time, calendar: calendar).first { $0.id == id }
        return dose.map { DoseWidgetEntry.Answered(dose: $0, at: tap.at) }
    }

    /// The entries from `now` until `end(from:calendar:)`: now, then each
    /// moment a dose falls due, turns late (`DoseSchedule.grace`) or stops
    /// waiting (`ScheduledDose.waitsUntil`), and midnight, when the day's
    /// count starts over; and when a dose taken on the widget stops showing
    /// (`answeredFor`). A moment that changes nothing on the widget adds no
    /// entry.
    public static func entries(
        from now: Date, medications: [Medication], log: DoseLog, calendar: Calendar, answered: DoseWidgetTap? = nil
    ) -> [DoseWidgetEntry] {
        let today = calendar.startOfDay(for: now)
        let end = Self.end(from: now, calendar: calendar)
        var moments: Set<Date> = []
        if let midnight = calendar.date(byAdding: .day, value: 1, to: today) {
            moments.insert(midnight)
        }
        if let answered {
            moments.insert(answered.at.addingTimeInterval(answeredFor))
        }
        for day in (-1...1).compactMap({ calendar.date(byAdding: .day, value: $0, to: today) }) {
            for dose in DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar) {
                moments.formUnion([dose.time, dose.time.addingTimeInterval(DoseSchedule.grace), dose.waitsUntil])
            }
        }
        var entries: [DoseWidgetEntry] = []
        for moment in [now] + moments.filter({ $0 > now && $0 < end }).sorted() {
            let next = entry(at: moment, medications: medications, log: log, calendar: calendar, answered: answered)
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
        records = Self.recent(log.records, now: now, calendar: calendar)
    }

    /// The records of doses from the day before `now` on, on `calendar`'s
    /// clock: all the widget ever shows.
    static func recent(_ records: [DoseRecord], now: Date, calendar: Calendar) -> [DoseRecord] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return records.filter { $0.dose.time >= yesterday }
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

/// Where the app and its widget meet: the defaults of an App Group both
/// belong to. The app shares its snapshot (`save`); the widget keeps the
/// answers given on it apart (`record`, `answers`) and shows them at once,
/// and the app takes them into its log when it next becomes active. Each
/// writes only its own: the app never clears the widget's answers, which
/// the widget may be adding to meanwhile; the widget drops them after a day.
public struct DoseWidgetStore {
    private let defaults: UserDefaults?
    private let key: String

    private var answersKey: String { key + ".answers" }

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

    /// The answers given on the widget, doses from the day before on, one
    /// per dose. The app merges them into its log when it becomes active
    /// (`DoseLog.merge` keeps a dose's latest answer, so merging twice
    /// changes nothing), then shares its log again.
    public var answers: [DoseRecord] {
        DoseLog(taps.map(\.record)).records
    }

    /// The answers given on the widget, with when each was tapped.
    public var taps: [DoseWidgetTap] {
        defaults?.data(forKey: answersKey).flatMap { try? JSONDecoder().decode([DoseWidgetTap].self, from: $0) } ?? []
    }

    /// The log as the widget knows it: the app's, with the answers given on
    /// the widget. `nil` before the app shared anything.
    public var log: DoseLog? {
        snapshot.map { Self.log(of: $0, answers: taps.map(\.record)) }
    }

    /// Records the answer a button on the widget carries
    /// (`DoseWidgetAnswer.action`), stamped after what the log holds for its
    /// dose, as `DoseLog.record` does. Returns the log with it, for the
    /// parent's reminders to be planned again (`DoseAlerts`); `nil`,
    /// recording nothing, when the log no longer holds for the dose what the
    /// widget was drawn with (the app answered it since, or a first tap
    /// did), before the app shared anything, or without an App Group.
    @discardableResult
    public func record(_ action: DoseWidgetAction, at time: Date) -> DoseLog? {
        record(action.outcome, for: action.dose, at: time) { $0.storedRecord(for: action.dose) == action.drawnOver }
    }

    /// Records `outcome` for `dose` as given on the widget, if `holds` for
    /// the log as the widget knows it.
    @discardableResult
    func record(
        _ outcome: DoseRecord.Outcome, for dose: DoseID, at time: Date, if holds: (DoseLog) -> Bool = { _ in true }
    ) -> DoseLog? {
        guard let defaults, let snapshot else { return nil }
        let taps = taps
        var log = Self.log(of: snapshot, answers: taps.map(\.record))
        guard holds(log) else { return nil }
        log.record(outcome, for: dose, at: time)
        guard let record = log.storedRecord(for: dose) else { return nil }
        // One per dose, the new one in place of the dose's last; doses from
        // the day before on.
        let all = taps.filter { $0.record.dose != dose } + [DoseWidgetTap(record: record, at: time)]
        let recent = Set(DoseWidgetSnapshot.recent(all.map(\.record), now: time, calendar: snapshot.calendar).map(\.dose))
        let kept = all.filter { recent.contains($0.record.dose) }
        guard let data = try? JSONEncoder().encode(kept) else { return nil }
        defaults.set(data, forKey: answersKey)
        return log
    }

    /// The widget's entries from `now` (`DoseWidgetTimeline`): the app's
    /// snapshot with the answers given on the widget, the latest taken shown
    /// for a moment with "Hoàn tác". `nil` before the app shared anything.
    public func entries(from now: Date) -> [DoseWidgetEntry]? {
        guard let snapshot else { return nil }
        let taps = taps
        return DoseWidgetTimeline.entries(
            from: now, medications: snapshot.medications, log: Self.log(of: snapshot, answers: taps.map(\.record)),
            calendar: snapshot.calendar, answered: taps.max { $0.at < $1.at }
        )
    }

    private static func log(of snapshot: DoseWidgetSnapshot, answers: [DoseRecord]) -> DoseLog {
        var log = snapshot.log
        for answer in answers {
            log.merge(answer)
        }
        return log
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
        if case .dayOver = entry.headline {
            return "Mai \(LedgerExport.time(dose.time, calendar))"
        }
        return clock(of: dose, on: entry.date, calendar: calendar)
    }

    /// A dose's time on the parent's clock, seen on `date`: "07:00", or
    /// "21:00 hôm qua" for the day before's.
    public static func clock(of dose: ScheduledDose, on date: Date, calendar: Calendar) -> String {
        let clock = LedgerExport.time(dose.time, calendar)
        return calendar.isDate(dose.time, inSameDayAs: date) ? clock : "\(clock) hôm qua"
    }

    /// The headline while a dose taken on the widget shows (`answered`).
    public static let answered = "Đã uống"

    /// A button's words: "ĐÃ UỐNG", as on the parent's screen, or "Hoàn tác".
    public static func title(for answer: DoseWidgetAnswer) -> String {
        switch answer {
        case .take: "ĐÃ UỐNG"
        case .undo: "Hoàn tác"
        }
    }

    /// What VoiceOver reads for a button, naming its dose: "Đã uống Thuốc
    /// huyết áp, liều 07:00", "Hoàn tác, Thuốc huyết áp liều 07:00 chưa
    /// uống".
    public static func spoken(for answer: DoseWidgetAnswer, on date: Date, calendar: Calendar) -> String {
        let dose = answer.dose
        let clock = clock(of: dose, on: date, calendar: calendar)
        switch answer {
        case .take: return "Đã uống \(dose.medication.name), liều \(clock)"
        case .undo: return "Hoàn tác, \(dose.medication.name) liều \(clock) chưa uống"
        }
    }

    /// "Thuốc huyết áp · 1 viên": the medicine and how much.
    public static func medicine(_ dose: ScheduledDose) -> String {
        let medication = dose.medication
        return medication.dose.isEmpty ? medication.name : "\(medication.name) · \(medication.dose)"
    }

    /// "+1 liều khác chưa uống", while other doses wait too.
    public static func alsoWaiting(for entry: DoseWidgetEntry) -> String? {
        let others = othersWaiting(entry)
        return others > 0 ? "+\(others) liều khác chưa uống" : nil
    }

    /// The doses waiting besides the one the Home Screen shows: while a dose
    /// just taken on the widget shows, the headline's own too.
    private static func othersWaiting(_ entry: DoseWidgetEntry) -> Int {
        guard entry.answered != nil else { return entry.alsoWaiting }
        switch entry.headline {
        case .due, .late: return entry.alsoWaiting + 1
        case .next, .dayOver, .noMedicines: return entry.alsoWaiting
        }
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
    ///
    /// - Parameter showingAnswered: whether the widget shows a dose just
    ///   taken on it (`answered`): the Home Screen's do, and read "Đã uống
    ///   Thuốc huyết áp, 1 viên, liều 07:00." first.
    public static func spoken(for entry: DoseWidgetEntry, calendar: Calendar, showingAnswered: Bool = true) -> String {
        let title = title(for: entry)
        func what(_ dose: ScheduledDose) -> String {
            dose.medication.dose.isEmpty ? dose.medication.name : "\(dose.medication.name), \(dose.medication.dose)"
        }
        var sentences: [String] = []
        if showingAnswered, let answered = entry.answered {
            let dose = answered.dose
            sentences.append("\(Self.answered) \(what(dose)), liều \(clock(of: dose, on: entry.date, calendar: calendar)).")
            let others = othersWaiting(entry)
            if others > 0 {
                sentences.append("Còn \(others) liều khác chưa uống.")
            }
            if entry.total > 0 {
                sentences.append("Hôm nay đã uống \(entry.taken) trong \(entry.total) liều.")
            }
            return sentences.joined(separator: " ")
        }
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
