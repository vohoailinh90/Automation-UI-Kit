import IdeaLabCore
import Testing

private let nbsp = "\u{00A0}"
private let minus = "\u{2212}"

@Suite("VND formatting")
struct VNDTests {
    @Test(arguments: [
        (0, "0"), (5, "5"), (999, "999"), (1_000, "1.000"), (450_000, "450.000"),
        (1_234_567, "1.234.567"), (999_999_999_999, "999.999.999.999"),
    ] as [(Int64, String)])
    func grouping(amount: Int64, expected: String) {
        #expect(VND.string(amount, style: .plain) == expected)
    }

    @Test func styles() {
        #expect(VND.string(450_000) == "450.000\(nbsp)₫")
        #expect(VND.string(450_000, style: .suffixD) == "450.000đ")
        #expect(VND.string(450_000, style: .spoken) == "450.000\(nbsp)đồng")
    }

    @Test("Negative amounts use U+2212, the same width as +")
    func negative() {
        #expect(VND.string(-120_000) == "\(minus)120.000\(nbsp)₫")
        #expect(VND.signedString(-120_000) == "\(minus)120.000\(nbsp)₫")
        #expect(VND.signedString(450_000) == "+450.000\(nbsp)₫")
        #expect(VND.signedString(0) == "0\(nbsp)₫")
    }

    @Test("Int64.min does not trap")
    func extremes() {
        #expect(VND.string(.min, style: .plain) == "\(minus)9.223.372.036.854.775.808")
        #expect(VND.string(.max, style: .plain) == "9.223.372.036.854.775.807")
    }

    @Test(arguments: [
        (0, "0"), (950, "950"), (1_000, "1k"), (1_049, "1k"), (1_050, "1,1k"),
        (12_500, "12,5k"), (99_949, "99,9k"), (99_950, "100k"), (450_000, "450k"),
        (999_499, "999k"),
        // Rounds up to 1.000k, so it is said in the next unit.
        (999_500, "1tr"), (999_999, "1tr"),
        (1_200_000, "1,2tr"), (12_000_000, "12tr"), (125_400_000, "125tr"),
        (999_600_000, "1\(nbsp)tỷ"), (1_500_000_000, "1,5\(nbsp)tỷ"),
        (1_234_000_000_000, "1.234\(nbsp)tỷ"),
        (-450_000, "\(minus)450k"),
    ] as [(Int64, String)])
    func compact(amount: Int64, expected: String) {
        #expect(VND.compact(amount) == expected)
    }

    @Test("Compact form survives the extremes")
    func compactExtremes() {
        #expect(VND.compact(.max) == "9.223.372.037\(nbsp)tỷ")
        #expect(VND.compact(.min) == "\(minus)9.223.372.037\(nbsp)tỷ")
    }
}

@Suite("Amount keypad")
struct AmountInputTests {
    // `#expect(input.append(...))` cannot call a mutating method inside the
    // macro, so each press is recorded first and checked after.

    @Test("4-5-0-000 types 450.000: four presses instead of six")
    func fastestPath() {
        var input = AmountInput()
        let presses = [input.append(digit: 4), input.append(digit: 5), input.append(digit: 0), input.appendThousand()]
        #expect(presses == [true, true, true, true])
        #expect(input.value == 450_000)
    }

    @Test("Leading zeros and 000 on an empty amount are rejected, not stored")
    func leadingZeros() {
        var input = AmountInput()
        let presses = [input.append(digit: 0), input.appendThousand()]
        #expect(presses == [false, false])
        #expect(input.value == 0)
        #expect(input.isEmpty)
    }

    @Test("The 13th digit is rejected and the amount is unchanged")
    func maximum() {
        var input = AmountInput()
        let twelve = (0..<12).map { _ in input.append(digit: 9) }
        #expect(twelve.allSatisfy { $0 })
        #expect(input.value == AmountInput.maximum)
        let extra = [input.append(digit: 9), input.append(digit: 0)]
        #expect(extra == [false, false])
        #expect(input.value == AmountInput.maximum)
    }

    @Test("000 that would pass the maximum is rejected")
    func thousandOverflow() {
        var input = AmountInput(value: 1_000_000_000)
        let rejected = input.appendThousand()
        #expect(!rejected)
        #expect(input.value == 1_000_000_000)

        var small = AmountInput(value: 999_999_999)
        let accepted = small.appendThousand()
        #expect(accepted)
        #expect(small.value == 999_999_999_000)
    }

    @Test func deleteAndClear() {
        var input = AmountInput(value: 450_000)
        let deleted = input.deleteLast()
        #expect(deleted)
        #expect(input.value == 45_000)
        input.clear()
        #expect(input.value == 0)
        let deletedEmpty = input.deleteLast()
        #expect(!deletedEmpty)
    }

    @Test("set rejects out-of-range values instead of clamping them")
    func set() {
        var input = AmountInput(value: 5)
        let outOfRange = [input.set(-1), input.set(AmountInput.maximum + 1)]
        #expect(outOfRange == [false, false])
        #expect(input.value == 5)
        let inRange = input.set(1_200_000)
        #expect(inRange)
        #expect(input.value == 1_200_000)
    }

    @Test("init clamps, since it has no way to report")
    func initClamps() {
        #expect(AmountInput(value: -5).value == 0)
        #expect(AmountInput(value: .max).value == AmountInput.maximum)
    }
}

@Suite("Amount parser")
struct AmountParserTests {
    @Test(arguments: [
        ("450k", 450_000, ""),
        ("450K", 450_000, ""),
        ("bán 3 thùng nước 450k", 450_000, "bán 3 thùng nước"),
        ("bán 3 thùng nước 450 nghìn", 450_000, "bán 3 thùng nước"),
        ("450 ngàn tiền điện", 450_000, "tiền điện"),
        ("450 nghin", 450_000, ""),
        ("tiền điện 850.000đ", 850_000, "tiền điện"),
        ("tiền điện: 850.000 đồng", 850_000, "tiền điện"),
        ("850.000₫", 850_000, ""),
        ("850.000 VND", 850_000, ""),
        ("1tr2", 1_200_000, ""),
        ("1TR2", 1_200_000, ""),
        ("nhập hàng 1 triệu 2", 1_200_000, "nhập hàng"),
        ("1 Triệu 2", 1_200_000, ""),
        ("1 triệu 25", 1_250_000, ""),
        ("1 triệu 250", 1_250_000, ""),
        ("1 triệu 200 nghìn", 1_200_000, ""),
        ("1 triệu 200 nghìn đồng", 1_200_000, ""),
        ("1,2 triệu", 1_200_000, ""),
        ("1.5tr", 1_500_000, ""),
        ("2 triệu rưỡi", 2_500_000, ""),
        ("2 trieu ruoi", 2_500_000, ""),
        ("5 nghìn rưỡi", 5_500, ""),
        ("1 tỷ 2", 1_200_000_000, ""),
        ("1,5 tỷ", 1_500_000_000, ""),
        ("1 tỷ 200 triệu", 1_200_000_000, ""),
        ("1.500 nghìn", 1_500_000, ""),
        ("1,500k", 1_500_000, ""),
    ] as [(String, Int64, String)])
    func explicitAmounts(text: String, amount: Int64, note: String) throws {
        let parsed = try #require(AmountParser.parse(text))
        #expect(parsed.amount == amount)
        #expect(parsed.note == note)
        #expect(!parsed.assumedThousands)
    }

    @Test("A number followed by a word is a quantity, not the amount's tail")
    func quantityAfterUnit() throws {
        let parsed = try #require(AmountParser.parse("chi 1 triệu 2 thùng sơn"))
        #expect(parsed.amount == 1_000_000)
        #expect(parsed.note == "chi 2 thùng sơn")
    }

    @Test("Unit letters inside a word are not a unit: kg, trà")
    func unitInsideWord() throws {
        let kg = try #require(AmountParser.parse("5kg đường 100k"))
        #expect(kg.amount == 100_000)
        #expect(kg.note == "5kg đường")
        let tea = try #require(AmountParser.parse("2 trà sữa 60k"))
        #expect(tea.amount == 60_000)
        #expect(tea.note == "2 trà sữa")
    }

    @Test("A number glued to letters is part of a word: A4")
    func numberInsideWord() throws {
        let parsed = try #require(AmountParser.parse("A4 giấy 50k"))
        #expect(parsed.amount == 50_000)
        #expect(parsed.note == "A4 giấy")
    }

    @Test("With several amounts the last one wins; the rest stays in the note")
    func lastAmountWins() throws {
        let parsed = try #require(AmountParser.parse("150k một thùng, tổng 450k"))
        #expect(parsed.amount == 450_000)
        #expect(parsed.note == "150k một thùng, tổng")
    }

    @Test("A bare small number at the end is read as nghìn, and says so")
    func assumedThousands() throws {
        let parsed = try #require(AmountParser.parse("thu 450"))
        #expect(parsed.amount == 450_000)
        #expect(parsed.note == "thu")
        #expect(parsed.assumedThousands)

        let decimal = try #require(AmountParser.parse("thu 1,5"))
        #expect(decimal.amount == 1_500, "scaled before rounding, not 2.000")
        #expect(decimal.assumedThousands)
    }

    @Test("A bare number of 1.000 or more is taken literally")
    func bareLargeNumber() throws {
        let parsed = try #require(AmountParser.parse("thu 450000"))
        #expect(parsed.amount == 450_000)
        #expect(!parsed.assumedThousands)
    }

    @Test("Explicit đồng keeps a small number literal")
    func explicitDong() throws {
        let parsed = try #require(AmountParser.parse("gửi xe 5.000đ"))
        #expect(parsed.amount == 5_000)
        let tiny = try #require(AmountParser.parse("450 đ"))
        #expect(tiny.amount == 450)
        #expect(!tiny.assumedThousands)
    }

    @Test("Decomposed (NFD) Vietnamese still matches the unit words")
    func decomposedUnicode() throws {
        let nfd = "1 trie\u{0323}\u{0302}u 2"
        let parsed = try #require(AmountParser.parse(nfd))
        #expect(parsed.amount == 1_200_000)
    }

    @Test(arguments: [
        "", "   ", "abc", "bán 3 thùng nước", "0k", "0", "1.2.3",
        // Digits glued to letters are part of a word, not a bare amount at the end.
        "mua giấy A4",
        // Over AmountInput.maximum: rejected rather than clamped.
        "1000000000000", "1.000.000.000.000đ", "2000 tỷ",
        // More than 15 digits is not a number we try to read.
        "12345678901234567890k",
    ])
    func noAmount(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test("The largest accepted amount parses exactly")
    func maximum() throws {
        let parsed = try #require(AmountParser.parse("999999999999"))
        #expect(parsed.amount == AmountInput.maximum)
    }
}
