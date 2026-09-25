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
///
/// Anything that would be 0 or above `AmountInput.maximum` returns `nil`
/// rather than a guess.
public enum AmountParser {
    public static func parse(_ text: String) -> ParsedAmount? {
        let chars = Array(text)
        let phrases = scan(chars)

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

    static func scan(_ chars: [Character]) -> [Phrase] {
        var phrases: [Phrase] = []
        var i = 0
        while i < chars.count {
            let startsNumber = isDigit(chars[i]) && (i == 0 || !(chars[i - 1].isLetter || isDigit(chars[i - 1])))
            if startsNumber, let phrase = phrase(at: i, in: chars) {
                phrases.append(phrase)
                i = phrase.end
            } else if startsNumber {
                // Not a number we understand ("1.2.3"): skip the whole run.
                while i < chars.count, isDigit(chars[i]) || chars[i] == "." || chars[i] == "," { i += 1 }
            } else {
                i += 1
            }
        }
        return phrases
    }

    static func phrase(at start: Int, in chars: [Character]) -> Phrase? {
        guard let first = number(at: start, in: chars) else { return nil }

        var cursor = first.end
        let afterSpaces = skipSpaces(from: cursor, in: chars)
        let firstWord = word(at: afterSpaces, in: chars)

        guard let unit = units[firstWord.text.lowercased()] else {
            // No magnitude word. A currency word or ₫ still marks it as money.
            var isExplicit = first.isGrouped
            if let currencyEnd = currency(at: afterSpaces, in: chars) {
                cursor = currencyEnd
                isExplicit = true
            }
            guard let value = scaled(first, by: 1) else { return nil }
            let isBelowThousand = first.mantissa < 1_000 * pow10(first.scale)
            return Phrase(
                start: start, end: cursor, value: value, isExplicit: isExplicit,
                valueInThousands: isExplicit || !isBelowThousand ? nil : scaled(first, by: 1_000)
            )
        }

        guard var total = scaled(first, by: unit) else { return nil }
        cursor = firstWord.end
        var lastUnit = unit

        // "1 triệu 200 nghìn": each further part must use a smaller unit.
        // "1 triệu 2": trailing digits with no unit continue the last one.
        while true {
            let nextStart = skipSpaces(from: cursor, in: chars)
            if let tail = number(at: nextStart, in: chars), tail.isPlainInteger {
                let tailWord = word(at: skipSpaces(from: tail.end, in: chars), in: chars)
                if let smaller = units[tailWord.text.lowercased()], smaller < lastUnit {
                    guard let part = scaled(tail, by: smaller) else { return nil }
                    total += part
                    lastUnit = smaller
                    cursor = tailWord.end
                    continue
                }
                if tailWord.text.isEmpty, tail.digitCount <= 3, isPhraseBoundary(tail.end, in: chars) {
                    total += tail.mantissa * (lastUnit / pow10(tail.digitCount))
                    cursor = tail.end
                }
                break
            }
            let halfWord = word(at: nextStart, in: chars)
            if halfWords.contains(halfWord.text.lowercased()) {
                total += lastUnit / 2
                cursor = halfWord.end
            }
            break
        }

        if let currencyEnd = currency(at: skipSpaces(from: cursor, in: chars), in: chars) {
            cursor = currencyEnd
        }
        return Phrase(start: start, end: cursor, value: total, isExplicit: true)
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
