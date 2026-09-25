import Foundation

/// Deterministic sample book for previews, the demo app and screenshots: the
/// same `now` always gives the same entries, so screenshots are comparable run
/// to run. Not for shipping — a real app starts empty.
public enum LedgerSamples {
    /// Vietnam time, where the target users are, regardless of where CI runs.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? TimeZone(secondsFromGMT: 7 * 3_600)!
        calendar.locale = Locale(identifier: "vi_VN")
        calendar.firstWeekday = 2  // Monday
        return calendar
    }

    /// 09:41 on 25/09/2026 in Vietnam: the fixed "now" of every screenshot.
    public static let referenceNow: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 25
        components.hour = 9
        components.minute = 41
        return calendar.date(from: components)!
    }()

    static let incomeNotes = ["Bán hàng", "Bán 3 thùng nước", "Bán lẻ buổi sáng", "Khách quen trả nợ", "Bán 2 két bia"]
    static let expenseNotes = ["Nhập hàng", "Tiền điện", "Tiền ship", "Mua túi nilon", "Tiền nước đá"]

    /// Entries for the `days` days up to and including `now`, newest first.
    /// Every day has sales; expenses fall on some days only, like a real small
    /// shop. Today stops at `now`, so nothing is in the future.
    public static func entries(endingAt now: Date = referenceNow, days: Int = 30, calendar: Calendar = calendar) -> [LedgerEntry] {
        var generator = SplitMix64(seed: 2026_09_25)
        var entries: [LedgerEntry] = []
        let today = calendar.startOfDay(for: now)

        func add(_ kind: LedgerEntry.Kind, _ amount: Int64, _ note: String, on day: Date, atMinute minute: Int) {
            let id = UUID(uuid: uuidBytes(generator.next()))
            guard let date = calendar.date(byAdding: .minute, value: minute, to: day), date <= now else { return }
            entries.append(LedgerEntry(id: id, kind: kind, amount: amount, note: note, date: date))
        }

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let sales = 2 + Int(generator.next() % 4)
            for index in 0..<sales {
                let minute = 7 * 60 + index * 150 + Int(generator.next() % 90)
                let amount = Int64(80 + generator.next() % 420) * 1_000
                let note = incomeNotes[Int(generator.next() % UInt64(incomeNotes.count))]
                add(.income, amount, note, on: day, atMinute: minute)
            }
            if generator.next() % 3 == 0 {
                let minute = 8 * 60 + Int(generator.next() % 600)
                let amount = Int64(150 + generator.next() % 1_350) * 1_000
                let note = expenseNotes[Int(generator.next() % UInt64(expenseNotes.count))]
                add(.expense, amount, note, on: day, atMinute: minute)
            }
        }
        return entries.sorted { $0.date > $1.date }
    }

    private static func uuidBytes(_ value: UInt64) -> uuid_t {
        let b = withUnsafeBytes(of: value.bigEndian, Array.init)
        return (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], 0, 0, 0, 0, 0, 0, 0, 0)
    }
}

/// Small, fast, deterministic PRNG (SplitMix64, public domain). The system
/// generator is seeded randomly, which would make samples differ per run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
