import Foundation

/// Identifies one planned intake: this medication, at this moment.
public struct DoseID: Hashable, Sendable, Codable {
    public var medicationID: UUID
    public var time: Date

    public init(medicationID: UUID, time: Date) {
        self.medicationID = medicationID
        self.time = time
    }
}

/// One planned intake, with the medication it belongs to.
public struct ScheduledDose: Identifiable, Hashable, Sendable {
    public var medication: Medication
    public var time: Date
    /// When the dose stops waiting for an answer: when the same medicine's
    /// next dose is due, or `DoseSchedule.maxWait` after its time, whichever
    /// comes first. Then it is `.missed`, and the parent's screen moves on —
    /// "ĐÃ UỐNG" at 19:00 is for the evening pill, not the morning one.
    public var waitsUntil: Date

    public init(medication: Medication, time: Date, waitsUntil: Date? = nil) {
        self.medication = medication
        self.time = time
        self.waitsUntil = waitsUntil ?? time.addingTimeInterval(DoseSchedule.maxWait)
    }

    public var id: DoseID { DoseID(medicationID: medication.id, time: time) }
}

/// What happened to a dose — the only thing stored per dose. Everything
/// else (due, late, upcoming) is derived from the clock.
public struct DoseRecord: Hashable, Sendable, Codable {
    public enum Outcome: String, Hashable, Sendable, Codable {
        case taken
        case skipped
        /// Undone: the dose goes back to what the clock says. Stored like an
        /// answer, so the undo syncs and an older answer cannot come back.
        case cleared
    }

    public var dose: DoseID
    public var outcome: Outcome
    public var recordedAt: Date

    public init(dose: DoseID, outcome: Outcome, recordedAt: Date) {
        self.dose = dose
        self.outcome = outcome
        self.recordedAt = recordedAt
    }
}

/// The records of a household, looked up by dose. The latest answer for a
/// dose wins, so "Đã uống" after an accidental "Bỏ qua" simply corrects it.
///
/// Times are compared by the whole second, since stores keep different
/// precision (at least whole seconds, cut off rather than rounded, as
/// ISO 8601 and Unix seconds are). Two records from the same second (two
/// phones syncing) resolve taken over skipped over cleared, whichever arrives
/// first, so every device agrees.
public struct DoseLog: Hashable, Sendable {
    private var byDose: [DoseID: DoseRecord] = [:]

    /// Records from storage or other devices, in any order.
    public init<S: Sequence>(_ records: S) where S.Element == DoseRecord {
        for record in records { merge(record) }
    }

    public init() {}

    /// The answer for a dose: `nil` if there is none, or it was undone.
    public subscript(dose: DoseID) -> DoseRecord? {
        byDose[dose].flatMap { $0.outcome == .cleared ? nil : $0 }
    }

    /// What is stored for a dose, an undo included: it changes whenever
    /// anything is recorded for the dose, here or on another phone.
    public func storedRecord(for dose: DoseID) -> DoseRecord? {
        byDose[dose]
    }

    /// Everything to store and sync, undos included (as `.cleared`), by dose
    /// time and then medication, so the order never depends on the input's.
    public var records: [DoseRecord] {
        byDose.values.sorted {
            ($0.dose.time, $0.dose.medicationID.uuidString) < ($1.dose.time, $1.dose.medicationID.uuidString)
        }
    }

    /// An answer given on this device. It replaces what the log shows for the
    /// dose, so it is stamped at least a whole second after that record —
    /// even with a frozen or earlier clock — and stays later however a store
    /// cuts or rounds the seconds: every device resolves the two the same way.
    public mutating func record(_ outcome: DoseRecord.Outcome, for dose: DoseID, at time: Date) {
        // A nonsense clock is kept in range, so the record still syncs.
        let clock = time.timeIntervalSinceReferenceDate
        var stamp = clock.isNaN ? 0 : min(max(clock, -Self.clockRange), Self.clockRange)
        if let existing = byDose[dose] {
            stamp = max(stamp, existing.recordedAt.timeIntervalSinceReferenceDate + 1)
        }
        byDose[dose] = DoseRecord(dose: dose, outcome: outcome, recordedAt: Date(timeIntervalSinceReferenceDate: stamp))
    }

    /// Undo: the dose goes back to whatever the clock says it is.
    public mutating func undo(_ dose: DoseID, at time: Date) {
        record(.cleared, for: dose, at: time)
    }

    /// Adds a record from storage or another device, keeping the latest. A
    /// record whose date cannot be a clock's (not a number, or hundreds of
    /// thousands of years away) is corrupt and dropped, the same way on every
    /// phone. A clock that is merely wrong — set to 2099 — still counts.
    public mutating func merge(_ record: DoseRecord) {
        guard abs(record.recordedAt.timeIntervalSinceReferenceDate) <= 10 * Self.clockRange else { return }
        if let existing = byDose[record.dose], !Self.isNewer(record, than: existing) { return }
        byDose[record.dose] = record
    }

    /// About 31,700 years either side of 2001: wider than any clock, and
    /// narrow enough that a `Double` still counts single seconds.
    private static let clockRange: TimeInterval = 1e12

    private static func isNewer(_ record: DoseRecord, than existing: DoseRecord) -> Bool {
        let new = record.recordedAt.timeIntervalSinceReferenceDate.rounded(.down)
        let old = existing.recordedAt.timeIntervalSinceReferenceDate.rounded(.down)
        return new != old ? new > old : rank(record.outcome) > rank(existing.outcome)
    }

    private static func rank(_ outcome: DoseRecord.Outcome) -> Int {
        switch outcome {
        case .taken: 2
        case .skipped: 1
        case .cleared: 0
        }
    }

}

public enum DoseStatus: Hashable, Sendable {
    /// Not yet time.
    case upcoming
    /// Time to take it, still within the grace period.
    case due
    /// The grace period passed with no answer: this is when the family is told.
    case late(by: TimeInterval)
    /// Never answered, and no longer asked about: the medicine's next dose is
    /// due, or 12 hours went by. Counted as not taken.
    case missed
    case taken(at: Date)
    case skipped(at: Date)

    /// Due or late: the parent's screen should ask about it.
    public var isWaiting: Bool {
        switch self {
        case .due, .late: true
        case .upcoming, .missed, .taken, .skipped: false
        }
    }
}

public enum DoseSchedule {
    /// 30 minutes: when Apple Health's Medications reminds a second time, and
    /// when the idea's "con cái nhận báo" notification goes to the family.
    public static let grace: TimeInterval = 30 * 60

    /// 12 hours: the longest a dose waits for an answer. Much later, taking
    /// it would crowd the next dose, and the parent's screen should not ask
    /// about the morning pill all evening.
    public static let maxWait: TimeInterval = 12 * 3_600

    /// Every dose of `medications` on the day containing `day`, earliest
    /// first (by name when two share a time, then by id, so the order never
    /// depends on the input's), in `calendar`'s time zone — the parent's, on
    /// every phone. Doses outside a medicine's start and end dates are left
    /// out, and so is a second time that a daylight-saving change lands on
    /// the same instant.
    public static func doses(of medications: [Medication], onDayOf day: Date, calendar: Calendar) -> [ScheduledDose] {
        let start = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)
        return medications
            .flatMap { medication in
                let times = Set(medication.times.compactMap { $0.date(onDayOf: start, calendar: calendar) }).sorted()
                let tomorrow = nextDay.flatMap { next in medication.times.compactMap { $0.date(onDayOf: next, calendar: calendar) }.min() }
                return times.indices.compactMap { index -> ScheduledDose? in
                    let time = times[index]
                    guard medication.isScheduled(at: time) else { return nil }
                    let limit = time.addingTimeInterval(maxWait)
                    let next = index + 1 < times.count ? times[index + 1] : tomorrow
                    let waitsUntil = next.flatMap { medication.isScheduled(at: $0) ? min($0, limit) : nil } ?? limit
                    return ScheduledDose(medication: medication, time: time, waitsUntil: waitsUntil)
                }
            }
            .sorted {
                ($0.time, $0.medication.name, $0.medication.id.uuidString) < ($1.time, $1.medication.name, $1.medication.id.uuidString)
            }
    }

    /// Every dose waiting for an answer at `now`, earliest first: today's, and
    /// the day before's that still wait — at 00:30 the 21:00 pill is still
    /// asked about.
    public static func waiting(of medications: [Medication], in log: DoseLog, now: Date, calendar: Calendar) -> [ScheduledDose] {
        let today = calendar.startOfDay(for: now)
        let days = [calendar.date(byAdding: .day, value: -1, to: today), today].compactMap { $0 }
        return days
            .flatMap { doses(of: medications, onDayOf: $0, calendar: calendar) }
            .filter { status(of: $0, in: log, now: now).isWaiting }
    }

    public static func status(of dose: ScheduledDose, in log: DoseLog, now: Date, grace: TimeInterval = grace) -> DoseStatus {
        if let record = log[dose.id] {
            return record.outcome == .taken ? .taken(at: record.recordedAt) : .skipped(at: record.recordedAt)
        }
        guard now >= dose.time else { return .upcoming }
        guard now < dose.waitsUntil else { return .missed }
        let overdue = now.timeIntervalSince(dose.time)
        return overdue < grace ? .due : .late(by: overdue)
    }

    /// The dose the parent's screen is about: the earliest of `doses` still
    /// waiting for an answer. `nil` when nothing is waiting. Pass
    /// `waiting(of:in:now:calendar:)` to include the day before's.
    public static func current(of doses: [ScheduledDose], in log: DoseLog, now: Date) -> ScheduledDose? {
        doses.first { status(of: $0, in: log, now: now).isWaiting }
    }

    /// The next dose that is not yet due.
    public static func next(of doses: [ScheduledDose], in log: DoseLog, now: Date) -> ScheduledDose? {
        doses.first { status(of: $0, in: log, now: now) == .upcoming }
    }

    public struct DaySummary: Hashable, Sendable {
        public var taken = 0
        public var skipped = 0
        public var late = 0
        public var due = 0
        public var missed = 0
        public var upcoming = 0

        public init() {}

        public var total: Int { soFar + upcoming }
        /// Doses whose time has come: the denominator for "2 / 3 liều".
        public var soFar: Int { taken + skipped + late + due + missed }
    }

    public static func summary(of doses: [ScheduledDose], in log: DoseLog, now: Date) -> DaySummary {
        doses.reduce(into: DaySummary()) { summary, dose in
            switch status(of: dose, in: log, now: now) {
            case .taken: summary.taken += 1
            case .skipped: summary.skipped += 1
            case .late: summary.late += 1
            case .due: summary.due += 1
            case .missed: summary.missed += 1
            case .upcoming: summary.upcoming += 1
            }
        }
    }

    /// Share of the day's settled doses that were taken: those answered, plus
    /// those whose grace period is over. `nil` when none is settled yet, so a
    /// morning with nothing due does not read as 0%.
    public static func adherence(of doses: [ScheduledDose], in log: DoseLog, now: Date, grace: TimeInterval = grace) -> Double? {
        var settled = 0
        var taken = 0
        for dose in doses {
            switch status(of: dose, in: log, now: now, grace: grace) {
            case .taken: settled += 1; taken += 1
            case .skipped, .late, .missed: settled += 1
            case .due, .upcoming: break
            }
        }
        return settled == 0 ? nil : Double(taken) / Double(settled)
    }
}

/// Spoken-style Vietnamese durations for status lines: "35 phút",
/// "2 giờ", "2 giờ 41 phút", "1 ngày 3 giờ". Rounded down to the minute —
/// "trễ 30 phút" should not appear at 29 minutes 40 seconds.
public enum VietnameseDuration {
    public static func string(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        let days = minutes / (24 * 60)
        let hours = (minutes / 60) % 24
        let remainder = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days) ngày \(hours) giờ" : "\(days) ngày"
        }
        if hours > 0 {
            return remainder > 0 ? "\(hours) giờ \(remainder) phút" : "\(hours) giờ"
        }
        return "\(remainder) phút"
    }
}
