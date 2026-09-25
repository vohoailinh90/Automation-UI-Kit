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

    /// This time on the day containing `day`, in `calendar`'s time zone.
    public func date(onDayOf day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))
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
    public var id: UUID
    /// What the family calls it: "Thuốc huyết áp", not the chemical name.
    public var name: String
    /// "1 viên", "2 viên", "5 ml".
    public var dose: String
    /// "Sau ăn sáng", "Trước khi ngủ".
    public var instructions: String
    public var style: PillStyle
    /// When to take it each day; kept sorted and without duplicates.
    public private(set) var times: [TimeOfDay]

    public init(id: UUID = UUID(), name: String, dose: String, instructions: String = "", style: PillStyle, times: [TimeOfDay]) {
        self.id = id
        self.name = name
        self.dose = dose
        self.instructions = instructions
        self.style = style
        self.times = Array(Set(times)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, dose, instructions, style, times
    }

    /// Decoding goes through `init`, so stored times come back sorted and unique.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            dose: try container.decode(String.self, forKey: .dose),
            instructions: try container.decode(String.self, forKey: .instructions),
            style: try container.decode(PillStyle.self, forKey: .style),
            times: try container.decode([TimeOfDay].self, forKey: .times)
        )
    }
}
