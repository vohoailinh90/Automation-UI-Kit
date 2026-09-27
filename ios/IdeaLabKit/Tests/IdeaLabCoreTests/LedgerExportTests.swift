import Foundation
import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Ledger export: what an export lists and what it is called")
struct LedgerExportTests {
    @Test("Listing: the period's entries, end excluded, oldest first, ties by id")
    func listing() {
        let tie = date(2026, 9, 10, 8)
        let b = LedgerEntry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, kind: .income, amount: 2, note: "b", date: tie)
        let a = LedgerEntry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, kind: .income, amount: 1, note: "a", date: tie)
        let first = LedgerEntry(kind: .expense, amount: 3, note: "first", date: date(2026, 9, 1))
        let before = LedgerEntry(kind: .expense, amount: 4, note: "before", date: date(2026, 8, 31, 23, 59))
        let after = LedgerEntry(kind: .expense, amount: 5, note: "after", date: date(2026, 10, 1))
        let september = DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 1))
        #expect(LedgerExport.listing([after, b, before, a, first], in: september).map(\.note) == ["first", "a", "b"])
    }

    @Test("Titles and file names: a month, a quarter, or the days between")
    func names() {
        let september = vietnam.dateInterval(of: .month, for: date(2026, 9, 25))!
        #expect(LedgerExport.title(for: september, calendar: vietnam) == "Sổ thu chi tháng 9/2026")
        #expect(LedgerExport.fileName(for: september, calendar: vietnam) == "So-thu-chi-thang-9-2026")
        let q3 = LedgerMath.quarter(containing: date(2026, 9, 25), calendar: vietnam)!
        #expect(LedgerExport.title(for: q3, calendar: vietnam) == "Sổ thu chi quý 3/2026")
        #expect(LedgerExport.fileName(for: q3, calendar: vietnam) == "So-thu-chi-quy-3-2026")
        let q1 = LedgerMath.quarter(containing: date(2027, 2, 1), calendar: vietnam)!
        #expect(LedgerExport.title(for: q1, calendar: vietnam) == "Sổ thu chi quý 1/2027")
        let half = DateInterval(start: date(2026, 9, 1), end: date(2026, 9, 16))
        #expect(LedgerExport.title(for: half, calendar: vietnam) == "Sổ thu chi 01/09/2026 – 15/09/2026")
        #expect(LedgerExport.fileName(for: half, calendar: vietnam) == "So-thu-chi-01-09-2026-den-15-09-2026")
        // A month that starts mid-month is days, not a month.
        let shifted = DateInterval(start: date(2026, 9, 2), end: date(2026, 10, 2))
        #expect(LedgerExport.title(for: shifted, calendar: vietnam) == "Sổ thu chi 02/09/2026 – 01/10/2026")
        let instant = DateInterval(start: date(2026, 9, 2), duration: 0)
        #expect(LedgerExport.title(for: instant, calendar: vietnam) == "Sổ thu chi 02/09/2026 – 02/09/2026")
    }

    @Test("The line under the title: the days covered, and when the export was made")
    func subtitle() {
        let september = DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 1))
        #expect(LedgerExport.subtitle(for: september, calendar: vietnam, made: date(2026, 9, 25, 9, 41))
            == "Từ 01/09/2026 đến 30/09/2026 · Lập ngày 25/09/2026 lúc 09:41")
        #expect(LedgerExport.subtitle(for: september, calendar: vietnam, made: date(2026, 10, 2, 21, 5))
            == "Từ 01/09/2026 đến 30/09/2026 · Lập ngày 02/10/2026 lúc 21:05")
    }

    @Test("Notes: as written, or what the book shows for an entry without one")
    func notes() {
        let when = date(2026, 9, 2)
        #expect(LedgerExport.note(of: LedgerEntry(kind: .income, amount: 1, note: "Bán hàng", date: when)) == "Bán hàng")
        #expect(LedgerExport.note(of: LedgerEntry(kind: .income, amount: 1, note: "", date: when)) == "Khoản thu")
        #expect(LedgerExport.note(of: LedgerEntry(kind: .expense, amount: 1, note: "", date: when)) == "Khoản chi")
    }

    @Test("Days and times on the book's clock, whatever the calendar's own era")
    func dayAndTime() {
        #expect(LedgerExport.day(date(2026, 9, 1), vietnam) == "01/09/2026")
        #expect(LedgerExport.time(date(2026, 9, 25, 9, 41), vietnam) == "09:41")
        #expect(LedgerExport.time(date(2026, 9, 25, 21, 5), vietnam) == "21:05")
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = vietnam.timeZone
        #expect(LedgerExport.day(date(2026, 9, 1), buddhist) == "01/09/2026")
    }

    @Test("Pages: the first holds fewer rows; no rows still make a page", arguments: [
        (0, [0 ..< 0]), (1, [0 ..< 1]), (28, [0 ..< 28]), (29, [0 ..< 28, 28 ..< 29]),
        (66, [0 ..< 28, 28 ..< 66]), (67, [0 ..< 28, 28 ..< 66, 66 ..< 67]), (-3, [0 ..< 0]),
    ] as [(Int, [Range<Int>])])
    func pages(rows: Int, expected: [Range<Int>]) {
        #expect(LedgerExport.pages(rows: rows, first: 28, others: 38) == expected)
    }

    @Test("Pages never loop on nonsense sizes")
    func pageSizes() {
        #expect(LedgerExport.pages(rows: 3, first: 0, others: 0) == [0 ..< 1, 1 ..< 2, 2 ..< 3])
    }
}
