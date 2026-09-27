import Foundation

/// The book as an Excel workbook (.xlsx), for `LedgerReportScreen`'s
/// spreadsheet export: one sheet listing a period's entries, oldest first,
/// with their date, time, note, money in and money out, then the totals and
/// the difference, which stay formulas, so the sheet can be added to.
///
/// A workbook rather than a CSV file: Excel opens a CSV with the list
/// separator of the computer's region, a semicolon where the decimal mark is
/// a comma, as in Vietnam, so a comma-separated file opens as one column; and
/// it reads a CSV without a byte order mark as the region's legacy code page,
/// which mangles Vietnamese. A workbook says what each cell is: dates are
/// dates, amounts are numbers, text is Unicode, in Excel, Numbers and Google
/// Sheets alike.
///
/// A plain book, not the bookkeeping forms the tax rules prescribe for a
/// household business: those must be checked against the rules in force.
public enum LedgerSpreadsheet {
    /// The workbook's bytes, for a file ending in ".xlsx".
    ///
    /// - Parameters:
    ///   - entries: the book, in any order; only those in `interval`, end
    ///     excluded, are listed.
    ///   - interval: the period, as `LedgerReportScreen` passes it.
    ///   - calendar: the book's calendar: dates and times are written as its
    ///     time zone's clock shows them.
    ///   - title: the sheet's first line, such as "Sổ thu chi quý 3/2026"
    ///     (`LedgerExport.title`).
    ///   - made: when the export is made, said under the title
    ///     (`LedgerExport.subtitle`).
    public static func xlsx(entries: [LedgerEntry], in interval: DateInterval, calendar: Calendar, title: String, made: Date) -> Data {
        var zip = StoredZip()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(packageRelationships.utf8))
        zip.add("xl/workbook.xml", Data(workbook.utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRelationships.utf8))
        zip.add("xl/styles.xml", Data(styles.utf8))
        zip.add("xl/worksheets/sheet1.xml", Data(sheet(entries: entries, in: interval, calendar: calendar, title: title, made: made).utf8))
        return zip.data
    }

    /// The sheet: the title, the period, the column headings, a row per
    /// entry, then the totals and the difference.
    static func sheet(entries: [LedgerEntry], in interval: DateInterval, calendar: Calendar, title: String, made: Date) -> String {
        let listed = LedgerExport.listing(entries, in: interval)
        var rows: [String] = []
        func row(_ cells: [String]) {
            rows.append("<row r=\"\(rows.count + 1)\">" + cells.joined() + "</row>")
        }
        row([text("A", 1, title, style: .bold)])
        row([text("A", 2, LedgerExport.subtitle(for: interval, calendar: calendar, made: made))])
        row([
            text("A", 3, "Ngày", style: .bold), text("B", 3, "Giờ", style: .bold), text("C", 3, "Diễn giải", style: .bold),
            text("D", 3, "Thu (đồng)", style: .bold), text("E", 3, "Chi (đồng)", style: .bold),
        ])
        for entry in listed {
            let at = rows.count + 1
            let serial = excelSerial(entry.date, calendar)
            let amount = number(entry.kind == .income ? "D" : "E", at, Double(entry.amount), style: .amount)
            row([
                number("A", at, serial.rounded(.down), style: .date),
                number("B", at, serial - serial.rounded(.down), style: .time),
                text("C", at, LedgerExport.note(of: entry)),
                amount,
            ])
        }
        let totals = LedgerMath.totals(of: listed)
        let sums = rows.count + 1
        // Formulas only over rows that exist: an empty period has none.
        let span = listed.isEmpty ? nil : (first: 4, last: rows.count)
        row([
            text("A", sums, "Cộng", style: .bold),
            number("D", sums, Double(totals.income), style: .boldAmount, formula: span.map { "SUM(D\($0.first):D\($0.last))" }),
            number("E", sums, Double(totals.expense), style: .boldAmount, formula: span.map { "SUM(E\($0.first):E\($0.last))" }),
        ])
        let net = rows.count + 1
        row([
            text("A", net, "Chênh lệch (thu − chi)", style: .bold),
            number("D", net, Double(totals.net), style: .boldAmount, formula: "D\(sums)-E\(sums)"),
        ])
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetViews><sheetView workbookViewId="0">\
        <pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>\
        <cols><col min="1" max="1" width="12" customWidth="1"/><col min="2" max="2" width="8" customWidth="1"/>\
        <col min="3" max="3" width="40" customWidth="1"/><col min="4" max="5" width="16" customWidth="1"/></cols>\
        <sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    /// The cell formats of `styles`, by their index there.
    enum Style: Int {
        case plain = 0, bold, date, time, amount, boldAmount
    }

    static func text(_ column: String, _ row: Int, _ value: String, style: Style = .plain) -> String {
        "<c r=\"\(column)\(row)\" t=\"inlineStr\" s=\"\(style.rawValue)\"><is><t xml:space=\"preserve\">\(escaped(value))</t></is></c>"
    }

    static func number(_ column: String, _ row: Int, _ value: Double, style: Style, formula: String? = nil) -> String {
        let written = value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        return "<c r=\"\(column)\(row)\" s=\"\(style.rawValue)\">" + (formula.map { "<f>\($0)</f>" } ?? "") + "<v>\(written)</v></c>"
    }

    /// `date` as Excel counts time: days since 30 December 1899, the time of
    /// day a fraction, on the clock of `calendar`'s time zone.
    static func excelSerial(_ date: Date, _ calendar: Calendar) -> Double {
        let local = date.timeIntervalSince1970 + Double(calendar.timeZone.secondsFromGMT(for: date))
        return local / 86_400 + 25_569
    }

    /// `text` as XML character data: markup escaped, and the characters XML
    /// 1.0 cannot hold (control characters but tab and line breaks) left out,
    /// cut to the 32,767 UTF-16 units a cell holds.
    static func escaped(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        var units = 0
        for scalar in text.unicodeScalars {
            let allowed = scalar == "\t" || scalar == "\n" || scalar == "\r"
                || (scalar.value >= 0x20 && scalar.value != 0xFFFE && scalar.value != 0xFFFF)
            guard allowed else { continue }
            units += scalar.utf16.count
            guard units <= 32_767 else { break }
            kept.append(scalar)
        }
        var out = ""
        for character in String(kept) {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    </Types>
    """

    private static let packageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
    <sheets><sheet name="Sổ thu chi" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    </Relationships>
    """

    /// Cell formats in `Style`'s order: plain, bold, date (dd/mm/yyyy), time
    /// (hh:mm), amount (#,##0, grouped as the reader's region groups) and a
    /// bold amount.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="hh:mm"/></numFmts>\
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="6">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="3" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}
