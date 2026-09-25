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
        }
    }

    /// "+450.000 ₫" / "−120.000 ₫". Zero gets no sign.
    public static func signedString(_ amount: Int64, style: Style = .symbol) -> String {
        amount > 0 ? "+" + string(amount, style: style) : string(amount, style: style)
    }

    /// Short form for chart axes and tight badges: "950", "12,5k", "450k",
    /// "1,2tr", "125tr", "1,5 tỷ". One decimal below 100 of a unit, none above;
    /// a value that rounds up to 1.000 of a unit moves to the next unit
    /// (999.999 → "1tr", not "1.000k").
    public static func compact(_ amount: Int64) -> String {
        let sign = amount < 0 ? minus : ""
        let magnitude = amount.magnitude
        guard magnitude >= 1_000 else { return sign + String(magnitude) }

        let units: [(size: UInt64, suffix: String)] = [
            (1_000, "k"), (1_000_000, "tr"), (1_000_000_000, "\(nbsp)tỷ"),
        ]
        var index = units.lastIndex { magnitude >= $0.size } ?? 0
        while true {
            let unit = units[index]
            let text = roundedTenths(magnitude, of: unit.size)
            if text.tenths >= 10_000, index + 1 < units.count {
                // Rounded up to 1.000 of this unit: say it in the next one.
                index += 1
                continue
            }
            return sign + text.string + unit.suffix
        }
    }

    /// `magnitude / unit` rounded half-up to one decimal, dropping ",0" and
    /// dropping the decimal entirely from 100 units upwards.
    private static func roundedTenths(_ magnitude: UInt64, of unit: UInt64) -> (tenths: UInt64, string: String) {
        // Half-up in integer maths; `unit / 10` is exact for 1k/1tr/1tỷ.
        let tenth = unit / 10
        let tenths = (magnitude + tenth / 2) / tenth
        if tenths >= 1_000 {
            let whole = (magnitude + unit / 2) / unit
            return (whole * 10, grouped(whole))
        }
        let whole = tenths / 10
        let decimal = tenths % 10
        return (tenths, decimal == 0 ? String(whole) : "\(whole),\(decimal)")
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
