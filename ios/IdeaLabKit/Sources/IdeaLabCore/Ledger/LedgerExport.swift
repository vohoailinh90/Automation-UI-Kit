import Foundation

/// What an export of the book lists, and what it is called, whatever its
/// format: `LedgerSpreadsheet` and the PDF report share it, so the two
/// always agree.
public enum LedgerExport {
    /// The entries of `interval`, end excluded, oldest first; entries of one
    /// instant by id, so an export lists them the same way every time.
    public static func listing(_ entries: [LedgerEntry], in interval: DateInterval) -> [LedgerEntry] {
        entries
            .filter { interval.start <= $0.date && $0.date < interval.end }
            .sorted { a, b in a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString }
    }

    /// "Sổ thu chi tháng 9/2026" for a calendar month, "Sổ thu chi quý
    /// 3/2026" for a quarter, else "Sổ thu chi 01/09/2026 – 15/09/2026".
    public static func title(for interval: DateInterval, calendar: Calendar) -> String {
        switch Period(interval, calendar) {
        case let .month(month, year): "Sổ thu chi tháng \(month)/\(year)"
        case let .quarter(quarter, year): "Sổ thu chi quý \(quarter)/\(year)"
        case .days: "Sổ thu chi \(day(interval.start, calendar)) – \(day(lastDay(of: interval), calendar))"
        }
    }

    /// The title as a file name any system takes, without accents or
    /// spaces: "So-thu-chi-thang-9-2026", "So-thu-chi-quy-3-2026",
    /// "So-thu-chi-01-09-2026-den-15-09-2026". Without an extension.
    public static func fileName(for interval: DateInterval, calendar: Calendar) -> String {
        switch Period(interval, calendar) {
        case let .month(month, year): "So-thu-chi-thang-\(month)-\(year)"
        case let .quarter(quarter, year): "So-thu-chi-quy-\(quarter)-\(year)"
        case .days:
            "So-thu-chi-" + day(interval.start, calendar).replacingOccurrences(of: "/", with: "-")
                + "-den-" + day(lastDay(of: interval), calendar).replacingOccurrences(of: "/", with: "-")
        }
    }

    /// "Từ 01/09/2026 đến 30/09/2026 · Lập ngày 25/09/2026 lúc 09:41": the
    /// line under the title. When it was made says whether a period still
    /// running, such as this month, was cut short.
    public static func subtitle(for interval: DateInterval, calendar: Calendar, made: Date) -> String {
        "Từ \(day(interval.start, calendar)) đến \(day(lastDay(of: interval), calendar))"
            + " · Lập ngày \(day(made, calendar)) lúc \(time(made, calendar))"
    }

    /// The entry's note, or "Khoản thu" / "Khoản chi" when it has none, as
    /// the book's own rows show it (`LedgerRow`).
    public static func note(of entry: LedgerEntry) -> String {
        entry.note.isEmpty ? (entry.kind == .income ? "Khoản thu" : "Khoản chi") : entry.note
    }

    /// The rows of each printed page: `first` on the first, which also holds
    /// the title and totals, and `others` on each after. No rows still make
    /// one page, to say so.
    public static func pages(rows: Int, first: Int, others: Int) -> [Range<Int>] {
        let first = max(first, 1), others = max(others, 1)
        var pages = [0 ..< min(max(rows, 0), first)]
        var start = pages[0].upperBound
        while start < rows {
            pages.append(start ..< min(start + others, rows))
            start += others
        }
        return pages
    }

    /// "01/09/2026": the day of `date` on `calendar`'s clock, written the
    /// Vietnamese way, on the Gregorian calendar whatever `calendar` is.
    public static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = gregorian(calendar).dateComponents([.year, .month, .day], from: date)
        return "\(twoDigits(parts.day))/\(twoDigits(parts.month))/\(parts.year ?? 0)"
    }

    /// "09:41": the time of `date` on `calendar`'s clock, 24-hour.
    public static func time(_ date: Date, _ calendar: Calendar) -> String {
        let parts = gregorian(calendar).dateComponents([.hour, .minute], from: date)
        return "\(twoDigits(parts.hour)):\(twoDigits(parts.minute))"
    }

    /// The last day `interval` covers: its end is excluded.
    private static func lastDay(of interval: DateInterval) -> Date {
        interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
    }

    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    private static func twoDigits(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : String(value)
    }

    /// What `interval` is on `calendar`: a whole calendar month, a whole
    /// quarter, or any other run of days.
    private enum Period {
        case month(Int, Int)
        case quarter(Int, Int)
        case days

        init(_ interval: DateInterval, _ calendar: Calendar) {
            let parts = LedgerExport.gregorian(calendar).dateComponents([.year, .month], from: interval.start)
            guard let month = parts.month, let year = parts.year else {
                self = .days
                return
            }
            if calendar.dateInterval(of: .month, for: interval.start) == interval {
                self = .month(month, year)
            } else if LedgerMath.quarter(containing: interval.start, calendar: calendar) == interval {
                self = .quarter((month - 1) / 3 + 1, year)
            } else {
                self = .days
            }
        }
    }
}
