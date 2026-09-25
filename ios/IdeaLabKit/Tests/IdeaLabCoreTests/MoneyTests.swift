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
        // "trăm": a hundred of the group it sits in.
        ("chi 1 triệu 2 trăm", 1_200_000, "chi"),
        ("chi 1 triệu 2 trăm nghìn", 1_200_000, "chi"),
        ("1 triệu 2 trăm 50", 1_250_000, ""),
        ("1 triệu 2 trăm 50 nghìn", 1_250_000, ""),
        ("2 trăm 50 nghìn", 250_000, ""),
        ("3 trăm rưỡi nghìn", 350_000, ""),
        ("5 nghìn 2 trăm", 5_200, ""),
        ("1 tỷ 2 trăm", 1_200_000_000, ""),
        // A tail before a currency, where đồng and the next group agree.
        ("5 nghìn 500 đồng", 5_500, ""),
        ("12k500đ", 12_500, ""),
        ("5 nghìn 2 trăm đồng", 5_200, ""),
        ("1 triệu 200 nghìn 500 đồng", 1_200_500, ""),
    ] as [(String, Int64, String)])
    func explicitAmounts(text: String, amount: Int64, note: String) throws {
        let parsed = try #require(AmountParser.parse(text))
        #expect(parsed.amount == amount)
        #expect(parsed.note == note)
        #expect(!parsed.assumedThousands)
        #expect(parsed.isExplicit)
    }

    @Test(
        "A spelled-out number followed by a noun is a quantity: \"150k một thùng\" is per crate",
        arguments: [
            ("150k một thùng", 150_000, "một thùng"),
            ("150k một trăm thùng", 150_000, "một trăm thùng"),
            ("150k năm mươi cái", 150_000, "năm mươi cái"),
            ("chi 1 triệu hai thùng sơn", 1_000_000, "chi hai thùng sơn"),
            ("mua năm cân gạo 150k", 150_000, "mua năm cân gạo"),
            ("trứng 30k một chục", 30_000, "trứng một chục"),
            ("trung 30k mot chuc", 30_000, "trung mot chuc"),
            ("2 chục trứng 60k", 60_000, "2 chục trứng"),
        ] as [(String, Int64, String)]
    )
    func perUnitPrice(text: String, amount: Int64, note: String) throws {
        let parsed = try #require(AmountParser.parse(text))
        #expect(parsed.amount == amount)
        #expect(parsed.note == note)
    }

    @Test("A bare hundred is read like any bare small number: as nghìn, flagged")
    func bareHundred() throws {
        let parsed = try #require(AmountParser.parse("thu 3 trăm"))
        #expect(parsed.amount == 300_000)
        #expect(parsed.assumedThousands)
        #expect(!parsed.isExplicit)
        #expect(AmountParser.parse("bán 2 trăm cái") == nil, "a hundred items is a quantity")
    }

    @Test(
        "A phrase that goes on in a way we cannot read is rejected, not cut short",
        arguments: [
            "chi 1 triệu hai", "chi 1 triệu năm trăm", "1 triệu 2500", "1 triệu 2,5", "2 tỷ mốt",
            "1 triệu hai, tiền hàng", "1 triệu hai trăm nghìn", "1 triệu hai rưỡi", "1 triệu 2 rưỡi",
            "1 triệu 2 trăm năm mươi nghìn", "1 triệu 2 rưỡi nghìn",
            // Before a currency, a tail could be đồng or the next group.
            "chi 1 triệu 2500 đồng", "1 triệu 2500đ", "1 triệu 2 đồng", "1tr2đ", "1 triệu 2 ₫",
            "1 triệu 2 trăm đồng", "5 nghìn 2 đồng", "1 triệu hai đồng",
            // Written in words: skipping it would let another amount win.
            "năm trăm nghìn", "chi hai triệu rưỡi", "tổng 450k, trả lại năm nghìn đồng",
            "tổng 450k, chi 2 trăm năm mươi nghìn", "tổng 450k, trả lại hai chục nghìn", "tổng 450k, 2 chục nghìn",
            // Also when an earlier, readable amount is in the same text.
            "150k một thùng, tổng 1 triệu hai",
        ]
    )
    func incompletePhrase(text: String) {
        #expect(AmountParser.parse(text) == nil, "reading only the first part would save less, silently")
    }

    @Test("Parts that each fit but overflow together return nil instead of trapping")
    func overflowingSum() {
        #expect(AmountParser.parse("18446744073 tỷ 999999 triệu") == nil)
        #expect(AmountParser.parse("18446744073 tỷ 999 trăm") == nil)
        #expect(AmountParser.parse("18446744073 tỷ rưỡi") == nil)
    }

    @Test("Rounding a product close to UInt64.max does not trap")
    func roundingNearTheLimit() throws {
        // 18446744073 × 10⁹ fits in UInt64; adding half of 10¹⁴ to round it did not.
        let parsed = try #require(AmountParser.parse("chi 0.00018446744073 tỷ"))
        #expect(parsed.amount == 184_467)
    }

    @Test("Decimals round half up to whole đồng")
    func roundsHalfUp() throws {
        #expect(AmountParser.parse("0,0005k")?.amount == 1)
        #expect(AmountParser.parse("0,0004k") == nil, "rounds to 0, which is no amount")
        #expect(AmountParser.parse("1,2345 triệu")?.amount == 1_234_500)
    }

    @Test("A number followed by a word is a quantity, not the amount's tail")
    func quantityAfterUnit() throws {
        let parsed = try #require(AmountParser.parse("chi 1 triệu 2 thùng sơn"))
        #expect(parsed.amount == 1_000_000)
        #expect(parsed.note == "chi 2 thùng sơn")
        #expect(AmountParser.parse("thuê xe 1 triệu 2 ngày")?.amount == 1_000_000, "a span of time is a quantity too")
        #expect(AmountParser.parse("1 trieu 2 cay")?.amount == 1_000_000)
    }

    @Test("Digits after a unit, then a word that is neither a quantity nor an ending: nil")
    func tailBeforeOtherWords() throws {
        #expect(AmountParser.parse("bán được 1 triệu 2 hôm qua") == nil, "1,2 triệu or 1 triệu and 2 of something")
        #expect(AmountParser.parse("chi 1 triệu 2 lúc sáng") == nil)
        #expect(try #require(AmountParser.parse("bán 1 triệu 2 rồi")).amount == 1_200_000, "rồi ends the sentence")
        #expect(try #require(AmountParser.parse("chi 1tr2 nữa")).amount == 1_200_000)
        #expect(try #require(AmountParser.parse("bán 1tr2 hôm qua")).amount == 1_200_000, "glued digits are always the tail")
        #expect(try #require(AmountParser.parse("1k5 bánh mì")).amount == 1_500)
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

    @Test(
        "With two or more amounts there is no guess",
        arguments: [
            "150k một thùng, tổng 450k", "tiền hàng 1tr, ship 25k", "1tr2 ship 30k", "2 triệu, 500k",
            "3 x 150k = 450k", "450k ăn với 3 đồng",
            // The second amount bare: on its own it would be read literally.
            "450k, tổng 500000", "450k rồi 1500", "450000 + 500000", "thuê 3500000/tháng, cọc 7000000",
            // After a word that may name a code, a number may still be money.
            "chốt đơn 450000, ship 30k", "cọc 1tr, tiền phòng 3500000", "450k phòng 1204", "450k, mã: 12345",
            "450k, đơn hàng 12345", "450k, mã đơn 12345 - 2500",
            // Thousands in spaced groups are one amount, whatever the spaces.
            "450k, 1 500 000", "450k, 1\u{00A0}500\u{00A0}000", "450k, 1\u{202F}500\u{202F}000", "450k, 1  500 000",
        ]
    )
    func severalAmounts(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test(
        "A bare amount is only the amount at the very end",
        arguments: ["450000 bán 3", "tiền nhà 3500000 tháng 9", "bán 1500 hôm qua"]
    )
    func bareAmountNotAtEnd(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test("The note closes the gap the amount leaves before punctuation")
    func noteTidy() throws {
        #expect(try #require(AmountParser.parse("thu 450k, còn nợ 2 thùng")).note == "thu, còn nợ 2 thùng")
        #expect(try #require(AmountParser.parse("tiền điện 850k .")).note == "tiền điện")
    }

    @Test("A bare number next to an explicit amount does not make it two amounts")
    func explicitWithBare() throws {
        let parsed = try #require(AmountParser.parse("bán 3 thùng nước 450k"))
        #expect(parsed.amount == 450_000)
        #expect(try #require(AmountParser.parse("450k bán 3")).amount == 450_000)
        #expect(try #require(AmountParser.parse("450k bán 1500 cái")).amount == 450_000, "a count, not at the end")
        #expect(try #require(AmountParser.parse("450k, mã đơn #12345")).amount == 450_000, "a code, not a number on its own")
        #expect(try #require(AmountParser.parse("450k bán 1500kg")).amount == 450_000, "a weight, not a number on its own")
        #expect(try #require(AmountParser.parse("450k, in 1500-2000 tờ")).amount == 450_000, "a range of counts")
        #expect(try #require(AmountParser.parse("450k, 1500 đô")).amount == 450_000, "another currency")
        #expect(try #require(AmountParser.parse("450k, gọi 0912 345 678")).amount == 450_000, "a phone number in groups")
        #expect(try #require(AmountParser.parse("450k, in 1 500 tờ")).amount == 450_000, "a count in groups")
    }

    @Test("Thousands separators read anywhere, but a count or another currency is no amount")
    func groupedNumbers() {
        #expect(AmountParser.parse("tiền nhà tháng 9 3.500.000")?.amount == 3_500_000)
        #expect(AmountParser.parse("tháng 10 450.000")?.amount == 450_000, "not a spaced 10 450")
        #expect(AmountParser.parse("bán 3 450.000")?.amount == 450_000)
        #expect(AmountParser.parse("450.000 bán 3")?.amount == 450_000)
        #expect(AmountParser.parse("bán 1.500 cái") == nil)
        #expect(AmountParser.parse("chi 1.500 đô") == nil)
        #expect(AmountParser.parse("450k, in 1.500 tờ")?.amount == 450_000)
    }

    @Test("Digits after a unit that belong to a date, a time or a percentage stay in the note")
    func tailBeforeDateTimePercent() throws {
        for (text, note) in [
            ("450k 25/9", "25/9"), ("450k 12:30", "12:30"), ("450k 25%", "25%"),
            ("450k 25 %", "25 %"), ("450k 25 / 9", "25 / 9"), ("450k 12 : 30", "12: 30"), ("450k 25-9", "25-9"),
            ("450k 25 . 9", "25. 9"), ("450k 25 , 9", "25, 9"), ("450k 25 -9", "25 -9"),
        ] {
            let parsed = try #require(AmountParser.parse(text))
            #expect(parsed.amount == 450_000, "\(text)")
            #expect(parsed.note == note, "\(text)")
        }
        #expect(AmountParser.parse("1 triệu 2 (tiền hàng)")?.amount == 1_200_000, "a tail before a bracketed note")
        #expect(AmountParser.parse("1 triệu 2, còn nợ")?.amount == 1_200_000)
        #expect(AmountParser.parse("1 triệu 2 - còn nợ")?.amount == 1_200_000, "a spaced dash ends the phrase")
    }

    @Test(
        "Digits after a tail and a clause break: 1,2 triệu and a count, or 1 triệu and a range?",
        arguments: ["1 triệu 2, 3 người", "1 triệu 2 - 3 người", "chi 1 triệu 2. 3 ngày nữa trả", "450k 25 - 9", "450k 25, 9"]
    )
    func tailBeforeClauseAndDigits(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test("Digits glued to the unit are its tail, whatever follows")
    func gluedTailBeforeDigits() {
        #expect(AmountParser.parse("1tr2, 3 người")?.amount == 1_200_000)
        #expect(AmountParser.parse("1tr2 - 3 người")?.amount == 1_200_000)
    }

    @Test("A number in spaced groups is never read: \"bán 3 450\" may be three of something")
    func spacedGroups() {
        #expect(AmountParser.parse("thu 1 500 000") == nil)
        #expect(AmountParser.parse("bán 3 450") == nil)
        #expect(AmountParser.parse("mua 3 150k")?.amount == 150_000, "a count before a price, not 3.150.000")
    }

    @Test("Ten digits or more without separators are an account or a phone number")
    func longBareNumbers() {
        #expect(AmountParser.parse("gọi 84912345678") == nil, "not 84.912.345.678 ₫")
        #expect(AmountParser.parse("thu 1000000000") == nil)
        #expect(AmountParser.parse("thu 999999999")?.amount == 999_999_999)
        #expect(AmountParser.parse("bán nhà 3.500.000.000")?.amount == 3_500_000_000, "with separators it is written as money")
    }

    @Test(
        "An identifier is neither the amount nor a second amount",
        arguments: [
            ("450k, mã đơn 12345", 450_000), ("450k, SĐT 0912345678", 450_000), ("450k, gọi 0912345678", 450_000),
            ("450k, mã đơn: 12345", 450_000), ("450k, mã đơn hàng 12345", 450_000),
            ("450k, số điện thoại 912345678", 450_000), ("450k, STK là 123456789", 450_000),
            ("450k, số lượng 1500", 450_000), ("450k, so tai khoan 123456789", 450_000),
            // The label is the last words before the number, whatever came first.
            ("450k mã đơn 12345", 450_000),
            ("đóng học phí năm 2025 cho con 5tr", 5_000_000),
            ("đóng học phí năm học 2025 hết 5tr", 5_000_000), ("450k năm tài chính 2025", 450_000),
            // A month's number before "năm" makes a date, not a length of time.
            ("ngày 25 tháng 9 năm 2025 thu 450k", 450_000), ("tháng mười hai năm 2025, thu 450k", 450_000),
            ("450k tháng 2 năm 2025", 450_000), ("450k tháng hai năm 2025", 450_000), ("450k, SĐT 0912-345 678", 450_000),
            ("450k quý 2 năm 2025", 450_000), ("450k học kỳ 1 năm 2025", 450_000),
            // An area code in brackets is part of the phone number.
            ("450k, SĐT (024) 3825 2509", 450_000), ("450k, SĐT (024)-3825 2509", 450_000),
            ("450k, SĐT (024)\u{2013}3825 2509", 450_000),
            // A spaced dash joins a phone's short groups, not a longer number.
            ("SĐT 0912345678 - 450000", 450_000), ("SĐT 0912345678 - 45000", 45_000),
            ("SĐT 0912345678 - 450.000", 450_000), ("450k, SĐT (024) - 3825 2509", 450_000),
            ("SĐT 0912345678 - 2500", 2_500), ("SĐT 0912.345.678 - 2500", 2_500), ("SĐT 09123 45678 - 2500", 2_500),
            ("450k, SĐT 912 - 345 - 678", 450_000),
            // After a code that is not a phone, a spaced dash separates what comes next.
            ("mã đơn 12345 - 2500", 2_500), ("mã đơn 1234 - 2500", 2_500), ("mã đơn 0123 - 2500", 2_500),
            // Plain spaces do not join a room number to the rent after it.
            ("phòng 12 3500000", 3_500_000),
            // Written with separators, an identifier is still one.
            ("450k, SĐT 912.345.678", 450_000), ("450k, mã đơn 12.345", 450_000), ("450k, SĐT +84 912.345.678", 450_000),
            // A unit ends the phone number: the amount after it is money.
            ("SĐT 0912 345 678 450k", 450_000), ("450k, SĐT 0912.345 678", 450_000),
        ] as [(String, Int64)]
    )
    func identifiers(text: String, amount: Int64) throws {
        let parsed = try #require(AmountParser.parse(text))
        #expect(parsed.amount == amount)
    }

    @Test(
        "A number that is, or may be, only an identifier gives no amount",
        arguments: [
            "mã đơn 12345", "gọi 0912345678", "phòng 1204", "mã đơn hàng 12345", "số điện thoại 12345",
            "ma don hang 12345", "mã đơn là 12345", "SĐT: 912345678", "gọi 0912 345 678", "mã 12345", "đơn 12345",
            "đơn hàng 12345", "điện thoại 912345678", "năm 2025", "năm học 2025",
            "SĐT 912.345.678", "mã đơn 12.345", "số hóa đơn 12.345", "số lượng 2 nghìn",
            // Separators alone do not make a code money.
            "code 12.345", "id 12.345", "phòng 3.500.000", "mã đơn #12.345", "SĐT +84 912.345.678",
            // The rest of a phone number or code in groups.
            "hotline 1900 1234", "zalo 912 345 678", "sinh năm 1990", "tháng 9 năm 2025", "tháng chín năm 2025",
            // Separators inside the phone number do not break it up.
            "SĐT 0912.345 678", "SĐT 0912,345 678", "SĐT 0912-345 678", "tháng 2 năm 2025", "tháng hai năm 2025",
            "quý 2 năm 2025", "học kỳ 1 năm 2025", "SĐT (024) 3825 2509", "mã đơn (12345)",
            "SĐT (024)-3825 2509", "SĐT (024).3825 2509",
            // Dashes from formatted text: en dash, non-breaking hyphen.
            "SĐT (024)\u{2013}3825 2509", "SĐT 0912\u{2011}345 678",
            "SĐT 0912\u{2010}345 678", "SĐT 0912\u{2012}345 678", "SĐT 0912\u{2014}345 678", "SĐT 0912\u{2212}345 678",
            "hotline 1900 - 1234", "SĐT (024) - 3825 2509", "gọi 0912 - 345 - 678",
            "SĐT 912 - 345 - 678", "số điện thoại 1900 - 1234", "zalo 0912 - 345 - 678",
            // After a word that may name a phone, the rest of one may be too.
            "zalo 912 - 345 - 678", "điện thoại 912 - 345 - 678",
        ]
    )
    func identifierAlone(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test("A spaced dash with nothing before it joins nothing")
    func dashAtStart() {
        #expect(AmountParser.parse(" - 2500")?.amount == 2_500)
    }

    @Test("Money words make a label what the money is for")
    func labelsForMoney() {
        #expect(AmountParser.parse("tiền phòng 3500000")?.amount == 3_500_000)
        #expect(AmountParser.parse("tổng số 450000")?.amount == 450_000)
        #expect(AmountParser.parse("số tiền 450000")?.amount == 450_000)
        #expect(AmountParser.parse("mua điện thoại 4500000")?.amount == 4_500_000)
        #expect(AmountParser.parse("nạp tài khoản 500000")?.amount == 500_000)
        #expect(AmountParser.parse("thanh toán đơn hàng 450000")?.amount == 450_000)
        #expect(AmountParser.parse("năm 2000000")?.amount == 2_000_000, "not a year")
        #expect(AmountParser.parse("gửi xe 2000")?.amount == 2_000, "a year needs \"năm\"")
        #expect(AmountParser.parse("phí mỗi năm 2k")?.amount == 2_000, "a year is four plain digits")
        #expect(AmountParser.parse("phí mỗi năm 2000")?.amount == 2_000, "mỗi năm is a length of time")
        #expect(AmountParser.parse("phí duy trì năm 2k")?.amount == 2_000, "after a year label, a unit still makes it money")
        #expect(AmountParser.parse("chi phí năm nay 2000")?.amount == 2_000, "năm nay is no year label")
        #expect(AmountParser.parse("phí hai năm 2000")?.amount == 2_000, "two years, a length of time")
        #expect(AmountParser.parse("phí ba năm 2000")?.amount == 2_000)
        #expect(AmountParser.parse("phí 2 năm 2000")?.amount == 2_000)
        #expect(AmountParser.parse("phí 2 năm tài chính 2025")?.amount == 2_025, "the numeral counts before a longer label too")
    }

    @Test("After a label that only may name a code, a unit or a money word makes it money")
    func explicitAfterPossibleLabel() {
        #expect(AmountParser.parse("mua code 50k")?.amount == 50_000)
        #expect(AmountParser.parse("phòng 450k")?.amount == 450_000)
        #expect(AmountParser.parse("hóa đơn 450.000")?.amount == 450_000)
        #expect(AmountParser.parse("chốt đơn 450.000")?.amount == 450_000)
        #expect(AmountParser.parse("hóa đơn 450000")?.amount == 450_000)
        #expect(AmountParser.parse("tiền phòng 3.500.000")?.amount == 3_500_000)
        #expect(AmountParser.parse("thu 450000")?.amount == 450_000, "a plain large number still reads")
        #expect(AmountParser.parse("thu 0,5")?.amount == 500, "a decimal with a leading zero is not an identifier")
    }

    @Test("A bare small number at the end is read as nghìn, and says so")
    func assumedThousands() throws {
        let parsed = try #require(AmountParser.parse("thu 450"))
        #expect(parsed.amount == 450_000)
        #expect(parsed.note == "thu")
        #expect(parsed.assumedThousands)
        #expect(!parsed.isExplicit)

        let decimal = try #require(AmountParser.parse("thu 1,5"))
        #expect(decimal.amount == 1_500, "scaled before rounding, not 2.000")
        #expect(decimal.assumedThousands)
    }

    @Test(
        "A bare number that does not stand alone is not an amount",
        arguments: ["tip 10%", "ngày 25/9", "hẹn 7:30", "sđt 0912-345-678", "phòng 12A"]
    )
    func bareNumberNotAlone(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test("A bare number before closing punctuation or inside brackets still counts")
    func bareNumberWithPunctuation() throws {
        #expect(try #require(AmountParser.parse("thu 450.")).amount == 450_000)
        #expect(try #require(AmountParser.parse("thu (450)")).amount == 450_000)
        #expect(try #require(AmountParser.parse("thu 450!")).amount == 450_000)
    }

    @Test(
        "A price next to a multiplication sign is a unit price: no guess at the total",
        arguments: [
            "3 x 150k", "3 thùng x 150k", "3kg x 20k", "3x 150k", "150k x 3", "150k x3", "150k x 3 thùng",
            "150k × 3", "2*150k", "tổng 450k, 3 X 150k", "150k X 3",
            // The quantity in words, or several words away.
            "ba thùng x 150k", "3 chai nước x 150k", "3 mét vuông x 150k", "150k x hai thùng", "150k x 3 chai nước",
            // The sign further along the clause.
            "150k/cái x 3", "150k một thùng x 3", "20k/kg x 3kg", "2 chục x 150k",
            // Quantities typed without diacritics.
            "bon thung x 150k", "nam chai x 150k", "mot tram cai x 150k", "150k x hai muoi cai",
            // The quantity between the x and the price.
            "x2 450000", "150k 2x",
        ]
    )
    func multiplied(text: String) {
        #expect(AmountParser.parse(text) == nil)
    }

    @Test("An x inside a word, a model name's X, an x with no quantity, or a total after the multiplication is fine")
    func notMultiplied() throws {
        #expect(try #require(AmountParser.parse("taxi 150k")).amount == 150_000)
        #expect(try #require(AmountParser.parse("150k xe ôm")).amount == 150_000)
        #expect(try #require(AmountParser.parse("bán 2 box 150k")).amount == 150_000)
        #expect(try #require(AmountParser.parse("ốp iPhone X 150k")).amount == 150_000)
        #expect(try #require(AmountParser.parse("bán 2 ốp iPhone X 150k")).amount == 150_000, "a capital X after a word is a model")
        #expect(try #require(AmountParser.parse("150k xăng 2 lít")).amount == 150_000, "xăng is a word, not a times sign")
        #expect(try #require(AmountParser.parse("áo size x 150k")).amount == 150_000, "no quantity before the x")
        #expect(try #require(AmountParser.parse("2 áo, size x 150k")).amount == 150_000, "the 2 is in another clause")
        #expect(try #require(AmountParser.parse("thu 450k, còn 2 x 3 thùng chưa giao")).amount == 450_000, "the x is in another clause")
        #expect(try #require(AmountParser.parse("2 ốp iPhone X 150k")).amount == 150_000, "the capital X's own neighbour decides")
        #expect(try #require(AmountParser.parse("ốp Galaxy X2 150k")).amount == 150_000, "a capital X before digits is a model too")
        #expect(try #require(AmountParser.parse("3 x, tổng 450k")).amount == 450_000, "the x is in another clause")
    }

    @Test(
        "A money word that begins an ordinary noun is not money",
        arguments: [
            ("ăn với ba đồng nghiệp hết 450k", 450_000),
            ("trả cho năm đồng nghiệp 500k", 500_000),
            ("khám ba triệu chứng 150k", 150_000),
            ("450k ăn với 3 đồng nghiệp", 450_000),
            ("150k khám 3 triệu chứng", 150_000),
            ("sửa 2 đồng hồ 300k", 300_000),
            ("tăng 2 tỷ lệ 50k", 50_000),
            ("120k an voi 3 dong nghiep", 120_000),
            ("450k mua 3 đồng tiền cổ", 450_000),
            ("450k mua 3 dong tien co", 450_000),
        ] as [(String, Int64)]
    )
    func compoundNouns(text: String, amount: Int64) throws {
        #expect(try #require(AmountParser.parse(text)).amount == amount)
    }

    @Test(
        "A spelled-out magnitude before a counting noun is a count, not money",
        arguments: [
            ("450k in 2 nghìn tờ rơi", 450_000),
            ("150k quyên góp cho 1 triệu cây", 150_000),
            ("in 2 nghìn tờ rơi hết 450k", 450_000),
            ("450k, 1 triệu 2 trăm nghìn tờ rơi", 450_000),
            ("450k in 1tr 200 nghìn tờ rơi", 450_000),
            ("bán 2 nghìn vé được 450k", 450_000),
            ("450k in 2 nghìn bản", 450_000),
            ("450k bán 2 nghìn vé", 450_000),
            ("450k in 3 nghìn trang", 450_000),
            ("450k đổi 2 nghìn bảng Anh", 450_000),
            ("450k đổi 2 nghìn nhân dân tệ", 450_000),
            // Typed without diacritics.
            ("450k ban 2 nghin ve", 450_000),
            ("450k doi 2 nghin do la", 450_000),
            ("450k doi 2 nghin dola", 450_000),
            // The count in words.
            ("450k in hai nghìn tờ rơi", 450_000),
            ("450k bán năm nghìn vé", 450_000),
            ("450k quyên góp một triệu cây", 450_000),
            ("450k đổi hai nghìn đô", 450_000),
            ("50k cho 2 ngàn nguoi xem", 50_000),
            ("đổi 2 nghìn đô hết 50k phí", 50_000),
        ] as [(String, Int64)]
    )
    func counts(text: String, amount: Int64) throws {
        #expect(try #require(AmountParser.parse(text)).amount == amount)
    }

    @Test("A count or another currency alone gives no amount; k and tr before a noun stay prices")
    func countsAlone() throws {
        #expect(AmountParser.parse("3 triệu người xem") == nil)
        #expect(AmountParser.parse("chi 2 nghìn đô") == nil, "dollars, not đồng")
        #expect(AmountParser.parse("chi 2k usd") == nil)
        #expect(try #require(AmountParser.parse("chi 2 triệu bản quyền")).amount == 2_000_000, "a copyright fee")
        #expect(try #require(AmountParser.parse("mua 2 triệu trang sức")).amount == 2_000_000, "jewellery")
        #expect(try #require(AmountParser.parse("2 triệu bảng hiệu")).amount == 2_000_000, "a sign board, not pounds")
        #expect(try #require(AmountParser.parse("chi 2 trieu ve que")).amount == 2_000_000, "về quê: going home")
        #expect(try #require(AmountParser.parse("mua 2 triệu vé số")).amount == 2_000_000, "lottery tickets for 2 triệu")
        #expect(AmountParser.parse("chi 2 trieu do la phi phat") == nil, "unaccented, \"do là\" (because) reads as đô la: nil, not a guess")
        #expect(try #require(AmountParser.parse("trà sữa 30k ly")).amount == 30_000, "a price per cup")
        #expect(try #require(AmountParser.parse("450 nghìn tiền điện")).amount == 450_000, "tiền is what it is for")
        #expect(try #require(AmountParser.parse("chi 2 triệu cho mẹ")).amount == 2_000_000)
    }

    @Test("Without the noun's second half, the same words are money again")
    func compoundNeedsItsSecondHalf() {
        #expect(AmountParser.parse("chi ba đồng") == nil, "an amount in words")
        #expect(AmountParser.parse("chi 3 đồng")?.amount == 3, "đồng alone is money")
    }

    @Test("A decimal with no leading digit is rejected, not read ten times too big")
    func leadingDecimalMark() {
        #expect(AmountParser.parse(".5 triệu") == nil)
        #expect(AmountParser.parse("chi ,5 triệu") == nil)
        #expect(AmountParser.parse("tổng...5 triệu")?.amount == 5_000_000, "an ellipsis is not a decimal mark")
    }

    @Test("A separator typed twice is rejected, not read from the digits after it")
    func doubledSeparator() {
        #expect(AmountParser.parse("1..5 triệu") == nil)
        #expect(AmountParser.parse("1,,5 triệu") == nil)
        #expect(AmountParser.parse("chi 1.,5 triệu") == nil)
    }

    @Test("A bare number of 1.000 or more is taken literally")
    func bareLargeNumber() throws {
        let parsed = try #require(AmountParser.parse("thu 450000"))
        #expect(parsed.amount == 450_000)
        #expect(!parsed.assumedThousands)
        #expect(!parsed.isExplicit, "no unit and no separators: still a bare number")
    }

    @Test("A sentence still being typed yields a bare, non-explicit reading")
    func halfTypedSentence() throws {
        let typing = try #require(AmountParser.parse("bán 3"))
        #expect(typing.amount == 3_000)
        #expect(!typing.isExplicit)
        #expect(AmountParser.parse("bán 3 thùng") == nil)
    }

    @Test("Explicit đồng keeps a small number literal")
    func explicitDong() throws {
        let parsed = try #require(AmountParser.parse("gửi xe 5.000đ"))
        #expect(parsed.amount == 5_000)
        let tiny = try #require(AmountParser.parse("450 đ"))
        #expect(tiny.amount == 450)
        #expect(!tiny.assumedThousands)
        #expect(tiny.isExplicit)
        let grouped = try #require(AmountParser.parse("thu 450.000"))
        #expect(grouped.isExplicit, "thousands separators alone make it money")
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
        let parsed = try #require(AmountParser.parse("999.999.999.999"))
        #expect(parsed.amount == AmountInput.maximum)
        #expect(try #require(AmountParser.parse("999.999.999.999đ")).amount == AmountInput.maximum)
    }
}
