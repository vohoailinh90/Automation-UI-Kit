/// One colour role in its four appearances. High-contrast values are optional:
/// when absent, "Increase Contrast" falls back to the normal value.
public struct Swatch: Hashable, Sendable {
    public var light: RGB
    public var dark: RGB
    public var lightHighContrast: RGB?
    public var darkHighContrast: RGB?

    public init(light: RGB, dark: RGB, lightHighContrast: RGB? = nil, darkHighContrast: RGB? = nil) {
        self.light = light
        self.dark = dark
        self.lightHighContrast = lightHighContrast
        self.darkHighContrast = darkHighContrast
    }

    public init(light: UInt32, dark: UInt32, lightHighContrast: UInt32? = nil, darkHighContrast: UInt32? = nil) {
        self.init(
            light: RGB(light),
            dark: RGB(dark),
            lightHighContrast: lightHighContrast.map(RGB.init),
            darkHighContrast: darkHighContrast.map(RGB.init)
        )
    }

    /// A role that looks the same in every appearance (e.g. white text on a fill).
    public init(_ both: UInt32) {
        self.init(light: both, dark: both)
    }

    public func resolve(dark: Bool, highContrast: Bool) -> RGB {
        switch (dark, highContrast) {
        case (false, false): light
        case (false, true): lightHighContrast ?? light
        case (true, false): self.dark
        case (true, true): darkHighContrast ?? self.dark
        }
    }
}

/// Semantic colours for one app. Components never pick a hex value themselves;
/// they ask for a role, so re-theming an app is one `LabPalette` away.
///
/// Every text role is at least 4.5:1 against every background role, in light,
/// dark and both high-contrast modes, and every fill is at least 4.5:1 against
/// the text drawn on it. `PaletteContrastTests` enforces this for the shipped
/// palettes, so a tweak that breaks it fails CI instead of shipping.
public struct LabPalette: Hashable, Sendable {
    // Backgrounds
    /// Screen background behind cards (grouped background).
    public var canvas: Swatch
    /// Cards, sheets, list rows.
    public var surface: Swatch
    /// Insets inside a surface: keypad keys, segmented tracks, chips.
    public var surfaceSecondary: Swatch

    // Text on backgrounds
    public var label: Swatch
    public var secondaryLabel: Swatch
    /// Brand colour when used as text or an outline on a background: links, tinted icons.
    public var accentText: Swatch
    /// Money in, dose taken, photo kept.
    public var positive: Swatch
    /// Money out, dose missed, photo deleted.
    public var negative: Swatch
    public var warning: Swatch

    // Fills and the text drawn on them
    /// Brand colour as a filled button.
    public var accent: Swatch
    public var positiveFill: Swatch
    public var negativeFill: Swatch
    /// Text and icons on `accent`, `positiveFill` and `negativeFill`.
    public var onFill: Swatch
    /// Amber attention fill. Amber never reaches 4.5:1 as text on white, so it
    /// is only ever a fill, with dark text on top.
    public var warningFill: Swatch
    public var onWarningFill: Swatch

    /// Hairlines between rows. Decorative, so it has no contrast requirement.
    public var separator: Swatch

    public init(
        canvas: Swatch, surface: Swatch, surfaceSecondary: Swatch,
        label: Swatch, secondaryLabel: Swatch, accentText: Swatch,
        positive: Swatch, negative: Swatch, warning: Swatch,
        accent: Swatch, positiveFill: Swatch, negativeFill: Swatch, onFill: Swatch,
        warningFill: Swatch, onWarningFill: Swatch, separator: Swatch
    ) {
        self.canvas = canvas
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.accentText = accentText
        self.positive = positive
        self.negative = negative
        self.warning = warning
        self.accent = accent
        self.positiveFill = positiveFill
        self.negativeFill = negativeFill
        self.onFill = onFill
        self.warningFill = warningFill
        self.onWarningFill = onWarningFill
        self.separator = separator
    }

    /// A pale, opaque version of `fill` sitting on `surface`: chips, the
    /// selected segment track, tonal buttons. It is opaque on purpose — a
    /// translucent tint would change contrast depending on what is behind it,
    /// and on the grey canvas the ledger blue drops below 4.5:1.
    ///
    /// Pair it with the matching text role: `accentText` on `tonal(\.accent)`,
    /// `positive` on `tonal(\.positiveFill)`, `negative` on `tonal(\.negativeFill)`.
    public func tonal(_ fill: KeyPath<LabPalette, Swatch>) -> Swatch {
        let tint = self[keyPath: fill]
        func mix(_ top: RGB, _ bottom: RGB, dark: Bool) -> RGB {
            top.composited(over: bottom, opacity: dark ? Self.tonalDarkOpacity : Self.tonalLightOpacity)
        }
        return Swatch(
            light: mix(tint.light, surface.light, dark: false),
            dark: mix(tint.dark, surface.dark, dark: true),
            lightHighContrast: mix(tint.resolve(dark: false, highContrast: true), surface.resolve(dark: false, highContrast: true), dark: false),
            darkHighContrast: mix(tint.resolve(dark: true, highContrast: true), surface.resolve(dark: true, highContrast: true), dark: true)
        )
    }

    /// Dark surfaces need a stronger tint before it reads as colour at all.
    public static let tonalLightOpacity = 0.12
    public static let tonalDarkOpacity = 0.24

    /// The neutral base every app shares, with its own brand colour on top.
    /// `accent` is the fill (white text on it), `accentText` the same hue tuned
    /// to read as text: in dark mode one colour cannot do both jobs, since a
    /// blue light enough for text on #1C1C1E is too light to carry white text.
    public static func standard(accent: Swatch, accentText: Swatch) -> LabPalette {
        LabPalette(
            canvas: Swatch(light: 0xF2F2F7, dark: 0x000000),
            surface: Swatch(light: 0xFFFFFF, dark: 0x1C1C1E),
            surfaceSecondary: Swatch(light: 0xEBEBF0, dark: 0x2C2C2E),
            label: Swatch(light: 0x0F1115, dark: 0xF5F5F7, lightHighContrast: 0x000000, darkHighContrast: 0xFFFFFF),
            // iOS's own secondaryLabel is ~3.4:1 on white: fine for hints,
            // too faint for the older users these apps are built for.
            secondaryLabel: Swatch(light: 0x5C5C66, dark: 0xAEAEB5, lightHighContrast: 0x3A3A42, darkHighContrast: 0xD1D1D6),
            accentText: accentText,
            positive: Swatch(light: 0x137333, dark: 0x3DD56D, lightHighContrast: 0x0B5A26, darkHighContrast: 0x6BE38F),
            negative: Swatch(light: 0xB3261E, dark: 0xFF6B61, lightHighContrast: 0x8C1D18, darkHighContrast: 0xFF8F87),
            warning: Swatch(light: 0x8A5300, dark: 0xFFB340, lightHighContrast: 0x6B4000, darkHighContrast: 0xFFC56B),
            accent: accent,
            positiveFill: Swatch(light: 0x14803E, dark: 0x14803E, lightHighContrast: 0x0B5A26, darkHighContrast: 0x0B5A26),
            negativeFill: Swatch(light: 0xC8281E, dark: 0xC8281E, lightHighContrast: 0x8C1D18, darkHighContrast: 0x8C1D18),
            onFill: Swatch(0xFFFFFF),
            warningFill: Swatch(0xFFB020),
            onWarningFill: Swatch(0x1F1400),
            separator: Swatch(light: 0xD1D1D6, dark: 0x38383A, lightHighContrast: 0x8E8E93, darkHighContrast: 0x8E8E93)
        )
    }

    /// Sổ thu chi: a bank-like blue, so green and red stay free to mean money in and out.
    public static let ledger = standard(
        accent: Swatch(light: 0x0B5FD0, dark: 0x1F6FE0, lightHighContrast: 0x0A4DA8, darkHighContrast: 0x0A4DA8),
        accentText: Swatch(light: 0x0B5FD0, dark: 0x6AA6FF, lightHighContrast: 0x0A4DA8, darkHighContrast: 0x9CC3FF)
    )

    /// Nhắc thuốc: a calm teal that reads as health without borrowing "danger" red.
    public static let meds = standard(
        accent: Swatch(light: 0x00756D, dark: 0x00756D, lightHighContrast: 0x005A54, darkHighContrast: 0x005A54),
        accentText: Swatch(light: 0x00756D, dark: 0x4FD1C5, lightHighContrast: 0x005A54, darkHighContrast: 0x8BE3DA)
    )

    /// Dọn ảnh: violet for the "smart" feel of on-device AI.
    public static let cleaner = standard(
        accent: Swatch(light: 0x6236D8, dark: 0x7047E6, lightHighContrast: 0x4B22B8, darkHighContrast: 0x4B22B8),
        accentText: Swatch(light: 0x6236D8, dark: 0xB39DFF, lightHighContrast: 0x4B22B8, darkHighContrast: 0xCFC2FF)
    )
}
