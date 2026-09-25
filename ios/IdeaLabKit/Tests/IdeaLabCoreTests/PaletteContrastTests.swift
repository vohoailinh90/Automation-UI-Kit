import IdeaLabCore
import Testing

/// The palette's promises, checked for every shipped app, in light, dark and
/// both Increase Contrast variants. A colour tweak that breaks one fails here.
@Suite("Palette contrast")
struct PaletteContrastTests {
    static let palettes: [(name: String, palette: LabPalette)] = [
        ("ledger", .ledger), ("meds", .meds), ("cleaner", .cleaner),
    ]
    static let modes: [(dark: Bool, highContrast: Bool)] = [
        (false, false), (true, false), (false, true), (true, true),
    ]

    struct Pair: CustomStringConvertible {
        let text: String
        let background: String
        let ratio: Double
        var description: String { "\(text) on \(background): \(ratio)" }
    }

    /// Every (text, background) ratio for one palette in one mode.
    static func ratios(
        _ palette: LabPalette, dark: Bool, highContrast: Bool,
        texts: [(String, Swatch)], backgrounds: [(String, Swatch)]
    ) -> [Pair] {
        texts.flatMap { text in
            backgrounds.map { background in
                let fg = text.1.resolve(dark: dark, highContrast: highContrast)
                let bg = background.1.resolve(dark: dark, highContrast: highContrast)
                return Pair(text: text.0, background: background.0, ratio: fg.contrastRatio(with: bg))
            }
        }
    }

    static func textRoles(_ p: LabPalette) -> [(String, Swatch)] {
        [("label", p.label), ("secondaryLabel", p.secondaryLabel), ("accentText", p.accentText),
         ("positive", p.positive), ("negative", p.negative), ("warning", p.warning)]
    }

    static func backgrounds(_ p: LabPalette) -> [(String, Swatch)] {
        [("canvas", p.canvas), ("surface", p.surface), ("surfaceSecondary", p.surfaceSecondary)]
    }

    @Test("Text roles reach 4.5:1 on every background", arguments: palettes.indices, modes.indices)
    func textOnBackgrounds(paletteIndex: Int, modeIndex: Int) {
        let palette = Self.palettes[paletteIndex].palette
        let mode = Self.modes[modeIndex]
        let pairs = Self.ratios(palette, dark: mode.dark, highContrast: mode.highContrast,
                                texts: Self.textRoles(palette), backgrounds: Self.backgrounds(palette))
        #expect(pairs.count == 18)
        for pair in pairs {
            #expect(pair.ratio >= 4.5, "\(Self.palettes[paletteIndex].name) \(mode): \(pair)")
        }
    }

    @Test("Body text reaches AAA 7:1", arguments: palettes.indices, modes.indices)
    func labelIsAAA(paletteIndex: Int, modeIndex: Int) {
        let palette = Self.palettes[paletteIndex].palette
        let mode = Self.modes[modeIndex]
        let pairs = Self.ratios(palette, dark: mode.dark, highContrast: mode.highContrast,
                                texts: [("label", palette.label)], backgrounds: Self.backgrounds(palette))
        for pair in pairs {
            #expect(pair.ratio >= 7, "\(Self.palettes[paletteIndex].name) \(mode): \(pair)")
        }
    }

    @Test("Text on fills reaches 4.5:1", arguments: palettes.indices, modes.indices)
    func textOnFills(paletteIndex: Int, modeIndex: Int) {
        let palette = Self.palettes[paletteIndex].palette
        let mode = Self.modes[modeIndex]
        var pairs = Self.ratios(palette, dark: mode.dark, highContrast: mode.highContrast,
                                texts: [("onFill", palette.onFill)],
                                backgrounds: [("accent", palette.accent), ("positiveFill", palette.positiveFill),
                                              ("negativeFill", palette.negativeFill)])
        pairs += Self.ratios(palette, dark: mode.dark, highContrast: mode.highContrast,
                             texts: [("onWarningFill", palette.onWarningFill)],
                             backgrounds: [("warningFill", palette.warningFill)])
        #expect(pairs.count == 4)
        for pair in pairs {
            #expect(pair.ratio >= 4.5, "\(Self.palettes[paletteIndex].name) \(mode): \(pair)")
        }
    }

    @Test("Tinted text reaches 4.5:1 on its own tonal fill", arguments: palettes.indices, modes.indices)
    func tonalPairs(paletteIndex: Int, modeIndex: Int) {
        let palette = Self.palettes[paletteIndex].palette
        let mode = Self.modes[modeIndex]
        let pairs: [(String, Swatch, Swatch)] = [
            ("accentText", palette.accentText, palette.tonal(\.accent)),
            ("positive", palette.positive, palette.tonal(\.positiveFill)),
            ("negative", palette.negative, palette.tonal(\.negativeFill)),
        ]
        for (name, text, fill) in pairs {
            let ratio = text.resolve(dark: mode.dark, highContrast: mode.highContrast)
                .contrastRatio(with: fill.resolve(dark: mode.dark, highContrast: mode.highContrast))
            #expect(ratio >= 4.5, "\(Self.palettes[paletteIndex].name) \(mode): \(name) on its tonal fill: \(ratio)")
        }
    }

    @Test("Increase Contrast never lowers contrast", arguments: palettes.indices, [false, true])
    func highContrastIsNotWorse(paletteIndex: Int, dark: Bool) {
        let palette = Self.palettes[paletteIndex].palette
        let normal = Self.ratios(palette, dark: dark, highContrast: false,
                                 texts: Self.textRoles(palette), backgrounds: Self.backgrounds(palette))
        let high = Self.ratios(palette, dark: dark, highContrast: true,
                               texts: Self.textRoles(palette), backgrounds: Self.backgrounds(palette))
        for (before, after) in zip(normal, high) {
            #expect(after.ratio >= before.ratio, "\(Self.palettes[paletteIndex].name) dark=\(dark): \(before) → \(after)")
        }
    }

    @Test("Tonal fills are opaque, pale versions of their fill")
    func tonalIsBetweenFillAndSurface() {
        let palette = LabPalette.ledger
        let tonal = palette.tonal(\.accent)
        // 12% of #0B5FD0 over white, per channel, rounded: 225.72, 235.8, 249.36.
        #expect(tonal.light == RGB(0xE2ECF9))
        // Dark mode uses a stronger 24% tint of #1F6FE0 over #1C1C1E: 28.72, 47.92, 76.56.
        #expect(tonal.dark == RGB(0x1D304D))
    }

    @Test("Amber only works as a fill, which is why warning text has its own role")
    func amberFailsAsText() {
        let amber = LabPalette.ledger.warningFill.light
        #expect(amber.contrastRatio(with: RGB(0xFFFFFF)) < 3)
    }
}

@Suite("WCAG maths")
struct RGBTests {
    @Test func blackOnWhiteIs21() {
        #expect(abs(RGB(0x000000).contrastRatio(with: RGB(0xFFFFFF)) - 21) < 1e-9)
    }

    @Test func contrastIsSymmetricAndOneForSameColour() {
        let a = RGB(0x0B5FD0), b = RGB(0xF2F2F7)
        #expect(a.contrastRatio(with: b) == b.contrastRatio(with: a))
        #expect(a.contrastRatio(with: a) == 1)
    }

    @Test("#767676 is the lightest grey that passes 4.5:1 on white")
    func knownGreys() {
        #expect(RGB(0x767676).contrastRatio(with: RGB(0xFFFFFF)) >= 4.5)
        #expect(RGB(0x777777).contrastRatio(with: RGB(0xFFFFFF)) < 4.5)
    }

    @Test func compositing() {
        #expect(RGB(0x000000).composited(over: RGB(0xFFFFFF), opacity: 0.5) == RGB(0x808080))
        #expect(RGB(0x123456).composited(over: RGB(0xABCDEF), opacity: 1) == RGB(0x123456))
        #expect(RGB(0x123456).composited(over: RGB(0xABCDEF), opacity: 0) == RGB(0xABCDEF))
        // Out-of-range opacity is clamped rather than extrapolated.
        #expect(RGB(0x123456).composited(over: RGB(0xABCDEF), opacity: 2) == RGB(0x123456))
    }

    @Test func description() {
        #expect(RGB(0x0B5FD0).description == "#0B5FD0")
        #expect(RGB(0x000001).description == "#000001")
    }
}
