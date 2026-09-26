import Foundation

/// The add-a-medicine form as data: what has been filled in, what is still
/// missing, and the `Medication` it makes. The rules live here, tested, not
/// in a view: names are trimmed, times stay sorted and unique, and a course
/// of days ends on a whole day in the parent's calendar.
public struct MedicationDraft: Hashable, Sendable {
    public enum Course: Hashable, Sendable {
        /// Every day with no end: "thuốc huyết áp".
        case ongoing
        /// A course of this many days, the day it is added counted as the
        /// first: "kháng sinh 7 ngày".
        case days(Int)
    }

    /// What still stops the medicine from being saved, in form order.
    public enum Problem: Hashable, Sendable, CaseIterable {
        case missingName
        case missingDose
        case noTimes
        case courseLength

        /// Said under the save button, so a disabled button is never a riddle.
        public var message: String {
            switch self {
            case .missingName: "Nhập tên thuốc"
            case .missingDose: "Nhập liều mỗi lần uống"
            case .noTimes: "Chọn ít nhất một giờ uống"
            case .courseLength: "Số ngày uống từ 1 đến \(MedicationDraft.longestCourse)"
            }
        }
    }

    /// A year: longer than that is "lâu dài".
    public static let longestCourse = 365

    public var name: String
    public var dose: String
    public var instructions: String
    public var style: PillStyle
    /// When to take it each day, sorted and without duplicates.
    public private(set) var times: [TimeOfDay]
    public var course: Course

    public init(
        name: String = "",
        dose: String = "1 viên",
        instructions: String = "",
        style: PillStyle = PillStyle(shape: .round, color: .white),
        times: [TimeOfDay] = [TimeOfDay(hour: 7)],
        course: Course = .ongoing
    ) {
        self.name = name
        self.dose = dose
        self.instructions = instructions
        self.style = style
        self.times = Array(Set(times)).sorted()
        self.course = course
    }

    /// One tap each, in the words on Vietnamese prescriptions.
    public static let doseSuggestions = ["1 viên", "2 viên", "½ viên", "5 ml"]
    public static let instructionSuggestions = ["Sau ăn", "Trước ăn", "Trong bữa ăn", "Trước khi ngủ"]
    /// The usual times of day, to add without turning a wheel.
    public static let timeSuggestions: [(label: String, time: TimeOfDay)] = [
        ("Sáng", TimeOfDay(hour: 7)),
        ("Trưa", TimeOfDay(hour: 12)),
        ("Chiều", TimeOfDay(hour: 17)),
        ("Tối", TimeOfDay(hour: 21)),
    ]

    /// Where the wheel starts for "Thêm giờ khác": the first usual time not
    /// taken yet, else an hour after the last one, else the first whole hour
    /// free from midnight; `nil` only once every whole hour is taken. Never
    /// one of `times`.
    public var suggestedNewTime: TimeOfDay? {
        if let usual = Self.timeSuggestions.map(\.time).first(where: { !times.contains($0) }) {
            return usual
        }
        if let last = times.last, last.hour < 23 {
            return TimeOfDay(hour: last.hour + 1, minute: last.minute)
        }
        return (0..<24).lazy.map { TimeOfDay(hour: $0) }.first { !times.contains($0) }
    }

    /// Adds a time. Returns `false`, changing nothing, if it is already there.
    @discardableResult
    public mutating func add(_ time: TimeOfDay) -> Bool {
        guard !times.contains(time) else { return false }
        times.append(time)
        times.sort()
        return true
    }

    public mutating func remove(_ time: TimeOfDay) {
        times.removeAll { $0 == time }
    }

    /// Moves `old` to `new`. Returns `false`, changing nothing, if `new` is
    /// already another of the times or `old` is not one of them: two rows
    /// must never become the same dose.
    @discardableResult
    public mutating func change(_ old: TimeOfDay, to new: TimeOfDay) -> Bool {
        guard let index = times.firstIndex(of: old) else { return false }
        guard old != new else { return true }
        guard !times.contains(new) else { return false }
        times[index] = new
        times.sort()
        return true
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDose: String { dose.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstructions: String { instructions.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var problems: [Problem] {
        var problems: [Problem] = []
        if trimmedName.isEmpty { problems.append(.missingName) }
        if trimmedDose.isEmpty { problems.append(.missingDose) }
        if times.isEmpty { problems.append(.noTimes) }
        if case let .days(count) = course, !(1...Self.longestCourse).contains(count) { problems.append(.courseLength) }
        return problems
    }

    public var isComplete: Bool { problems.isEmpty }

    /// The last moment a dose of a `days`-day course counts, the course
    /// starting at `start`: the end of its last day in `calendar` — the
    /// parent's — which may be 23 or 25 hours long around a clock change.
    /// `nil` for a length outside `1...longestCourse`.
    public static func courseEnd(days: Int, startingAt start: Date, calendar: Calendar) -> Date? {
        guard (1...longestCourse).contains(days),
              let dayAfter = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: start))
        else { return nil }
        // The last whole second of the last day: dose times are whole minutes.
        return dayAfter.addingTimeInterval(-1)
    }

    /// The medicine to save, or `nil` while `problems` is not empty. It starts
    /// at `now` — the moment it is added — so this morning's earlier doses are
    /// not shown as missed; a course ends as `courseEnd` says.
    public func medication(id: UUID = UUID(), startingAt now: Date, calendar: Calendar) -> Medication? {
        guard isComplete else { return nil }
        let endDate: Date?
        switch course {
        case .ongoing:
            endDate = nil
        case let .days(count):
            guard let end = Self.courseEnd(days: count, startingAt: now, calendar: calendar) else { return nil }
            endDate = end
        }
        return Medication(
            id: id,
            name: trimmedName,
            dose: trimmedDose,
            instructions: trimmedInstructions,
            style: style,
            times: times,
            startDate: now,
            endDate: endDate
        )
    }
}
