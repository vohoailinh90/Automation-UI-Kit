import Foundation

/// What a pill looks like, so a parent can recognise it without reading the
/// box — the idea behind Apple Health's shape and colour picker for
/// medications.
public struct PillStyle: Hashable, Sendable, Codable {
    public enum Shape: String, Hashable, Sendable, Codable, CaseIterable {
        case round
        case oval
        case oblong
        /// Two halves, like a gel capsule; uses `secondColor`.
        case capsule
    }

    /// A small fixed set, as on a pharmacy shelf: easier to pick than a
    /// colour wheel, and every colour stays distinguishable.
    public enum Color: String, Hashable, Sendable, Codable, CaseIterable {
        case white, cream, yellow, orange, pink, red, lightBlue, blue, green, brown

        public var rgb: RGB {
            switch self {
            case .white: RGB(0xF7F7F5)
            case .cream: RGB(0xF3E7C9)
            case .yellow: RGB(0xF6D34A)
            case .orange: RGB(0xF29B38)
            case .pink: RGB(0xF4A6C0)
            case .red: RGB(0xD9453B)
            case .lightBlue: RGB(0x9FCBF2)
            case .blue: RGB(0x3E7BD6)
            case .green: RGB(0x5BB36A)
            case .brown: RGB(0x8C5E3C)
            }
        }
    }

    public var shape: Shape
    public var color: Color
    /// The other half of a capsule; ignored for other shapes.
    public var secondColor: Color?

    public init(shape: Shape, color: Color, secondColor: Color? = nil) {
        self.shape = shape
        self.color = color
        self.secondColor = secondColor
    }
}

/// A time on the clock, independent of any day ("07:00").
public struct TimeOfDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int = 0) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "TimeOfDay \(hour):\(minute) is not a time")
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    /// "07:00" — 24-hour, as Vietnamese medicine labels write it.
    public var description: String {
        (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
    }

    /// This time on the day containing `day`, in `calendar`'s time zone —
    /// never on another day. A time that a daylight-saving jump skips moves
    /// to just after the jump (02:30 is 03:00 in New York that day), and is
    /// `nil` when the jump ends the day: in Nuuk, 23:00 does not exist on the
    /// night clocks go forward.
    public func date(onDayOf day: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let onThisDay = { (date: Date?) in date.flatMap { (start..<end).contains($0) ? $0 : nil } }
        if let date = onThisDay(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)) {
            return date
        }
        // Some Foundation versions look for the skipped time on the next day.
        var parts = calendar.dateComponents([.era, .year, .month, .day], from: start)
        parts.hour = hour
        parts.minute = minute
        return onThisDay(calendar.date(from: parts))
    }

    private enum CodingKeys: String, CodingKey {
        case hour, minute
    }

    /// Decoding validates like `init`: a stored 25:00 is corrupt, not a time.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        guard (0..<24).contains(hour), (0..<60).contains(minute) else {
            throw DecodingError.dataCorruptedError(
                forKey: .hour, in: container, debugDescription: "\(hour):\(minute) is not a time of day"
            )
        }
        self.init(hour: hour, minute: minute)
    }
}

public struct Medication: Identifiable, Hashable, Sendable, Codable {
    /// This version of the medicine. A dose is recorded against it.
    public var id: UUID
    /// The medicine across its versions. Changing when or how much it is
    /// taken does not rewrite this `Medication`: it ends, and a new one with
    /// its own `id` and the same `seriesID` takes over (`MedicationChanges`),
    /// so past days keep the times and doses they had. A dose waits for an
    /// answer until the series' next dose, whichever version that is.
    public var seriesID: UUID
    /// What the family calls it: "Thuốc huyết áp", not the chemical name.
    public var name: String
    /// "1 viên", "2 viên", "5 ml".
    public var dose: String
    /// "Sau ăn sáng", "Trước khi ngủ".
    public var instructions: String
    public var style: PillStyle
    /// When to take it each day; kept sorted and without duplicates.
    public private(set) var times: [TimeOfDay]
    /// The first moment a dose counts. Set it to when the medicine is added,
    /// so this morning's 07:00 is not shown as missed. `nil`: from always.
    public var startDate: Date?
    /// The last moment a dose counts, for a course that ends ("7 ngày").
    /// `nil`: no end.
    public var endDate: Date?
    /// When the medicine was stopped ("ngừng thuốc"), if it was. From then on
    /// there is no dose, and none is asked about: a dose still waiting for an
    /// answer stops waiting then, and counts as missed.
    public var stoppedAt: Date?

    /// `seriesID` is `id` unless this continues an earlier version.
    public init(
        id: UUID = UUID(), seriesID: UUID? = nil, name: String, dose: String, instructions: String = "", style: PillStyle,
        times: [TimeOfDay], startDate: Date? = nil, endDate: Date? = nil, stoppedAt: Date? = nil
    ) {
        self.id = id
        self.seriesID = seriesID ?? id
        self.name = name
        self.dose = dose
        self.instructions = instructions
        self.style = style
        self.times = Array(Set(times)).sorted()
        self.startDate = startDate
        self.endDate = endDate
        self.stoppedAt = stoppedAt
    }

    /// Whether a dose at `time` is part of the course: not before
    /// `startDate`, not after `endDate`, and before `stoppedAt`.
    public func isScheduled(at time: Date) -> Bool {
        (startDate.map { $0 <= time } ?? true) && (endDate.map { time <= $0 } ?? true) && (stoppedAt.map { time < $0 } ?? true)
    }

    /// Whether the medicine is in use at `now` or starts later: neither past
    /// its end nor stopped.
    public func isCurrent(at now: Date) -> Bool {
        (endDate.map { $0 >= now } ?? true) && (stoppedAt.map { $0 > now } ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, seriesID, name, dose, instructions, style, times, startDate, endDate, stoppedAt
    }

    /// Decoding goes through `init`, so stored times come back sorted and
    /// unique. Medicines stored before start and end dates existed have none,
    /// and those stored before versions existed are their own series.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            seriesID: try container.decodeIfPresent(UUID.self, forKey: .seriesID),
            name: try container.decode(String.self, forKey: .name),
            dose: try container.decode(String.self, forKey: .dose),
            instructions: try container.decode(String.self, forKey: .instructions),
            style: try container.decode(PillStyle.self, forKey: .style),
            times: try container.decode([TimeOfDay].self, forKey: .times),
            startDate: try container.decodeIfPresent(Date.self, forKey: .startDate),
            endDate: try container.decodeIfPresent(Date.self, forKey: .endDate),
            stoppedAt: try container.decodeIfPresent(Date.self, forKey: .stoppedAt)
        )
    }
}
