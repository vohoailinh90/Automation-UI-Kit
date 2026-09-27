import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func entry(_ kind: LedgerEntry.Kind, _ amount: Int64, _ note: String, at when: Date) -> LedgerEntry {
    LedgerEntry(kind: kind, amount: amount, note: note, date: when)
}

private let september = DateInterval(start: date(2026, 9, 1, 0), end: date(2026, 10, 1, 0))
private let made = date(2026, 9, 25, 9, 41)

/// The files of a stored ZIP, read back the way an unzipper reads them:
/// from the end record, through the central directory, to each local header.
private func unzip(_ data: Data) throws -> [String: Data] {
    let bytes = [UInt8](data)
    func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
    func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
    let end = bytes.count - 22
    try #require(u32(end) == 0x0605_4B50)
    let count = u16(end + 10)
    #expect(u16(end + 8) == count)
    var cursor = u32(end + 16)
    #expect(cursor + u32(end + 12) == end)
    var files: [String: Data] = [:]
    for _ in 0 ..< count {
        try #require(u32(cursor) == 0x0201_4B50)
        let method = u16(cursor + 10), crc = u32(cursor + 16), size = u32(cursor + 20)
        #expect(method == 0)
        #expect(u32(cursor + 24) == size)
        let nameLength = u16(cursor + 28), extra = u16(cursor + 30), comment = u16(cursor + 32)
        let local = u32(cursor + 42)
        let name = String(decoding: bytes[cursor + 46 ..< cursor + 46 + nameLength], as: UTF8.self)
        try #require(u32(local) == 0x0403_4B50)
        #expect(u32(local + 14) == crc)
        #expect(u16(local + 26) == nameLength)
        let start = local + 30 + nameLength + u16(local + 28)
        let body = Data(bytes[start ..< start + size])
        #expect(Int(CRC32.checksum(body)) == crc)
        files[name] = body
        cursor += 46 + nameLength + extra + comment
    }
    return files
}

private func sheet(_ entries: [LedgerEntry], in interval: DateInterval = september, title: String = "Sổ thu chi tháng 9/2026") throws -> String {
    let files = try unzip(LedgerSpreadsheet.xlsx(entries: entries, in: interval, calendar: vietnam, title: title, made: made))
    return String(decoding: try #require(files["xl/worksheets/sheet1.xml"]), as: UTF8.self)
}

@Suite("Ledger spreadsheet: the book as an .xlsx")
struct LedgerSpreadsheetTests {
    @Test("CRC-32 as ZIP computes it")
    func crc() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
        #expect(CRC32.checksum(Data([0])) == 0xD202_EF8D)
    }

    @Test("A stored ZIP holds its files as they are, and the same files make the same bytes")
    func zip() throws {
        var zip = StoredZip()
        zip.add("a.txt", Data("xin chào".utf8))
        zip.add("dir/empty", Data())
        let files = try unzip(zip.data)
        #expect(files == ["a.txt": Data("xin chào".utf8), "dir/empty": Data()])
        #expect(zip.data == zip.data)
        #expect(try unzip(StoredZip().data).isEmpty)
    }

    @Test("The workbook has the parts Excel needs, the sheet named for the book")
    func parts() throws {
        let files = try unzip(LedgerSpreadsheet.xlsx(entries: [], in: september, calendar: vietnam, title: "Sổ", made: made))
        #expect(Set(files.keys) == [
            "[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
            "xl/styles.xml", "xl/worksheets/sheet1.xml",
        ])
        let workbook = String(decoding: try #require(files["xl/workbook.xml"]), as: UTF8.self)
        #expect(workbook.contains("<sheet name=\"Sổ thu chi\" sheetId=\"1\" r:id=\"rId1\"/>"))
        let types = String(decoding: try #require(files["[Content_Types].xml"]), as: UTF8.self)
        #expect(types.contains("/xl/worksheets/sheet1.xml"))
        #expect(types.contains("/xl/styles.xml"))
    }

    @Test("Rows: the period's entries only, oldest first, each in its column; then the totals as formulas")
    func rows() throws {
        let xml = try sheet([
            entry(.expense, 120_000, "Tiền điện", at: date(2026, 9, 25, 9, 41)),
            entry(.income, 450_000, "Bán 3 thùng nước", at: date(2026, 9, 1, 0, 0)),
            entry(.income, 999, "Tháng trước", at: date(2026, 8, 31, 23, 59)),
            entry(.income, 5, "Tháng sau", at: date(2026, 10, 1, 0, 0)),
        ])
        #expect(xml.contains("<c r=\"A1\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">Sổ thu chi tháng 9/2026</t></is></c>"))
        #expect(xml.contains("<t xml:space=\"preserve\">Từ 01/09/2026 đến 30/09/2026 · Lập ngày 25/09/2026 lúc 09:41</t>"))
        for (cell, heading) in [("A3", "Ngày"), ("B3", "Giờ"), ("C3", "Diễn giải"), ("D3", "Thu (đồng)"), ("E3", "Chi (đồng)")] {
            #expect(xml.contains("<c r=\"\(cell)\" t=\"inlineStr\" s=\"1\"><is><t xml:space=\"preserve\">\(heading)</t></is></c>"))
        }
        // 1 September at midnight: day 46266, no time.
        #expect(xml.contains("<row r=\"4\"><c r=\"A4\" s=\"2\"><v>46266</v></c><c r=\"B4\" s=\"3\"><v>0</v></c>"))
        #expect(xml.contains("Bán 3 thùng nước</t></is></c><c r=\"D4\" s=\"4\"><v>450000</v></c></row>"))
        // 25 September at 09:41 in Vietnam: the time a fraction of the day.
        #expect(xml.contains("<c r=\"A5\" s=\"2\"><v>46290</v></c><c r=\"B5\" s=\"3\"><v>0.4034722222"))
        #expect(xml.contains("Tiền điện</t></is></c><c r=\"E5\" s=\"4\"><v>120000</v></c></row>"))
        #expect(!xml.contains("Tháng trước") && !xml.contains("Tháng sau"))
        #expect(xml.contains("<c r=\"D6\" s=\"5\"><f>SUM(D4:D5)</f><v>450000</v></c>"))
        #expect(xml.contains("<c r=\"E6\" s=\"5\"><f>SUM(E4:E5)</f><v>120000</v></c>"))
        #expect(xml.contains("<t xml:space=\"preserve\">Chênh lệch (thu − chi)</t></is></c><c r=\"D7\" s=\"5\"><f>D6-E6</f><v>330000</v></c></row>"))
        #expect(!xml.contains("<row r=\"8\""))
    }

    @Test("An evening entry stays on its day: the time is what is left of the day, below one")
    func evening() throws {
        let xml = try sheet([entry(.income, 1, "Bán buổi tối", at: date(2026, 9, 25, 21, 5))])
        // 21:05 is 1,265 minutes: 0.878472… of day 46290, not a day later.
        #expect(xml.contains("<c r=\"A4\" s=\"2\"><v>46290</v></c><c r=\"B4\" s=\"3\"><v>0.8784722222"))
    }

    @Test("A losing period's difference is negative; entries at one instant keep one order")
    func negative() throws {
        let when = date(2026, 9, 10, 8)
        let a = LedgerEntry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, kind: .expense, amount: 700_000, note: "a", date: when)
        let b = LedgerEntry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, kind: .income, amount: 200_000, note: "b", date: when)
        let xml = try sheet([b, a])
        #expect(try sheet([a, b]) == xml)
        #expect(xml.range(of: ">a</t>")!.lowerBound < xml.range(of: ">b</t>")!.lowerBound)
        #expect(xml.contains("<f>D6-E6</f><v>-500000</v>"))
    }

    @Test("An empty period: headings, zero totals, and no formula over rows that are not there")
    func empty() throws {
        let xml = try sheet([entry(.income, 5, "Tháng sau", at: date(2026, 10, 1, 0))])
        #expect(xml.contains("<c r=\"D4\" s=\"5\"><v>0</v></c><c r=\"E4\" s=\"5\"><v>0</v></c>"))
        #expect(!xml.contains("SUM("))
        #expect(xml.contains("<f>D4-E4</f><v>0</v>"))
    }

    @Test("An entry without a note is written as the book shows it: \"Khoản thu\", \"Khoản chi\"")
    func unnamed() throws {
        let xml = try sheet([entry(.income, 1, "", at: date(2026, 9, 2)), entry(.expense, 1, "", at: date(2026, 9, 3))])
        #expect(xml.contains("<c r=\"C4\" t=\"inlineStr\" s=\"0\"><is><t xml:space=\"preserve\">Khoản thu</t></is></c>"))
        #expect(xml.contains("<c r=\"C5\" t=\"inlineStr\" s=\"0\"><is><t xml:space=\"preserve\">Khoản chi</t></is></c>"))
    }

    @Test("Notes are XML text: markup escaped, characters XML cannot hold left out, spaces kept")
    func escaping() throws {
        let xml = try sheet([entry(.income, 1, "  <b>Tom & Jerry</b> \"x\"\u{7}\u{1B}\ttab\nline  ", at: date(2026, 9, 2))])
        #expect(xml.contains("<t xml:space=\"preserve\">  &lt;b&gt;Tom &amp; Jerry&lt;/b&gt; &quot;x&quot;\ttab\nline  </t>"))
        #expect(LedgerSpreadsheet.escaped("a\u{FFFE}b\u{FFFF}c\u{0}") == "abc")
        #expect(LedgerSpreadsheet.escaped("😀 Phở") == "😀 Phở")
        let long = LedgerSpreadsheet.escaped(String(repeating: "😀", count: 20_000))
        #expect(long.utf16.count <= 32_767)
        #expect(long.utf16.count > 32_760)
    }

    @Test("Excel's day count: days since 30 December 1899 on the book's clock")
    func serials() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(LedgerSpreadsheet.excelSerial(Date(timeIntervalSince1970: 0), utc) == 25_569)
        // Vietnam's clock, UTC+7 today (the zone's history holds other offsets).
        #expect(LedgerSpreadsheet.excelSerial(date(2026, 9, 25, 0, 0), vietnam) == 46_290)
        #expect(abs(LedgerSpreadsheet.excelSerial(date(2026, 9, 25, 9, 41), vietnam) - (46_290 + 581.0 / 1_440)) < 1e-9)
        #expect(abs(LedgerSpreadsheet.excelSerial(date(2026, 9, 25, 0, 0).addingTimeInterval(-1), vietnam) - (46_290 - 1.0 / 86_400)) < 1e-9)
    }
}
