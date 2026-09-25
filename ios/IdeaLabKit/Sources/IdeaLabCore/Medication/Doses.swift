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

    public init(medication: Medication, time: Date) {
        self.medication = medication
        self.time = time
    }

    public var id: DoseID { DoseID(medicationID: medication.id, time: time) }
}

/// What happened to a dose — the only thing stored per dose. Everything
/// else (due, late, upcoming) is derived from the clock.
public struct DoseRecord: Hashable, Sendable, Codable {
    public enum Outcome: String, Hashable, Sendable, Codable {
        case taken
        case skipped
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

/// The records of a household, looked up by dose. Recording the same dose
/// twice keeps the latest answer, so "Đã uống" after an accidental "Bỏ qua"
/// simply corrects it.
public struct DoseLog: Hashable, Sendable {
    private var byDose: [DoseID: DoseRecord] = [:]

    public init<S: Sequence>(_ records: S) where S.Element == DoseRecord {
        for record in records { insert(record) }
    }

    public init() {}

    public subscript(dose: DoseID) -> DoseRecord? {
        byDose[dose]
    }

    public var records: [DoseRecord] {
        byDose.values.sorted { ($0.dose.time, $0.recordedAt) < ($1.dose.time, $1.recordedAt) }
    }

    public mutating func record(_ outcome: DoseRecord.Outcome, for dose: DoseID, at time: Date) {
        insert(DoseRecord(dose: dose, outcome: outcome, recordedAt: time))
    }

    /// Undo: the dose goes back to whatever the clock says it is.
    @discardableResult
    public mutating func remove(_ dose: DoseID) -> DoseRecord? {
        byDose.removeValue(forKey: dose)
    }

    private mutating func insert(_ record: DoseRecord) {
        if let existing = byDose[record.dose], existing.recordedAt > record.recordedAt { return }
        byDose[record.dose] = record
    }
}

public enum DoseStatus: Hashable, Sendable {
    /// Not yet time.
    case upcoming
    /// Time to take it, still within the grace period.
    case due
    /// The grace period passed with no answer: this is when the family is told.
    case late(by: TimeInterval)
    case taken(at: Date)
    case skipped(at: Date)

    /// Due or late: the parent's screen should ask about it.
    public var isWaiting: Bool {
        switch self {
        case .due, .late: true
        case .upcoming, .taken, .skipped: false
        }
    }
}

public enum DoseSchedule {
    /// 30 minutes: when Apple Health's Medications reminds a second time, and
    /// when the idea's "con cái nhận báo" notification goes to the family.
    public static let grace: TimeInterval = 30 * 60

    /// Every dose of `medications` on the day containing `day`, earliest
    /// first (by name when two share a time), in `calendar`'s time zone.
    public static func doses(of medications: [Medication], onDayOf day: Date, calendar: Calendar) -> [ScheduledDose] {
        medications
            .flatMap { medication in
                medication.times.compactMap { time in
                    time.date(onDayOf: day, calendar: calendar).map { ScheduledDose(medication: medication, time: $0) }
                }
            }
            .sorted { ($0.time, $0.medication.name) < ($1.time, $1.medication.name) }
    }

    public static func status(of dose: ScheduledDose, in log: DoseLog, now: Date, grace: TimeInterval = grace) -> DoseStatus {
        if let record = log[dose.id] {
            return record.outcome == .taken ? .taken(at: record.recordedAt) : .skipped(at: record.recordedAt)
        }
        guard now >= dose.time else { return .upcoming }
        let overdue = now.timeIntervalSince(dose.time)
        return overdue < grace ? .due : .late(by: overdue)
    }

    /// The dose the parent's screen is about: the earliest one still waiting
    /// for an answer. `nil` when nothing is waiting.
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
        public var upcoming = 0

        public init() {}

        public var total: Int { taken + skipped + late + due + upcoming }
        /// Doses whose time has come: the denominator for "2 / 3 liều".
        public var soFar: Int { taken + skipped + late + due }
    }

    public static func summary(of doses: [ScheduledDose], in log: DoseLog, now: Date) -> DaySummary {
        doses.reduce(into: DaySummary()) { summary, dose in
            switch status(of: dose, in: log, now: now) {
            case .taken: summary.taken += 1
            case .skipped: summary.skipped += 1
            case .late: summary.late += 1
            case .due: summary.due += 1
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
            case .skipped, .late: settled += 1
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
