import Foundation

/// One line in the income/expense book.
public struct LedgerEntry: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
        /// Thu — money in.
        case income
        /// Chi — money out.
        case expense

        /// Lets a kind drive `.sheet(item:)` directly: tap "Thu", present the income sheet.
        public var id: String { rawValue }
    }

    public var id: UUID
    public var kind: Kind
    /// Whole đồng, in `1...AmountInput.maximum`: the direction lives in
    /// `kind`, and the cap keeps any realistic book's sums far from overflow.
    /// Change it with `setAmount(_:)`, which keeps it in that range.
    public private(set) var amount: Int64
    public var note: String
    public var date: Date

    public init(id: UUID = UUID(), kind: Kind, amount: Int64, note: String, date: Date) {
        precondition(amount > 0, "LedgerEntry.amount must be positive; the sign lives in `kind`")
        precondition(amount <= AmountInput.maximum, "LedgerEntry.amount must not exceed AmountInput.maximum")
        self.id = id
        self.kind = kind
        self.amount = amount
        self.note = note
        self.date = date
    }

    /// Edits the amount if `newValue` is in `1...AmountInput.maximum`.
    /// Returns `false` and keeps the old amount otherwise, so an edited entry
    /// is as valid as a new or decoded one.
    @discardableResult
    public mutating func setAmount(_ newValue: Int64) -> Bool {
        guard (1...AmountInput.maximum).contains(newValue) else { return false }
        amount = newValue
        return true
    }

    /// +amount for income, −amount for expense.
    public var signedAmount: Int64 { kind == .income ? amount : -amount }

    /// What to say aloud once the entry is saved, as a shop's payment
    /// speaker does: "Đã ghi thu bốn trăm năm mươi nghìn đồng". The amount
    /// is in words (`VND.Style.words`), so a voice says it right whatever it
    /// would make of digits.
    public var readback: String {
        "Đã ghi \(kind == .income ? "thu" : "chi") \(VND.string(amount, style: .words))"
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, amount, note, date
    }

    /// Decoding goes through the same rule as `init`: a stored entry with a
    /// zero or negative amount is corrupt, not a refund; one above
    /// `AmountInput.maximum` is corrupt too, and would make sums trap.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let amount = try container.decode(Int64.self, forKey: .amount)
        guard (1...AmountInput.maximum).contains(amount) else {
            throw DecodingError.dataCorruptedError(
                forKey: .amount, in: container,
                debugDescription: "LedgerEntry.amount must be in 1...\(AmountInput.maximum), got \(amount)"
            )
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(Kind.self, forKey: .kind),
            amount: amount,
            note: try container.decode(String.self, forKey: .note),
            date: try container.decode(Date.self, forKey: .date)
        )
    }
}

public struct LedgerTotals: Hashable, Sendable {
    public var income: Int64
    public var expense: Int64

    public init(income: Int64 = 0, expense: Int64 = 0) {
        self.income = income
        self.expense = expense
    }

    /// Lãi (or lỗ when negative).
    public var net: Int64 { income - expense }

    public mutating func add(_ entry: LedgerEntry) {
        switch entry.kind {
        case .income: income += entry.amount
        case .expense: expense += entry.amount
        }
    }

    /// Combines two periods, e.g. the days of a month into the month.
    public static func + (lhs: LedgerTotals, rhs: LedgerTotals) -> LedgerTotals {
        LedgerTotals(income: lhs.income + rhs.income, expense: lhs.expense + rhs.expense)
    }
}

/// Totals for one calendar day, e.g. one bar in the month chart.
public struct DayTotals: Hashable, Sendable, Identifiable {
    /// Start of the day in the calendar used to bucket it.
    public var day: Date
    public var totals: LedgerTotals

    public var id: Date { day }

    public init(day: Date, totals: LedgerTotals) {
        self.day = day
        self.totals = totals
    }
}

/// Totals for one calendar month, e.g. one bar in the quarter chart.
public struct MonthTotals: Hashable, Sendable, Identifiable {
    /// First instant of the month.
    public var month: Date
    public var totals: LedgerTotals

    public var id: Date { month }

    public init(month: Date, totals: LedgerTotals) {
        self.month = month
        self.totals = totals
    }
}

public enum LedgerMath {
    /// The calendar quarter containing `date` — Q3 is 1/7 to 1/10, end
    /// excluded. Household businesses declare tax by quarter, so the report
    /// needs this boundary exactly. Built from months rather than
    /// `dateInterval(of: .quarter)`, which Foundation has answered wrongly on
    /// some OS versions.
    public static func quarter(containing date: Date, calendar: Calendar) -> DateInterval? {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        var start = DateComponents()
        start.year = year
        start.month = (month - 1) / 3 * 3 + 1
        start.day = 1
        guard let first = calendar.date(from: start),
              let end = calendar.date(byAdding: .month, value: 3, to: first) else { return nil }
        return DateInterval(start: first, end: end)
    }

    /// One `MonthTotals` for every month that overlaps `interval` (end
    /// excluded), including empty months. Only entries inside `interval` count.
    public static func monthlyTotals<S: Sequence>(
        of entries: S, in interval: DateInterval, calendar: Calendar
    ) -> [MonthTotals] where S.Element == LedgerEntry {
        var byMonth: [Date: LedgerTotals] = [:]
        for entry in entries where interval.start <= entry.date && entry.date < interval.end {
            guard let month = calendar.dateInterval(of: .month, for: entry.date) else { continue }
            byMonth[month.start, default: LedgerTotals()].add(entry)
        }
        var months: [MonthTotals] = []
        var cursor = interval.start
        while cursor < interval.end {
            guard let month = calendar.dateInterval(of: .month, for: cursor), month.end > cursor else { break }
            months.append(MonthTotals(month: month.start, totals: byMonth[month.start] ?? LedgerTotals()))
            cursor = month.end
        }
        return months
    }

    public static func totals<S: Sequence>(of entries: S) -> LedgerTotals where S.Element == LedgerEntry {
        entries.reduce(into: LedgerTotals()) { $0.add($1) }
    }

    /// Totals of the entries whose date falls in `interval`, end excluded — so
    /// consecutive days (or months) never count an entry twice.
    public static func totals<S: Sequence>(of entries: S, in interval: DateInterval) -> LedgerTotals where S.Element == LedgerEntry {
        totals(of: entries.lazy.filter { interval.start <= $0.date && $0.date < interval.end })
    }

    /// One `DayTotals` for every day of the month containing `date`, including
    /// days with no entries, so a chart shows gaps as gaps instead of skipping them.
    public static func dailyTotals<S: Sequence>(
        of entries: S, inMonthOf date: Date, calendar: Calendar
    ) -> [DayTotals] where S.Element == LedgerEntry {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        var byDay: [Date: LedgerTotals] = [:]
        for entry in entries where month.start <= entry.date && entry.date < month.end {
            byDay[calendar.startOfDay(for: entry.date), default: LedgerTotals()].add(entry)
        }
        var days: [DayTotals] = []
        var day = calendar.startOfDay(for: month.start)
        while day < month.end {
            days.append(DayTotals(day: day, totals: byDay[day] ?? LedgerTotals()))
            // Re-anchor on startOfDay: where a DST change makes a day start at
            // 01:00, "+1 day" would otherwise drift off the bucket keys.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day),
                  calendar.startOfDay(for: next) > day else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }
}
