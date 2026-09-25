/// An amount pulled out of free text, plus what is left of the text.
public struct ParsedAmount: Hashable, Sendable {
    /// Whole đồng, always in `1...AmountInput.maximum`.
    public var amount: Int64
    /// The text with the amount phrase removed: "bán 3 thùng nước 450k" → "bán 3 thùng nước".
    public var note: String
    /// `true` when the text gave no unit and a small number was read as nghìn
    /// ("thu 450" → 450.000 ₫). Show the reading back so the user can catch it.
    public var assumedThousands: Bool
    /// `true` when the amount carried a unit, a currency or thousands
    /// separators ("450k", "450.000đ"); `false` for a bare trailing number.
    /// A bare number is often a sentence still being typed ("bán 3" on the
    /// way to "bán 3 thùng"), so it should not replace an amount the user
    /// already entered some other way.
    public var isExplicit: Bool

    public init(amount: Int64, note: String, assumedThousands: Bool, isExplicit: Bool) {
        self.amount = amount
        self.note = note
        self.assumedThousands = assumedThousands
        self.isExplicit = isExplicit
    }
}

/// Reads amounts the way Vietnamese shop owners type and say them:
///
/// | Input | Amount |
/// | --- | --- |
/// | `450k`, `450 nghìn`, `450 ngàn`, `450.000đ`, `450.000 ₫` | 450.000 |
/// | `1tr2`, `1 triệu 2`, `1 triệu 200 nghìn`, `1,2 triệu` | 1.200.000 |
/// | `2 triệu rưỡi` | 2.500.000 |
/// | `1 tỷ 2` | 1.200.000.000 |
/// | `1 triệu 2 trăm`, `2 trăm 50 nghìn`, `3 trăm rưỡi nghìn` | 1.200.000 / 250.000 / 350.000 |
///
/// Rules, in the order they matter:
/// - A number is only an amount if it carries a unit (`k`, `nghìn`, `tr`,
///   `triệu`, `tỷ`, `đ`, `đồng`, `vnd`, `₫`) or thousands separators
///   (`450.000`). "3" in "bán 3 thùng" is a quantity.
/// - "." or "," followed by exactly three digits groups thousands
///   (`1.500` = 1500); otherwise it is a decimal mark (`1,5` = 1.5).
/// - Digits after a unit with no unit of their own continue it:
///   "1 triệu 2" = 1,2 triệu, "1 triệu 25" = 1,25 triệu, "1 triệu 2 rồi" —
///   at the end of the phrase, or glued to the unit ("1tr2 hôm qua"). Before
///   a counting or time noun they are a
///   quantity ("1 triệu 2 thùng", "1 triệu 2 ngày"); before any other word
///   ("bán 1 triệu 2 hôm qua") either is possible, so it is `nil`. With a currency
///   after them they could also be plain đồng ("1 triệu 2 đồng": 1.200.000 or
///   1.000.002?), so they are only read where both agree: "5 nghìn 500 đồng".
/// - With two or more amounts it returns `nil`: in "tiền hàng 1tr, ship
///   25k" the total is neither, and in "150k một thùng, tổng 450k" guessing
///   which one is meant is how a quantity ends up saved as the price. The
///   user keys the amount instead. Counts ("2 nghìn tờ rơi") and other
///   currencies are not amounts, so they do not count here.
/// - With no amount at all, a bare number at the very end is used, read as
///   nghìn if below 1.000 (`assumedThousands`) — if it stands alone: "10%",
///   "25/9" and "7:30" are not amounts.
/// - A price next to a multiplication sign ("3 x 150k", "ba thùng x 150k",
///   "150k × 3") is a unit price, and the total is anyone's guess: `nil`. So
///   is a decimal with no leading digit (".5 triệu"), which would otherwise
///   read as 5 triệu.
/// - A unit or currency word that begins an ordinary noun is not money:
///   "3 đồng nghiệp" are colleagues, "3 triệu chứng" symptoms, "tỷ lệ" a ratio.
/// - A spelled-out magnitude followed by a counting noun is a count: "in 2
///   nghìn tờ rơi" (flyers), "1 triệu cây" (trees). "k" and "tr" stay money
///   ("30k ly" is a price per cup). Any magnitude followed by another
///   currency is not đồng: "2 nghìn đô", "2 nghìn bảng Anh".
/// - Separators typed twice ("1..5 triệu") make the text unreadable, rather
///   than restarting at "5 triệu".
/// - A phrase that clearly goes on in a way this parser cannot read —
///   "1 triệu hai" (a spelled-out number), "1 triệu 2500", "1 triệu 2500
///   đồng" — is rejected as a whole. Reading only "1 triệu" would save a
///   smaller amount without a word. So is an amount written in words
///   ("năm trăm nghìn"): skipped, it would leave another amount in the text
///   looking like the only one.
/// - Spelled-out numbers followed by a noun are a quantity: "150k một thùng",
///   "150k năm mươi cái".
///
/// Anything that would be 0 or above `AmountInput.maximum` returns `nil`
/// rather than a guess.
public enum AmountParser {
    public static func parse(_ text: String) -> ParsedAmount? {
        let chars = Array(text)
        guard let phrases = scan(chars) else { return nil }

        let chosen: Phrase
        let value: UInt64
        var assumedThousands = false
        let explicit = phrases.filter(\.isExplicit)
        if explicit.count > 1 {
            return nil
        } else if let explicit = explicit.first {
            chosen = explicit
            value = explicit.value
        } else if let bare = phrases.last, isAtEnd(bare.end, in: chars), startsToken(bare.start, in: chars) {
            chosen = bare
            if let thousands = bare.valueInThousands {
                value = thousands
                assumedThousands = true
            } else {
                value = bare.value
            }
        } else {
            return nil
        }

        guard value > 0, value <= UInt64(AmountInput.maximum), !isMultiplied(chosen, in: chars) else { return nil }
        let rest = Array(chars[..<chosen.start]) + [" "] + Array(chars[chosen.end...])
        return ParsedAmount(
            amount: Int64(value), note: tidy(String(rest)),
            assumedThousands: assumedThousands, isExplicit: chosen.isExplicit
        )
    }

    // MARK: - Scanning

    struct Phrase {
        var start: Int
        var end: Int
        var value: UInt64
        /// Has a unit or thousands separators, so it is certainly money.
        var isExplicit: Bool
        /// For a bare number below 1.000, the same number read as nghìn —
        /// computed from the unrounded number, so "1,5" becomes 1.500, not 2.000.
        var valueInThousands: UInt64? = nil
    }

    /// A number as `mantissa / 10^scale`, e.g. "1,5" = 15 / 10¹.
    struct Number {
        var mantissa: UInt64
        var scale: Int
        var digitCount: Int
        var isGrouped: Bool
        var end: Int

        var isPlainInteger: Bool { scale == 0 && !isGrouped }
    }

    static let units: [String: UInt64] = [
        "k": 1_000, "nghìn": 1_000, "nghin": 1_000, "ngàn": 1_000, "ngan": 1_000,
        "tr": 1_000_000, "triệu": 1_000_000, "trieu": 1_000_000,
        "tỷ": 1_000_000_000, "tỉ": 1_000_000_000, "ty": 1_000_000_000,
    ]
    static let currencyWords: Set<String> = ["đ", "đồng", "dong", "vnđ", "vnd"]
    static let halfWords: Set<String> = ["rưỡi", "rưởi", "ruoi"]
    static let hundredWords: Set<String> = ["trăm", "tram"]
    /// Spelled-out digits and tens, with and without diacritics. After a unit
    /// they mean the amount goes on in words ("1 triệu hai"), which this
    /// parser does not read.
    static let numberWords: Set<String> = [
        "một", "mốt", "hai", "ba", "bốn", "tư", "năm", "lăm", "sáu", "bảy", "bẩy",
        "tám", "chín", "mười", "mươi", "linh", "lẻ", "trăm", "chục",
        "mot", "bon", "tu", "nam", "lam", "sau", "bay", "tam", "chin", "muoi", "le", "tram", "chuc",
    ]
    /// Nouns that count things. After a spelled-out magnitude they make it a
    /// count: "2 nghìn tờ rơi", "1 triệu cây", "3 triệu người xem". Unaccented
    /// forms that are also common other words ("qua", "can", "don") are left out.
    static let countNouns: Set<String> = [
        "tờ", "cây", "cái", "con", "chiếc", "quyển", "cuốn", "hộp", "thùng", "chai", "lon", "gói", "túi", "bao",
        "người", "lượt", "viên", "hạt", "bông", "bó", "trái", "quả", "đôi", "bộ", "tấm", "cục", "miếng", "phần",
        "suất", "ly", "cốc", "bát", "chén", "đĩa", "kg", "lít", "mét", "tấn", "khách", "đơn", "sản", "view", "like",
        "vé", "chỗ", "căn", "bản", "trang", "ve",
        "cay", "cai", "chiec", "quyen", "cuon", "hop", "thung", "goi", "tui", "nguoi", "luot", "vien", "hat",
        "bong", "trai", "mieng", "phan", "suat", "coc", "bat", "chen", "dia", "lit", "khach",
    ]
    /// After an amount's trailing digits, nouns that make those digits a
    /// quantity: counting nouns, and spans of time ("1 triệu 2 ngày").
    static let tailQuantityNouns: Set<String> = countNouns.union([
        "lần", "ngày", "tuần", "tháng", "giờ", "tiếng", "phút", "đêm", "buổi", "chuyến", "căn", "phòng", "đứa",
        "ngay", "tuan", "thang", "gio", "tieng", "phut", "dem", "buoi", "chuyen", "phong",
    ])
    /// Words that end a sentence without adding to it: "1 triệu 2 rồi" is 1,2 triệu.
    static let particles: Set<String> = [
        "rồi", "thôi", "nhé", "nha", "ạ", "nhỉ", "đó", "nè", "nữa", "luôn",
        "roi", "thoi", "nhe", "ne", "nua", "luon",
    ]
    /// Counting nouns that begin other nouns: "2 triệu bản quyền" is a
    /// copyright fee, "2 triệu trang sức" jewellery — money, not a count.
    static let countNounCompounds: [String: Set<String>] = [
        "bản": ["quyền", "quyen"],
        "trang": ["trí", "phục", "điểm", "sức", "thiết", "tri", "phuc", "diem", "suc", "thiet"],
        // "vé số" is a lottery ticket bought for the amount; unaccented "ve"
        // is also "về" (going home, about): "2 trieu ve que".
        "vé": ["số", "so"],
        "ve": ["so", "que", "nha", "viec", "quê", "nhà", "việc"],
    ]
    /// Other currencies: after an amount they mean it is not in đồng.
    static let foreignCurrencies: Set<String> = [
        "đô", "đôla", "dola", "usd", "dollar", "euro", "eur", "yên", "yen", "tệ", "won", "baht", "ringgit", "peso",
        "rupee", "rupiah", "rúp", "kíp", "riel", "franc", "gbp", "jpy", "cny", "rmb", "krw", "thb", "sgd",
        "aud", "cad", "chf", "hkd", "twd",
    ]
    /// Two-word currency names whose first word alone is an ordinary word:
    /// "bảng Anh" (a board is "bảng"), "nhân dân tệ", "do la".
    static let foreignCurrencyPhrases: [String: Set<String>] = [
        "bảng": ["anh"], "bang": ["anh"], "nhân": ["dân"], "nhan": ["dan"],
        // Unaccented "đô la"; "do" alone is "because".
        "do": ["la"],
    ]

    /// Second halves that turn a money word into an ordinary noun: "đồng
    /// nghiệp" (colleague), "đồng hồ" (clock), "triệu chứng" (symptom), "tỷ lệ"
    /// (ratio)... With or without diacritics, as people type both.
    static let compounds: [String: Set<String>] = {
        let dong: Set<String> = [
            "tiền", "tien", "bạc", "bac",
            "nghiệp", "hồ", "ý", "phục", "bào", "chí", "đội", "hương", "bằng", "thời", "xu", "loại", "hành",
            "minh", "bộ", "cảm", "sự", "môn", "tính", "nhất", "dạng", "nai", "tháp", "ruộng", "lúa", "quê", "hạng",
            "nghiep", "ho", "y", "phuc", "bao", "chi", "doi", "huong", "bang", "thoi", "loai", "hanh",
            "bo", "cam", "su", "mon", "tinh", "nhat", "dang", "thap", "ruong", "lua", "que", "hang",
        ]
        let trieu: Set<String> = ["chứng", "tập", "hồi", "phú", "chung", "tap", "hoi", "phu"]
        let ty: Set<String> = ["lệ", "giá", "phú", "số", "trọng", "le", "gia", "phu", "so", "trong"]
        return ["đồng": dong, "dong": dong, "triệu": trieu, "trieu": trieu, "tỷ": ty, "tỉ": ty, "ty": ty]
    }()

    enum Scanned {
        case phrase(Phrase)
        /// Not a number we understand ("1.2.3"): skip it.
        case notANumber
        /// A number that is not money — a count, another currency: scanning
        /// resumes at this index, past the words that belong to it.
        case notMoney(resumeAt: Int)
        /// Clearly an amount, but one we cannot compute ("1 triệu hai",
        /// "1 triệu 2500", an overflowing sum). The whole text is rejected:
        /// otherwise a leftover like "2500" would be picked up as the amount.
        case unreadable
    }

    /// Every amount phrase in the text, or `nil` if any of them is unreadable.
    static func scan(_ chars: [Character]) -> [Phrase]? {
        var phrases: [Phrase] = []
        var i = 0
        while i < chars.count {
            let startsWord = chars[i].isLetter && (i == 0 || !chars[i - 1].isLetter)
            if startsWord, numberWords.contains(word(at: i, in: chars).text.lowercased()) {
                let runEnd = endOfSpelledNumber(from: i, in: chars)
                if isMoneyWord(at: runEnd, in: chars) {
                    if let resumeAt = notMoneyEnd(afterSpelledNumber: runEnd, in: chars) {
                        // "hai nghìn tờ rơi", "năm nghìn đô": a count, or
                        // another currency, in words.
                        i = resumeAt
                        continue
                    }
                    // "năm trăm nghìn", "hai triệu rưỡi": an amount in words.
                    return nil
                }
            }
            let startsNumber = isDigit(chars[i]) && (i == 0 || !(chars[i - 1].isLetter || isDigit(chars[i - 1])))
            guard startsNumber else {
                i += 1
                continue
            }
            if i >= 1, chars[i - 1] == "." || chars[i - 1] == ",", i == 1 || chars[i - 2].isWhitespace {
                // ".5 triệu": read from the 5 it would be ten times too much.
                return nil
            }
            if followsMistypedSeparator(i, in: chars) {
                // "1..5 triệu": a slip of the finger, not 5 triệu.
                return nil
            }
            switch phrase(at: i, in: chars) {
            case .phrase(let phrase):
                phrases.append(phrase)
                i = phrase.end
            case .notANumber:
                while i < chars.count, isDigit(chars[i]) || chars[i] == "." || chars[i] == "," { i += 1 }
            case .notMoney(let resumeAt):
                i = resumeAt
            case .unreadable:
                return nil
            }
        }
        return phrases
    }

    /// One group of a spoken amount: digits, optionally "trăm" ("2 trăm",
    /// "2 trăm 50", "2 trăm rưỡi"). A group with "trăm" is a whole number of
    /// units; without it, the number keeps its own form (decimal, grouped...).
    struct Group {
        var number: Number
        /// Set when the group used "trăm": its value as a plain integer.
        var hundreds: UInt64?
        var end: Int

        func scaled(by unit: UInt64) -> UInt64? {
            guard let hundreds else { return AmountParser.scaled(number, by: unit) }
            return multiplying(hundreds, unit)
        }
    }

    static func group(at start: Int, in chars: [Character]) -> Group? {
        guard let number = number(at: start, in: chars) else { return nil }
        let afterNumber = skipSpaces(from: number.end, in: chars)
        let next = word(at: afterNumber, in: chars)
        guard number.isPlainInteger, number.digitCount <= 3, hundredWords.contains(next.text.lowercased()) else {
            return Group(number: number, hundreds: nil, end: number.end)
        }
        var value = number.mantissa * 100
        var end = next.end
        let afterHundred = skipSpaces(from: end, in: chars)
        if let rest = self.number(at: afterHundred, in: chars), rest.isPlainInteger, rest.digitCount <= 2 {
            value += rest.mantissa
            end = rest.end
        } else if halfWords.contains(word(at: afterHundred, in: chars).text.lowercased()) {
            value += 50
            end = word(at: afterHundred, in: chars).end
        }
        return Group(number: number, hundreds: value, end: end)
    }

    static func phrase(at start: Int, in chars: [Character]) -> Scanned {
        guard let first = group(at: start, in: chars) else { return .notANumber }

        var cursor = first.end
        let afterSpaces = skipSpaces(from: cursor, in: chars)
        let firstWord = word(at: afterSpaces, in: chars)

        guard let unit = unitValue(of: firstWord, in: chars) else {
            // No magnitude word. A currency word or ₫ still marks it as money.
            var isExplicit = first.number.isGrouped
            if let currencyEnd = currency(at: afterSpaces, in: chars) {
                cursor = currencyEnd
                isExplicit = true
            }
            guard let value = first.scaled(by: 1) else { return .unreadable }
            let isBelowThousand = first.hundreds.map { $0 < 1_000 } ?? (first.number.mantissa < 1_000 * pow10(first.number.scale))
            return .phrase(Phrase(
                start: start, end: cursor, value: value, isExplicit: isExplicit,
                valueInThousands: isExplicit || !isBelowThousand ? nil : first.scaled(by: 1_000)
            ))
        }

        guard var total = first.scaled(by: unit) else { return .unreadable }
        cursor = firstWord.end
        var lastUnit = unit
        var lastUnitWord = firstWord.text

        // "1 triệu 200 nghìn": each further part must use a smaller unit.
        // "1 triệu 2", "1 triệu 2 trăm": trailing digits with no unit continue the last one.
        while true {
            let nextStart = skipSpaces(from: cursor, in: chars)
            if let tail = group(at: nextStart, in: chars) {
                let afterTail = skipSpaces(from: tail.end, in: chars)
                let tailWord = word(at: afterTail, in: chars)
                let tailText = tailWord.text.lowercased()
                if let smaller = unitValue(of: tailWord, in: chars), smaller < lastUnit {
                    guard let part = tail.scaled(by: smaller), let sum = adding(total, part) else { return .unreadable }
                    total = sum
                    lastUnit = smaller
                    lastUnitWord = tailWord.text
                    cursor = tailWord.end
                    continue
                }
                let endsInCurrency = currency(at: afterTail, in: chars) != nil
                // "1tr2", "1k5": digits glued to the unit can only be its tail,
                // whatever word comes next ("bán 1tr2 hôm qua").
                let isGlued = nextStart == cursor
                let endsPhrase = isGlued || (tailWord.text.isEmpty ? isPhraseBoundary(tail.end, in: chars) : particles.contains(tailText))
                guard endsInCurrency || endsPhrase else {
                    if tailQuantityNouns.contains(tailText) {
                        // "1 triệu 2 thùng sơn" — the 2 is a quantity.
                        break
                    }
                    // "bán được 1 triệu 2 hôm qua": 1,2 triệu, or 1 triệu and 2 of
                    // something? "1 triệu 2 rưỡi", "1 triệu 2 trăm năm mươi": it
                    // goes on in words. Guessing could save the wrong amount.
                    return .unreadable
                }
                let part: UInt64?
                if let hundreds = tail.hundreds {
                    // "1 triệu 2 trăm": hundreds of the next unit down (nghìn).
                    part = multiplying(hundreds, lastUnit / 1_000)
                } else if tail.number.isPlainInteger, tail.number.digitCount <= 3 {
                    // "1 triệu 2" / "1 triệu 25": the leading digits of the next group.
                    part = tail.number.mantissa * (lastUnit / pow10(tail.number.digitCount))
                } else {
                    // "1 triệu 2500": it clearly goes on, but not in a way we can read.
                    return .unreadable
                }
                // Before a currency the tail could also be plain đồng: "1 triệu
                // 2 đồng" is 1.200.000 or 1.000.002. Only read it where both
                // agree, as in "5 nghìn 500 đồng".
                if endsInCurrency, part != tail.scaled(by: 1) { return .unreadable }
                guard let part, let sum = adding(total, part) else { return .unreadable }
                total = sum
                cursor = tail.end
                break
            }
            let next = word(at: nextStart, in: chars)
            let nextWord = next.text.lowercased()
            if halfWords.contains(nextWord) {
                guard let sum = adding(total, lastUnit / 2) else { return .unreadable }
                total = sum
                cursor = next.end
            } else if numberWords.contains(nextWord), continuesInWords(after: next.end, in: chars) {
                // "1 triệu hai", "1 triệu năm trăm": the amount goes on in
                // words we cannot read. ("150k một thùng" is fine: "một thùng"
                // is "per crate", and a noun follows.)
                return .unreadable
            }
            break
        }

        if let currencyEnd = currency(at: skipSpaces(from: cursor, in: chars), in: chars) {
            cursor = currencyEnd
        } else if let noun = nounMakingItNotMoney(after: cursor, unitWord: lastUnitWord, in: chars) {
            return .notMoney(resumeAt: noun.end)
        }
        return .phrase(Phrase(start: start, end: cursor, value: total, isExplicit: true))
    }

    /// Whether spelled-out number words from `index` on end the phrase, as
    /// the rest of the amount before them ("1 triệu hai", "1 triệu hai
    /// rưỡi"). Followed by a noun they are a quantity ("150k năm mươi cái").
    /// Followed by a unit ("1 triệu hai trăm nghìn") they are an amount in
    /// words, which `scan` rejects on its own.
    static func continuesInWords(after index: Int, in chars: [Character]) -> Bool {
        let end = endOfSpelledNumber(from: index, in: chars)
        // "trứng 30k một chục": tens of items, a count, like a noun would be.
        var start = end
        while start > 0, chars[start - 1].isLetter { start -= 1 }
        if ["chục", "chuc"].contains(String(chars[start..<end]).lowercased()) { return false }
        return isPhraseBoundary(end, in: chars)
    }

    /// The word after an amount that makes it not money: another currency
    /// ("2 nghìn đô"), or a counting noun after a spelled-out magnitude ("2
    /// nghìn tờ rơi"). After "k" or "tr" a noun is what the price is for:
    /// "30k ly" is a price per cup.
    static func nounMakingItNotMoney(after index: Int, unitWord: String, in chars: [Character]) -> (text: String, end: Int)? {
        let next = word(at: skipSpaces(from: index, in: chars), in: chars)
        let text = next.text.lowercased()
        if foreignCurrencies.contains(text) || isCompound(next, in: chars, table: foreignCurrencyPhrases) { return next }
        let isAbbreviation = ["k", "tr"].contains(unitWord.lowercased())
        guard !isAbbreviation, countNouns.contains(text), !isCompound(next, in: chars, table: countNounCompounds) else { return nil }
        return next
    }

    /// After a spelled-out number ending at `index`: its unit, then a word that
    /// makes it not money ("hai nghìn tờ rơi", "năm nghìn đô"). Returns where
    /// scanning resumes, or `nil` if it is money.
    static func notMoneyEnd(afterSpelledNumber index: Int, in chars: [Character]) -> Int? {
        let unit = word(at: skipSpaces(from: index, in: chars), in: chars)
        guard unitValue(of: unit, in: chars) != nil,
              let noun = nounMakingItNotMoney(after: unit.end, unitWord: unit.text, in: chars) else { return nil }
        return noun.end
    }

    /// Where the run of spelled-out number words starting at `index` (after
    /// any spaces) ends; `index` itself if there is none.
    static func endOfSpelledNumber(from index: Int, in chars: [Character]) -> Int {
        var end = index
        while true {
            let next = word(at: skipSpaces(from: end, in: chars), in: chars)
            let text = next.text.lowercased()
            guard numberWords.contains(text) || halfWords.contains(text) else { return end }
            end = next.end
        }
    }

    /// A unit or a currency right after `index`: "nghìn", "k", "đồng", "₫".
    static func isMoneyWord(at index: Int, in chars: [Character]) -> Bool {
        let start = skipSpaces(from: index, in: chars)
        return unitValue(of: word(at: start, in: chars), in: chars) != nil || currency(at: start, in: chars) != nil
    }

    /// `a + b`, or `nil` if it would overflow: parts of "18446744073 tỷ 999999
    /// triệu" each fit in UInt64, their sum does not.
    static func adding(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let sum = a.addingReportingOverflow(b)
        return sum.overflow ? nil : sum.partialValue
    }

    static func multiplying(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let product = a.multipliedReportingOverflow(by: b)
        return product.overflow ? nil : product.partialValue
    }

    /// Digits with optional "." / "," separators, starting at `start`.
    static func number(at start: Int, in chars: [Character]) -> Number? {
        guard start < chars.count, isDigit(chars[start]) else { return nil }
        var groups: [[Character]] = [[]]
        var i = start
        while i < chars.count {
            if isDigit(chars[i]) {
                groups[groups.count - 1].append(chars[i])
                i += 1
            } else if (chars[i] == "." || chars[i] == ","), i + 1 < chars.count, isDigit(chars[i + 1]) {
                groups.append([])
                i += 1
            } else {
                break
            }
        }

        let digits = groups.reduce(0) { $0 + $1.count }
        guard digits <= 15 else { return nil }  // keeps every product below UInt64.max

        let isGrouped = groups.count > 1
            && (1...3).contains(groups[0].count)
            && groups.dropFirst().allSatisfy { $0.count == 3 }
        if groups.count == 1 || isGrouped {
            let mantissa = UInt64(String(groups.joined()))!
            return Number(mantissa: mantissa, scale: 0, digitCount: digits, isGrouped: isGrouped, end: i)
        }
        guard groups.count == 2 else { return nil }  // "1.2.3" is not a number
        let mantissa = UInt64(String(groups[0] + groups[1]))!
        return Number(mantissa: mantissa, scale: groups[1].count, digitCount: digits, isGrouped: false, end: i)
    }

    /// `number × unit`, rounded half-up to whole đồng. `nil` on overflow.
    static func scaled(_ number: Number, by unit: UInt64) -> UInt64? {
        guard let product = multiplying(number.mantissa, unit) else { return nil }
        // Half-up from quotient and remainder: `product + divisor / 2` could
        // overflow when the product is close to UInt64.max.
        let (quotient, remainder) = product.quotientAndRemainder(dividingBy: pow10(number.scale))
        return remainder >= pow10(number.scale) - remainder ? quotient + 1 : quotient
    }

    // MARK: - Characters

    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func pow10(_ exponent: Int) -> UInt64 {
        (0..<exponent).reduce(1) { value, _ in value * 10 }
    }

    static func skipSpaces(from index: Int, in chars: [Character]) -> Int {
        var i = index
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        return i
    }

    /// The run of letters starting at `index` (empty if there is none).
    static func word(at index: Int, in chars: [Character]) -> (text: String, end: Int) {
        var i = index
        while i < chars.count, chars[i].isLetter { i += 1 }
        return (String(chars[index..<i]), i)
    }

    /// End index of "đ" / "đồng" / "vnd" / "₫" at `index`, if one is there.
    static func currency(at index: Int, in chars: [Character]) -> Int? {
        guard index < chars.count else { return nil }
        if chars[index] == "₫" { return index + 1 }
        let candidate = word(at: index, in: chars)
        guard currencyWords.contains(candidate.text.lowercased()), !isCompound(candidate, in: chars) else { return nil }
        return candidate.end
    }

    /// The size of the unit `word` names ("k", "triệu"...), unless it begins
    /// an ordinary noun ("triệu chứng").
    static func unitValue(of word: (text: String, end: Int), in chars: [Character]) -> UInt64? {
        guard let value = units[word.text.lowercased()], !isCompound(word, in: chars) else { return nil }
        return value
    }

    /// `word` and the word after it make an ordinary noun: "đồng nghiệp".
    static func isCompound(_ word: (text: String, end: Int), in chars: [Character], table: [String: Set<String>] = compounds) -> Bool {
        guard let partners = table[word.text.lowercased()] else { return false }
        return partners.contains(self.word(at: skipSpaces(from: word.end, in: chars), in: chars).text.lowercased())
    }

    /// Nothing but spaces or punctuation between `index` and the next word.
    /// "1 triệu 2" ends there; "1 triệu 2 thùng" does not.
    static func isPhraseBoundary(_ index: Int, in chars: [Character]) -> Bool {
        let next = skipSpaces(from: index, in: chars)
        return next == chars.count || !(chars[next].isLetter || isDigit(chars[next]))
    }

    /// Digits right after two or more separators that follow a digit: the
    /// "5" of "1..5" or "1,,5". An ellipsis after a word ("tổng...5") is fine.
    static func followsMistypedSeparator(_ index: Int, in chars: [Character]) -> Bool {
        var i = index - 1
        var separators = 0
        while i >= 0, chars[i] == "." || chars[i] == "," {
            separators += 1
            i -= 1
        }
        return separators >= 2 && i >= 0 && isDigit(chars[i])
    }

    /// Only spaces and closing punctuation after `index`: "thu 450." ends
    /// there; "tip 10%", "ngày 25/9" and "hẹn 7:30" do not.
    static func isAtEnd(_ index: Int, in chars: [Character]) -> Bool {
        chars[index...].allSatisfy { $0.isWhitespace || closingPunctuation.contains($0) }
    }

    /// A token starts at `index`: the text starts there, or a space or an
    /// opening bracket or quote comes before it — not "/" or ":".
    static func startsToken(_ index: Int, in chars: [Character]) -> Bool {
        index == 0 || chars[index - 1].isWhitespace || openingPunctuation.contains(chars[index - 1])
    }

    static let closingPunctuation: Set<Character> = [".", ",", "!", "?", ";", "…", ")", "]", "\"", "'", "”", "’"]
    static let openingPunctuation: Set<Character> = ["(", "[", "\"", "'", "“", "‘"]

    /// A multiplication in the price's clause: "3 x 150k", "3 chai nước x
    /// 150k", "150k × 3", "150k/cái x 3", "150k một thùng x 3".
    static func isMultiplied(_ phrase: Phrase, in chars: [Character]) -> Bool {
        var start = phrase.start
        while start > 0, !clauseBreaks.contains(chars[start - 1]) { start -= 1 }
        var end = phrase.end
        while end < chars.count, !clauseBreaks.contains(chars[end]) { end += 1 }
        for index in start..<phrase.start where isTimesSign(at: index, farSide: start..<index, in: chars) {
            return true
        }
        for index in phrase.end..<end where isTimesSign(at: index, farSide: (index + 1)..<end, in: chars) {
            return true
        }
        return false
    }

    /// "×" and "*" always are. A lone "x" ("xe", "taxi" are words) is when its
    /// far side — away from the price, within the clause — has a quantity in
    /// digits or words: "3 mét vuông x", "x hai thùng". A capital "X" is
    /// usually a model name ("ốp iPhone X 150k"), so it only counts right next
    /// to a number: "3 X 150k".
    static func isTimesSign(at index: Int, farSide: Range<Int>, in chars: [Character]) -> Bool {
        switch chars[index] {
        case "×", "*":
            return true
        case "x", "X":
            let isLetter = { (i: Int) in chars.indices.contains(i) && chars[i].isLetter }
            guard !isLetter(index - 1), !isLetter(index + 1) else { return false }
            if chars[index] == "X" {
                let isAfter = farSide.lowerBound > index
                let nearest = isAfter ? farSide.first { !chars[$0].isWhitespace } : farSide.last { !chars[$0].isWhitespace }
                return nearest.map { isDigit(chars[$0]) } ?? false
            }
            return hasQuantity(in: farSide, chars)
        default:
            return false
        }
    }

    /// Digits or a spelled-out number somewhere in `range`.
    static func hasQuantity(in range: Range<Int>, _ chars: [Character]) -> Bool {
        var i = range.lowerBound
        while i < range.upperBound {
            if isDigit(chars[i]) { return true }
            guard chars[i].isLetter else {
                i += 1
                continue
            }
            let next = word(at: i, in: chars)
            if numberWords.contains(next.text.lowercased()) { return true }
            i = next.end
        }
        return false
    }

    static let clauseBreaks: Set<Character> = [",", ";", ".", "!", "?", ":", "\n"]

    /// Collapses whitespace, closes the gap the amount leaves before
    /// punctuation ("thu , còn" → "thu, còn"), and trims separators left
    /// behind at either end.
    static func tidy(_ text: String) -> String {
        var words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for mark in [",", ";", ":", ".", "!", "?"] {
            words = words.replacing(" " + mark, with: mark)
        }
        let edges: Set<Character> = [",", ";", ":", "-", "–", "—", "=", "."]
        var trimmed = Substring(words)
        while let first = trimmed.first, first.isWhitespace || edges.contains(first) { trimmed.removeFirst() }
        while let last = trimmed.last, last.isWhitespace || edges.contains(last) { trimmed.removeLast() }
        return String(trimmed)
    }
}
