#if os(iOS)
import CoreGraphics
import IdeaLabCore
import SwiftUI

/// The book as a printed report: a PDF of A4 pages, for
/// `LedgerReportScreen`'s PDF export (`LedgerExportFile` writes it to a file
/// to share). The first page opens with the title, the days covered and the
/// period's totals; every page lists entries oldest first, each with its
/// date, time, note and amount under "Thu" or "Chi", and says which page of
/// how many it is; the list ends with the column totals. Text stays text, so
/// the report prints sharp and can be searched and copied.
///
/// SwiftUI draws it (`ImageRenderer`) in fixed sizes and colours, whatever
/// the phone's text size, appearance and theme: paper is white. A note too
/// long for its row is cut short with "…"; the spreadsheet
/// (`LedgerSpreadsheet`) keeps every note whole.
public enum LedgerReportPDF {
    /// A4, 210 × 297 mm, in points.
    public static let pageSize = CGSize(width: 595.28, height: 841.89)
    /// Rows of the list on the first page, under the title and totals, and
    /// on each page after. The totals row counts as one.
    static let firstPageRows = 34
    static let otherPageRows = 40

    /// The report's bytes, for a file ending in ".pdf". It takes what
    /// `LedgerSpreadsheet.xlsx` takes, so the two exports of a period agree.
    ///
    /// - Throws: `CocoaError(.fileWriteUnknown)` if Core Graphics cannot
    ///   make a PDF.
    @MainActor
    public static func data(entries: [LedgerEntry], in interval: DateInterval, calendar: Calendar, title: String, made: Date) throws -> Data {
        let listed = LedgerExport.listing(entries, in: interval)
        let report = LedgerReportPage.Report(
            title: title,
            subtitle: LedgerExport.subtitle(for: interval, calendar: calendar, made: made),
            totals: LedgerMath.totals(of: listed),
            lines: listed.map { LedgerReportPage.Line($0, calendar) }
        )
        // The totals close the list, as its last row.
        let pages = LedgerExport.pages(rows: listed.count + 1, first: firstPageRows, others: otherPageRows)
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: title]
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { throw CocoaError(.fileWriteUnknown) }
        for (index, rows) in pages.enumerated() {
            let renderer = ImageRenderer(content: LedgerReportPage(report: report, rows: rows, number: index + 1, count: pages.count))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return output as Data
    }
}

/// One A4 page of `LedgerReportPDF`: the heading (on the first page the
/// title, the days covered and the totals; after it the title alone), the
/// column headings, rows of the list, and a footer with the page number.
struct LedgerReportPage: View {
    /// What every page of one report shares.
    struct Report {
        let title: String
        let subtitle: String
        let totals: LedgerTotals
        let lines: [Line]
    }

    /// An entry as the list writes it.
    struct Line {
        let day: String
        let time: String
        let note: String
        let income: Int64?
        let expense: Int64?

        init(_ entry: LedgerEntry, _ calendar: Calendar) {
            day = LedgerExport.day(entry.date, calendar)
            time = LedgerExport.time(entry.date, calendar)
            // A row holds one line: line breaks become spaces.
            note = LedgerExport.note(of: entry).split(whereSeparator: \.isNewline).joined(separator: " ")
            income = entry.kind == .income ? entry.amount : nil
            expense = entry.kind == .expense ? entry.amount : nil
        }
    }

    let report: Report
    /// This page's rows, by their place in the list: `report.lines`, then
    /// the totals.
    let rows: Range<Int>
    let number: Int
    let count: Int

    private static let rowHeight: CGFloat = 16
    private static let secondaryInk = Color(white: 0.36)
    private static let rule = Color(white: 0.72)
    private static let stripe = Color(white: 0.955)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if number == 1 {
                opening
            } else {
                runningHead
            }
            columns("Ngày", "Giờ", "Diễn giải", "Thu (đồng)", "Chi (đồng)")
                .font(.system(size: 8.5, weight: .semibold))
                .frame(height: 20)
                .overlay(alignment: .bottom) { Color.black.frame(height: 0.75) }
            if report.lines.isEmpty {
                Text(verbatim: "Không có khoản thu chi nào trong kỳ này.")
                    .font(.system(size: 9.5).italic())
                    .foregroundStyle(Self.secondaryInk)
                    .padding(.horizontal, 4)
                    .frame(height: Self.rowHeight + 8)
            }
            ForEach(rows, id: \.self) { index in
                if index < report.lines.count {
                    line(report.lines[index], striped: index % 2 == 1)
                } else {
                    totalsRow
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 40)
        .frame(width: LedgerReportPDF.pageSize.width, height: LedgerReportPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    /// The first page's heading: the title, the days covered and when the
    /// report was made, then the period's totals.
    private var opening: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: report.title)
                .font(.system(size: 17, weight: .bold))
                .minimumScaleFactor(0.6)
            Text(verbatim: report.subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(Self.secondaryInk)
                .padding(.top, 4)
            HStack(alignment: .top, spacing: 28) {
                figure("Tổng thu", report.totals.income)
                figure("Tổng chi", report.totals.expense)
                figure("Chênh lệch (thu − chi)", report.totals.net)
            }
            .padding(.top, 14)
        }
        .lineLimit(1)
        .padding(.bottom, 18)
    }

    /// "Tổng thu" over "12.345.000 đồng": the unit written out, as on paper.
    private func figure(_ title: String, _ amount: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.system(size: 8.5))
                .foregroundStyle(Self.secondaryInk)
            Text(verbatim: VND.string(amount, style: .spoken))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
    }

    /// The title again, above the list, on every page after the first.
    private var runningHead: some View {
        Text(verbatim: report.title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Self.secondaryInk)
            .lineLimit(1)
            .padding(.bottom, 12)
    }

    private func line(_ line: Line, striped: Bool) -> some View {
        columns(line.day, line.time, line.note, line.income.map(Self.amount) ?? "", line.expense.map(Self.amount) ?? "")
            .font(.system(size: 9.5))
            .monospacedDigit()
            .frame(height: Self.rowHeight)
            .background(striped ? Self.stripe : Color.clear)
    }

    /// "Cộng": what the money-in and money-out columns add up to.
    private var totalsRow: some View {
        columns("Cộng", "", "", Self.amount(report.totals.income), Self.amount(report.totals.expense))
            .font(.system(size: 9.5, weight: .bold))
            .monospacedDigit()
            .frame(height: Self.rowHeight + 4)
            .overlay(alignment: .top) { Color.black.frame(height: 0.75) }
    }

    /// A row of the five columns. A note cut short ends in "…"; an amount
    /// too wide for its column shrinks rather than lose digits.
    private func columns(_ day: String, _ time: String, _ note: String, _ income: String, _ expense: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: day)
                .frame(width: 58, alignment: .leading)
            Text(verbatim: time)
                .frame(width: 30, alignment: .leading)
            Text(verbatim: note)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: income)
                .minimumScaleFactor(0.6)
                .frame(width: 82, alignment: .trailing)
            Text(verbatim: expense)
                .minimumScaleFactor(0.6)
                .frame(width: 82, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "Sổ ghi chép để tham khảo khi kê khai. Ứng dụng không tư vấn thuế.")
            Spacer(minLength: 12)
            Text(verbatim: "Trang \(number)/\(count)")
        }
        .font(.system(size: 7.5))
        .foregroundStyle(Self.secondaryInk)
        .lineLimit(1)
        .padding(.top, 6)
        .overlay(alignment: .top) { Self.rule.frame(height: 0.5) }
    }

    /// "450.000": the column heading says the unit.
    private static func amount(_ amount: Int64) -> String {
        VND.string(amount, style: .plain)
    }
}
#endif
