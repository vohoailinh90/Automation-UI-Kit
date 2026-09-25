/// A number said in the largest unit it reaches, Vietnamese style: "12,5k",
/// "1,2tr", "350 MB", "1,5 tỷ". Shared by `VND.compact` and `ByteSize`.
enum DecimalUnits {
    /// - Parameters:
    ///   - magnitude: at least `units[0].size`.
    ///   - units: ascending; each size a multiple of 10. The suffix includes
    ///     any space before it.
    ///
    /// One decimal below 100 of a unit, none from 100 up, ",0" dropped. A
    /// value that rounds up to 1.000 of a unit moves to the next unit
    /// (999.999 → "1tr", not "1.000k"); past the last unit, thousands are
    /// grouped ("1.500 tỷ").
    static func string(_ magnitude: UInt64, units: [(size: UInt64, suffix: String)]) -> String {
        var index = units.lastIndex { magnitude >= $0.size } ?? 0
        while true {
            let unit = units[index]
            let text = roundedTenths(magnitude, of: unit.size)
            if text.tenths >= 10_000, index + 1 < units.count {
                // Rounded up to 1.000 of this unit: say it in the next one.
                index += 1
                continue
            }
            return text.string + unit.suffix
        }
    }

    /// `magnitude / unit` rounded half-up to one decimal, dropping ",0" and
    /// dropping the decimal entirely from 100 units upwards.
    private static func roundedTenths(_ magnitude: UInt64, of unit: UInt64) -> (tenths: UInt64, string: String) {
        // Half-up in integer maths; `unit / 10` is exact for every unit used.
        let tenth = unit / 10
        let tenths = (magnitude + tenth / 2) / tenth
        if tenths >= 1_000 {
            let whole = (magnitude + unit / 2) / unit
            return (whole * 10, VND.grouped(whole))
        }
        let whole = tenths / 10
        let decimal = tenths % 10
        return (tenths, decimal == 0 ? String(whole) : "\(whole),\(decimal)")
    }
}
