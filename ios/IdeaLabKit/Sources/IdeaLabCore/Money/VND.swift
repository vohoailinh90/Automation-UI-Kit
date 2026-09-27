import Foundation

/// Vietnamese đồng, written the Vietnamese way no matter what region the phone
/// is set to: "." groups thousands, "," is the decimal mark, the symbol goes
/// after the number. A shop owner whose iPhone is set to English (US) should
/// still see "450.000 ₫", not "₫450,000", because the paper book, the bank
/// app and the tax form all say "450.000".
///
/// Amounts are whole đồng in `Int64`. VND has no minor unit in daily use, and
/// integers keep sums exact.
///
/// Do not use this for App Store prices: StoreKit already formats those in the
/// buyer's own currency (`Product.displayPrice`).
public enum VND {
    public enum Style: Sendable {
        /// "450.000 ₫" — the default on screen.
        case symbol
        /// "450.000đ" — how receipts and handwritten books write it.
        case suffixD
        /// "450.000" — when the unit is already shown next to the number.
        case plain
        /// "450.000 đồng" — for VoiceOver, which reads "₫" inconsistently.
        case spoken
        /// "bốn trăm năm mươi nghìn đồng" — for a voice to say
        /// (`AVSpeechSynthesizer`), which then never has to guess what the
        /// dots in "450.000" mean; and for a receipt's "bằng chữ" line.
        case words
    }

    /// No-break space: the number and its symbol never wrap onto two lines.
    static let nbsp = "\u{00A0}"
    /// U+2212 MINUS SIGN, as wide as "+" so signed columns line up.
    static let minus = "\u{2212}"

    public static func string(_ amount: Int64, style: Style = .symbol) -> String {
        let sign = amount < 0 ? minus : ""
        let digits = grouped(amount.magnitude)
        switch style {
        case .symbol: return sign + digits + nbsp + "₫"
        case .suffixD: return sign + digits + "đ"
        case .plain: return sign + digits
        case .spoken: return sign + digits + nbsp + "đồng"
        case .words: return words(amount) + " đồng"
        }
    }

    /// "+450.000 ₫" / "−120.000 ₫". Zero gets no sign, nor do words, which
    /// say "âm" for a negative amount and nothing for a positive one.
    public static func signedString(_ amount: Int64, style: Style = .symbol) -> String {
        amount > 0 && style != .words ? "+" + string(amount, style: style) : string(amount, style: style)
    }

    /// The amount in Vietnamese words, by the spell-out rules of Unicode's
    /// CLDR, which Foundation's `NumberFormatter` carries: "bốn trăm năm
    /// mươi nghìn", "hai mươi mốt", "hai mươi tư", "mười lăm", "một trăm lẻ
    /// năm", "một nghìn không trăm lẻ năm", "hai tỷ"; "âm" before a negative
    /// amount. From 10^18 up, far past any book, the rules keep digits.
    static func words(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "vi")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    /// Short form for chart axes and tight badges: "950", "12,5k", "450k",
    /// "1,2tr", "125tr", "1,5 tỷ". One decimal below 100 of a unit, none above;
    /// a value that rounds up to 1.000 of a unit moves to the next unit
    /// (999.999 → "1tr", not "1.000k").
    public static func compact(_ amount: Int64) -> String {
        let sign = amount < 0 ? minus : ""
        let magnitude = amount.magnitude
        guard magnitude >= 1_000 else { return sign + String(magnitude) }
        return sign + DecimalUnits.string(magnitude, units: [
            (1_000, "k"), (1_000_000, "tr"), (1_000_000_000, "\(nbsp)tỷ"),
        ])
    }

    /// "1234567" → "1.234.567".
    static func grouped(_ value: UInt64) -> String {
        let digits = Array(String(value))
        var out = ""
        out.reserveCapacity(digits.count + digits.count / 3)
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { out.append(".") }
            out.append(digit)
        }
        return out
    }
}
