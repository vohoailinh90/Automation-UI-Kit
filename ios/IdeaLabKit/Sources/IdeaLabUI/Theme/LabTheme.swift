#if os(iOS)
import IdeaLabCore
import SwiftUI
import UIKit

/// How roomy controls are.
public enum LabDensity: Hashable, Sendable {
    /// HIG sizes with a little extra room.
    case regular
    /// For apps whose main users are older: bigger targets and a floor on text size.
    case senior

    /// Minimum height of an ordinary tappable control. The HIG minimum is 44 pt.
    public var controlHeight: CGFloat { self == .senior ? 60 : 50 }

    /// Minimum height of the one action a screen exists for ("Thu", "ĐÃ UỐNG").
    /// Studies with older adults found 14–17.5 mm targets worked best, roughly
    /// 84–100 pt on an iPhone, hence 96 pt in senior mode.
    public var heroHeight: CGFloat { self == .senior ? 96 : 84 }

    /// Smallest Dynamic Type size allowed; `nil` follows the system setting.
    public var minimumTypeSize: DynamicTypeSize? { self == .senior ? .xLarge : nil }
}

/// The look of one app: its palette plus its density.
public struct LabTheme: Hashable, Sendable {
    public var palette: LabPalette
    public var density: LabDensity

    public init(palette: LabPalette, density: LabDensity = .regular) {
        self.palette = palette
        self.density = density
    }

    public static let ledger = LabTheme(palette: .ledger)
    public static let meds = LabTheme(palette: .meds, density: .senior)
    public static let cleaner = LabTheme(palette: .cleaner)
}

/// Which semantic colour a control carries.
public enum LabTint: Hashable, Sendable {
    case accent
    case positive
    case negative

    /// Thu is positive, Chi is negative.
    public init(_ kind: LedgerEntry.Kind) {
        self = kind == .income ? .positive : .negative
    }
}

public extension LabTheme {
    var canvas: Color { Color(swatch: palette.canvas) }
    var surface: Color { Color(swatch: palette.surface) }
    var surfaceSecondary: Color { Color(swatch: palette.surfaceSecondary) }
    var label: Color { Color(swatch: palette.label) }
    var secondaryLabel: Color { Color(swatch: palette.secondaryLabel) }
    var separator: Color { Color(swatch: palette.separator) }
    var accentText: Color { Color(swatch: palette.accentText) }
    var onFill: Color { Color(swatch: palette.onFill) }
    var warning: Color { Color(swatch: palette.warning) }
    var warningFill: Color { Color(swatch: palette.warningFill) }
    var onWarningFill: Color { Color(swatch: palette.onWarningFill) }

    /// Solid fill for a filled button or badge; `onFill` goes on top.
    func fill(_ tint: LabTint) -> Color {
        switch tint {
        case .accent: Color(swatch: palette.accent)
        case .positive: Color(swatch: palette.positiveFill)
        case .negative: Color(swatch: palette.negativeFill)
        }
    }

    /// Pale opaque fill for chips and tonal buttons; `text(tint)` goes on top.
    func tonalFill(_ tint: LabTint) -> Color {
        switch tint {
        case .accent: Color(swatch: palette.tonal(\.accent))
        case .positive: Color(swatch: palette.tonal(\.positiveFill))
        case .negative: Color(swatch: palette.tonal(\.negativeFill))
        }
    }

    /// The tint as text or an icon on `surface`, `canvas` or `tonalFill(tint)`.
    func text(_ tint: LabTint) -> Color {
        switch tint {
        case .accent: accentText
        case .positive: Color(swatch: palette.positive)
        case .negative: Color(swatch: palette.negative)
        }
    }
}

public extension Color {
    /// A colour that follows light/dark mode and Increase Contrast, like the
    /// system's own dynamic colours do.
    init(swatch: Swatch) {
        self.init(uiColor: UIColor { traits in
            let rgb = swatch.resolve(
                dark: traits.userInterfaceStyle == .dark,
                highContrast: traits.accessibilityContrast == .high
            )
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

private struct LabThemeKey: EnvironmentKey {
    static let defaultValue = LabTheme.ledger
}

public extension EnvironmentValues {
    var labTheme: LabTheme {
        get { self[LabThemeKey.self] }
        set { self[LabThemeKey.self] = newValue }
    }
}

public extension View {
    /// Puts `theme` in the environment, tints system controls (links, toggles,
    /// the text cursor) with its accent, and in senior density raises the floor
    /// on Dynamic Type.
    ///
    /// The tint is `accentText`, not the fill: system prominent buttons would
    /// put white text on it, which fails contrast in dark mode. Use
    /// `.buttonStyle(.labFilled)` for filled buttons instead of `.borderedProminent`.
    func labTheme(_ theme: LabTheme) -> some View {
        modifier(LabThemeModifier(theme: theme))
    }
}

private struct LabThemeModifier: ViewModifier {
    let theme: LabTheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let themed = content
            .environment(\.labTheme, theme)
            .tint(theme.accentText)
        if let minimum = theme.density.minimumTypeSize {
            themed.dynamicTypeSize(minimum...)
        } else {
            themed
        }
    }
}

/// 4-pt grid.
public enum LabSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

/// Continuous ("squircle") corner radii, matching iOS's own rounded shapes.
public enum LabRadius {
    public static let sm: CGFloat = 10
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 22
    public static let xl: CGFloat = 32
}
#endif
