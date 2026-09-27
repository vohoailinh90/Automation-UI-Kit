#if os(iOS)
import SwiftUI

/// Explains *why* before iOS asks. The system prompt can be shown only once;
/// a "Don't Allow" there is hard to undo, so the app gets one fair chance to
/// explain first. Apple's Guideline 5.1.1 also expects the purpose to be clear.
///
/// "Cho phép" should trigger the real system request; "Để sau" must leave the
/// app usable (ask again at the moment the feature is needed).
///
/// An `example` shows what the permission brings — for notifications, one of
/// the app's own alerts (`DoseAlertBanner`) — under the title.
public struct PermissionPrimerScreen: View {
    public struct Reason: Identifiable, Hashable, Sendable {
        public var systemImage: String
        public var text: String
        public var id: String { text }

        public init(systemImage: String, text: String) {
            self.systemImage = systemImage
            self.text = text
        }
    }

    private let systemImage: String
    private let title: String
    private let message: String
    private let reasons: [Reason]
    private let allowTitle: String
    private let onAllow: () -> Void
    private let onLater: () -> Void
    private let example: AnyView?
    @Environment(\.labTheme) private var theme

    public init(
        systemImage: String,
        title: String,
        message: String,
        reasons: [Reason],
        allowTitle: String = "Cho phép",
        onAllow: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        self.init(
            systemImage: systemImage, title: title, message: message, reasons: reasons, allowTitle: allowTitle,
            onAllow: onAllow, onLater: onLater, anyExample: nil
        )
    }

    /// With an example of what the permission brings, under the title.
    public init<Example: View>(
        systemImage: String,
        title: String,
        message: String,
        reasons: [Reason],
        allowTitle: String = "Cho phép",
        onAllow: @escaping () -> Void,
        onLater: @escaping () -> Void,
        @ViewBuilder example: () -> Example
    ) {
        self.init(
            systemImage: systemImage, title: title, message: message, reasons: reasons, allowTitle: allowTitle,
            onAllow: onAllow, onLater: onLater, anyExample: AnyView(example())
        )
    }

    private init(
        systemImage: String,
        title: String,
        message: String,
        reasons: [Reason],
        allowTitle: String,
        onAllow: @escaping () -> Void,
        onLater: @escaping () -> Void,
        anyExample: AnyView?
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.reasons = reasons
        self.allowTitle = allowTitle
        self.onAllow = onAllow
        self.onLater = onLater
        self.example = anyExample
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(theme.onFill)
                    .frame(width: 104, height: 104)
                    .background(theme.fill(.accent), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .accessibilityHidden(true)
                    .padding(.top, LabSpacing.xl)

                VStack(spacing: LabSpacing.sm) {
                    Text(verbatim: title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(theme.label)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: message)
                        .font(.body)
                        .foregroundStyle(theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                }

                if let example {
                    example
                }

                VStack(alignment: .leading, spacing: LabSpacing.md) {
                    ForEach(reasons) { reason in
                        HStack(alignment: .top, spacing: LabSpacing.sm) {
                            Image(systemName: reason.systemImage)
                                .font(.headline)
                                .foregroundStyle(theme.accentText)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            Text(verbatim: reason.text)
                                .font(.body)
                                .foregroundStyle(theme.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .labCard()
            }
            .padding(.horizontal, LabSpacing.md)
        }
        .background(theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: LabSpacing.xs) {
                Button {
                    onAllow()
                } label: {
                    Text(verbatim: allowTitle)
                }
                .buttonStyle(.labFilled)
                Button {
                    onLater()
                } label: {
                    Text(verbatim: "Để sau")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentText)
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.xs)
            .background(theme.canvas)
            .labBottomBar()
        }
    }
}
#endif
