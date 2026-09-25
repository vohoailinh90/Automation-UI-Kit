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
///   "1 triệu 2" = 1,2 triệu, "1 triệu 25" = 1,25 triệu — but only at the end
///   of the phrase: in "1 triệu 2 thùng", 2 is a quantity.
/// - With several amounts, the last one wins ("150k một thùng, tổng 450k" →
///   450.000); the others stay in the note.
/// - With no amount at all, a bare number at the very end is used, read as
///   nghìn if below 1.000 (`assumedThousands`).
/// - A phrase that clearly goes on in a way this parser cannot read —
///   "1 triệu hai" (a spelled-out number), "1 triệu 2500" — is rejected as a
///   whole. Reading only "1 triệu" would save a smaller amount without a word.
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
        if let explicit = phrases.last(where: \.isExplicit) {
            chosen = explicit
            value = explicit.value
        } else if let bare = phrases.last, isAtEnd(bare.end, in: chars) {
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

        guard value > 0, value <= UInt64(AmountInput.maximum) else { return nil }
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
    /// Spelled-out digits and tens. After a unit they mean the amount goes on
    /// in words ("1 triệu hai"), which this parser does not read.
    static let numberWords: Set<String> = [
        "một", "mốt", "hai", "ba", "bốn", "tư", "năm", "lăm", "sáu", "bảy", "bẩy",
        "tám", "chín", "mười", "mươi", "linh", "lẻ", "trăm",
    ]

    enum Scanned {
        case phrase(Phrase)
        /// Not a number we understand ("1.2.3"): skip it.
        case notANumber
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
            let startsNumber = isDigit(chars[i]) && (i == 0 || !(chars[i - 1].isLetter || isDigit(chars[i - 1])))
            guard startsNumber else {
                i += 1
                continue
            }
            switch phrase(at: i, in: chars) {
            case .phrase(let phrase):
                phrases.append(phrase)
                i = phrase.end
            case .notANumber:
                while i < chars.count, isDigit(chars[i]) || chars[i] == "." || chars[i] == "," { i += 1 }
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

        guard let unit = units[firstWord.text.lowercased()] else {
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

        // "1 triệu 200 nghìn": each further part must use a smaller unit.
        // "1 triệu 2", "1 triệu 2 trăm": trailing digits with no unit continue the last one.
        while true {
            let nextStart = skipSpaces(from: cursor, in: chars)
            if let tail = group(at: nextStart, in: chars) {
                let tailWord = word(at: skipSpaces(from: tail.end, in: chars), in: chars)
                if let smaller = units[tailWord.text.lowercased()], smaller < lastUnit {
                    guard let part = tail.scaled(by: smaller), let sum = adding(total, part) else { return .unreadable }
                    total = sum
                    lastUnit = smaller
                    cursor = tailWord.end
                    continue
                }
                guard tailWord.text.isEmpty, isPhraseBoundary(tail.end, in: chars) else {
                    // A word follows: "1 triệu 2 thùng" — the 2 is a quantity.
                    break
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
        }
        return .phrase(Phrase(start: start, end: cursor, value: total, isExplicit: true))
    }

    /// Whether a spelled-out number word ending at `index` is part of the
    /// amount: it ends the phrase, or another number word or unit follows.
    static func continuesInWords(after index: Int, in chars: [Character]) -> Bool {
        let following = word(at: skipSpaces(from: index, in: chars), in: chars).text.lowercased()
        if following.isEmpty { return isPhraseBoundary(index, in: chars) }
        return numberWords.contains(following) || units[following] != nil || currencyWords.contains(following)
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
        let product = number.mantissa.multipliedReportingOverflow(by: unit)
        guard !product.overflow else { return nil }
        let divisor = pow10(number.scale)
        return (product.partialValue + divisor / 2) / divisor
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
        return currencyWords.contains(candidate.text.lowercased()) ? candidate.end : nil
    }

    /// Nothing but spaces or punctuation between `index` and the next word.
    /// "1 triệu 2" ends there; "1 triệu 2 thùng" does not.
    static func isPhraseBoundary(_ index: Int, in chars: [Character]) -> Bool {
        let next = skipSpaces(from: index, in: chars)
        return next == chars.count || !(chars[next].isLetter || isDigit(chars[next]))
    }

    static func isAtEnd(_ index: Int, in chars: [Character]) -> Bool {
        chars[index...].allSatisfy { $0.isWhitespace || $0.isPunctuation }
    }

    /// Collapses whitespace and trims separators left behind at either end.
    static func tidy(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let edges: Set<Character> = [",", ";", ":", "-", "–", "—", "=", "."]
        var trimmed = Substring(words)
        while let first = trimmed.first, first.isWhitespace || edges.contains(first) { trimmed.removeFirst() }
        while let last = trimmed.last, last.isWhitespace || edges.contains(last) { trimmed.removeLast() }
        return String(trimmed)
    }
}
