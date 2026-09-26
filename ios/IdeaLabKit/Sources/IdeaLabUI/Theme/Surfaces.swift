#if os(iOS)
import SwiftUI

public extension View {
    /// Liquid Glass on iOS 26 and later, a system material before that.
    ///
    /// Glass is for the layer that floats *above* content — a bottom action
    /// tray, a floating button — never for the content itself (Apple HIG,
    /// "Materials"). Cards stay solid: text on glass changes contrast with
    /// whatever scrolls underneath, and these apps are read by older eyes.
    @ViewBuilder
    func labGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Solid rounded card on the theme's surface colour.
    func labCard(padding: CGFloat = LabSpacing.md) -> some View {
        modifier(LabCardModifier(padding: padding))
    }
}

private struct LabCardModifier: ViewModifier {
    let padding: CGFloat
    @Environment(\.labTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: LabRadius.lg, style: .continuous))
            // A soft lift in light mode; dark mode separates by surface colour alone.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 12, x: 0, y: 4)
    }
}

/// A card title with an optional trailing action ("Xem tất cả").
public struct LabSectionHeader<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let trailing: Trailing
    @Environment(\.labTheme) private var theme

    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.label)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: LabSpacing.xs)
            trailing
                .font(.subheadline.weight(.semibold))
        }
    }
}

public extension LabSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}
#endif
