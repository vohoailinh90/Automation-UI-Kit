import Foundation
import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, calendar: Calendar = vietnam) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func entry(_ kind: LedgerEntry.Kind, _ amount: Int64, at when: Date) -> LedgerEntry {
    LedgerEntry(kind: kind, amount: amount, note: "", date: when)
}

@Suite("Ledger maths")
struct LedgerTests {
    @Test func totalsAndNet() {
        let entries = [
            entry(.income, 450_000, at: date(2026, 9, 25)),
            entry(.income, 50_000, at: date(2026, 9, 25)),
            entry(.expense, 700_000, at: date(2026, 9, 25)),
        ]
        let totals = LedgerMath.totals(of: entries)
        #expect(totals.income == 500_000)
        #expect(totals.expense == 700_000)
        #expect(totals.net == -200_000, "a losing day is negative, not clamped to zero")
        #expect(entries.map(\.signedAmount) == [450_000, 50_000, -700_000])
    }

    @Test("An interval includes its start and excludes its end")
    func intervalBounds() {
        let start = date(2026, 9, 25, 0, 0)
        let end = date(2026, 9, 26, 0, 0)
        let entries = [
            entry(.income, 1, at: start),
            entry(.income, 10, at: end.addingTimeInterval(-1)),
            entry(.income, 100, at: end),
            entry(.income, 1_000, at: start.addingTimeInterval(-1)),
        ]
        #expect(LedgerMath.totals(of: entries, in: DateInterval(start: start, end: end)).income == 11)
    }

    @Test("Days are bucketed in the given calendar's time zone, not UTC")
    func dailyTotalsUseCalendarTimeZone() throws {
        // 00:30 on 25/09 in Vietnam is still 24/09 in UTC.
        let justAfterMidnight = date(2026, 9, 25, 0, 30)
        let lateOn24th = date(2026, 9, 24, 23, 30)
        let days = LedgerMath.dailyTotals(
            of: [entry(.income, 100_000, at: justAfterMidnight), entry(.expense, 30_000, at: lateOn24th)],
            inMonthOf: justAfterMidnight, calendar: vietnam
        )
        #expect(days.count == 30, "September has 30 days, empty ones included")
        let day25 = try #require(days.first { vietnam.component(.day, from: $0.day) == 25 })
        let day24 = try #require(days.first { vietnam.component(.day, from: $0.day) == 24 })
        #expect(day25.totals == LedgerTotals(income: 100_000))
        #expect(day24.totals == LedgerTotals(expense: 30_000))
        #expect(days.filter { $0.totals != LedgerTotals() }.count == 2)
        #expect(days.allSatisfy { $0.day == vietnam.startOfDay(for: $0.day) })
    }

    @Test("Entries outside the month are ignored")
    func dailyTotalsIgnoreOtherMonths() {
        let days = LedgerMath.dailyTotals(
            of: [entry(.income, 5, at: date(2026, 10, 1, 0, 0)), entry(.income, 7, at: date(2026, 8, 31, 23, 59))],
            inMonthOf: date(2026, 9, 15), calendar: vietnam
        )
        #expect(LedgerMath.totals(of: []).income == 0)
        #expect(days.reduce(0) { $0 + $1.totals.income } == 0)
    }

    @Test(arguments: [
        ((2026, 9, 25), (2026, 7, 1), (2026, 10, 1)),
        ((2026, 1, 1), (2026, 1, 1), (2026, 4, 1)),
        ((2026, 3, 31), (2026, 1, 1), (2026, 4, 1)),
        ((2026, 4, 1), (2026, 4, 1), (2026, 7, 1)),
        ((2026, 12, 31), (2026, 10, 1), (2027, 1, 1)),
    ] as [((Int, Int, Int), (Int, Int, Int), (Int, Int, Int))])
    func quarters(day: (Int, Int, Int), start: (Int, Int, Int), end: (Int, Int, Int)) throws {
        let quarter = try #require(LedgerMath.quarter(containing: date(day.0, day.1, day.2, 23, 59), calendar: vietnam))
        #expect(quarter.start == date(start.0, start.1, start.2, 0, 0))
        #expect(quarter.end == date(end.0, end.1, end.2, 0, 0))
    }

    @Test("Quarter report: three months, empty ones kept, bucketed by month")
    func monthlyTotalsOverQuarter() throws {
        let q3 = try #require(LedgerMath.quarter(containing: date(2026, 9, 25), calendar: vietnam))
        let months = LedgerMath.monthlyTotals(
            of: [
                entry(.income, 100, at: date(2026, 7, 1, 0, 0)),
                entry(.expense, 40, at: date(2026, 9, 30, 23, 59)),
                entry(.income, 9_999, at: date(2026, 10, 1, 0, 0)),  // Q4: excluded
            ],
            in: q3, calendar: vietnam
        )
        #expect(months.map(\.month) == [date(2026, 7, 1, 0, 0), date(2026, 8, 1, 0, 0), date(2026, 9, 1, 0, 0)])
        #expect(months.map(\.totals) == [LedgerTotals(income: 100), LedgerTotals(), LedgerTotals(expense: 40)])
    }

    @Test("Monthly totals only count entries inside the interval, even within a listed month")
    func monthlyTotalsClipToInterval() {
        let interval = DateInterval(start: date(2026, 9, 15, 0, 0), end: date(2026, 10, 1, 0, 0))
        let months = LedgerMath.monthlyTotals(
            of: [entry(.income, 1, at: date(2026, 9, 14)), entry(.income, 2, at: date(2026, 9, 16))],
            in: interval, calendar: vietnam
        )
        #expect(months.count == 1)
        #expect(months.first?.totals == LedgerTotals(income: 2))
    }
}

@Suite("Ledger entry storage")
struct LedgerEntryCodingTests {
    @Test func roundTrip() throws {
        let original = LedgerEntry(kind: .expense, amount: 120_000, note: "Tiền điện", date: date(2026, 9, 25))
        let decoded = try JSONDecoder().decode(LedgerEntry.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test(
        "A stored amount that is zero, negative or over the keypad's maximum is corrupt",
        arguments: [0, -5, AmountInput.maximum + 1, .max] as [Int64]
    )
    func rejectsNonPositiveAmounts(amount: Int64) throws {
        let json = """
        {"id":"8D2B6A4E-1C1F-4A7B-9E4E-2F7B1C3D4E5F","kind":"income","amount":\(amount),"note":"","date":0}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LedgerEntry.self, from: Data(json.utf8))
        }
    }

    @Test("The largest amount decodes, and a book of them still sums")
    func largestAmountDecodes() throws {
        let json = """
        {"id":"8D2B6A4E-1C1F-4A7B-9E4E-2F7B1C3D4E5F","kind":"income","amount":\(AmountInput.maximum),"note":"","date":0}
        """
        let entry = try JSONDecoder().decode(LedgerEntry.self, from: Data(json.utf8))
        #expect(entry.amount == AmountInput.maximum)
        #expect(LedgerMath.totals(of: Array(repeating: entry, count: 1_000)).income == AmountInput.maximum * 1_000)
    }
}

@Suite("Sample book")
struct LedgerSamplesTests {
    @Test("Same now, same entries: screenshots are comparable run to run")
    func deterministic() {
        #expect(LedgerSamples.entries() == LedgerSamples.entries())
    }

    @Test("Plausible: nothing in the future, newest first, sales today")
    func plausible() {
        let now = LedgerSamples.referenceNow
        let entries = LedgerSamples.entries()
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.date <= now && $0.amount > 0 })
        #expect(entries.map(\.date) == entries.map(\.date).sorted(by: >))
        let today = DateInterval(start: vietnam.startOfDay(for: now), end: now.addingTimeInterval(1))
        #expect(LedgerMath.totals(of: entries, in: today).income > 0)
        let oldest = entries.map(\.date).min()!
        #expect(oldest >= vietnam.date(byAdding: .day, value: -29, to: vietnam.startOfDay(for: now))!)
    }

    @Test("Reference now is 09:41 on 25/09/2026 in Vietnam")
    func referenceNow() {
        let parts = vietnam.dateComponents([.year, .month, .day, .hour, .minute], from: LedgerSamples.referenceNow)
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2026, 9, 25, 9, 41])
    }
}
