#if os(iOS)
import SwiftUI

/// Filled, full-width button: the one primary action of a screen ("Lưu",
/// "Tiếp tục"). Replaces `.borderedProminent`, whose white-on-tint label
/// cannot reach 4.5:1 in dark mode with a text-safe tint.
public struct LabFilledButtonStyle: ButtonStyle {
    public enum Size: Sendable {
        /// `LabDensity.controlHeight` tall, headline text.
        case regular
        /// `LabDensity.heroHeight` tall, for the action a screen exists for.
        case hero
    }

    public var tint: LabTint
    public var size: Size

    public init(tint: LabTint = .accent, size: Size = .regular) {
        self.tint = tint
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        FilledBody(configuration: configuration, tint: tint, size: size)
    }

    private struct FilledBody: View {
        let configuration: Configuration
        let tint: LabTint
        let size: Size
        @Environment(\.labTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: size == .hero ? LabRadius.lg : LabRadius.md, style: .continuous)
            configuration.label
                .font(size == .hero ? .title3.weight(.bold) : .headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.onFill)
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.xs)
                .frame(maxWidth: .infinity, minHeight: size == .hero ? theme.density.heroHeight : theme.density.controlHeight)
                .background(theme.fill(tint), in: shape)
                .contentShape(shape)
                // Disabled controls are exempt from contrast rules; dimming is
                // the conventional signal and keeps the label readable.
                .opacity(isEnabled ? 1 : 0.4)
                .brightness(configuration.isPressed ? -0.08 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

/// Pale tinted button for secondary actions ("Xuất PDF", "Khôi phục mua hàng").
public struct LabTonalButtonStyle: ButtonStyle {
    public var tint: LabTint

    public init(tint: LabTint = .accent) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        TonalBody(configuration: configuration, tint: tint)
    }

    private struct TonalBody: View {
        let configuration: Configuration
        let tint: LabTint
        @Environment(\.labTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous)
            configuration.label
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text(tint))
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.xs)
                .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
                .background(theme.tonalFill(tint), in: shape)
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

public extension ButtonStyle where Self == LabFilledButtonStyle {
    static var labFilled: LabFilledButtonStyle { LabFilledButtonStyle() }

    static func labFilled(_ tint: LabTint, size: LabFilledButtonStyle.Size = .regular) -> LabFilledButtonStyle {
        LabFilledButtonStyle(tint: tint, size: size)
    }
}

public extension ButtonStyle where Self == LabTonalButtonStyle {
    static var labTonal: LabTonalButtonStyle { LabTonalButtonStyle() }

    static func labTonal(_ tint: LabTint) -> LabTonalButtonStyle { LabTonalButtonStyle(tint: tint) }
}

/// The big square-ish button a screen is built around: "Thu" / "Chi",
/// "ĐÃ UỐNG". Icon above a bold title, hero height, a haptic on every press.
public struct BigActionButton: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let systemImage: String
    private let tint: LabTint
    private let action: () -> Void
    @State private var presses = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tint: LabTint = .accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button {
            presses += 1
            action()
        } label: {
            VStack(spacing: LabSpacing.xxs) {
                Image(systemName: systemImage)
                    .font(.title.weight(.bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.weight(.bold))
                // At accessibility sizes the title alone already fills the
                // button; the subtitle would only push content off screen.
                if let subtitle, !typeSize.isAccessibilitySize {
                    Text(subtitle)
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(.vertical, LabSpacing.xs)
        }
        .buttonStyle(.labFilled(tint, size: .hero))
        .sensoryFeedback(.impact(weight: .medium), trigger: presses)
    }
}
#endif
