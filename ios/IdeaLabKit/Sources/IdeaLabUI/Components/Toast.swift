#if os(iOS)
import SwiftUI

/// A short confirmation with an optional action: "Đã lưu khoản thu 450.000 ₫ · Hoàn tác".
public struct LabToastMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var systemImage: String
    public var actionTitle: String?

    public init(id: UUID = UUID(), text: String, systemImage: String = "checkmark.circle.fill", actionTitle: String? = nil) {
        self.id = id
        self.text = text
        self.systemImage = systemImage
        self.actionTitle = actionTitle
    }
}

public extension View {
    /// Shows `message` above the bottom edge — and above any buttons the
    /// screen pins there with `labBottomBar()`, so it never covers them — and
    /// clears it after `duration`.
    ///
    /// With VoiceOver on, the toast is announced and stays until dismissed:
    /// a message that disappears on a timer is a message some users never
    /// get to hear (WCAG 2.2.1, Timing Adjustable).
    func labToast(
        _ message: Binding<LabToastMessage?>,
        duration: Duration = .seconds(4),
        onAction: @escaping (LabToastMessage) -> Void = { _ in }
    ) -> some View {
        modifier(LabToastModifier(message: message, duration: duration, onAction: onAction))
    }

    /// Marks buttons pinned to the bottom edge (the view given to
    /// `safeAreaInset(edge: .bottom)`): a `labToast` over the screen then
    /// shows above them, instead of covering them while they stay in place.
    func labBottomBar() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: LabBottomBarHeight.self, value: proxy.size.height)
            }
        }
    }
}

/// The height of the tallest bar marked with `labBottomBar()` below a toast.
private struct LabBottomBarHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LabToastModifier: ViewModifier {
    @Binding var message: LabToastMessage?
    let duration: Duration
    let onAction: (LabToastMessage) -> Void

    @Environment(\.labTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// Buttons the screen pins to its bottom edge: the toast sits above them.
    @State private var bottomBar: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(LabBottomBarHeight.self) { height in
                // Preferences are delivered during the view update, on the main actor.
                MainActor.assumeIsolated { bottomBar = height }
            }
            .overlay(alignment: .bottom) {
                if let current = message {
                    toast(current)
                        .padding(.horizontal, LabSpacing.md)
                        .padding(.bottom, LabSpacing.xs + bottomBar)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
                        .id(current.id)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: message)
            .task(id: message?.id) {
                guard let current = message else { return }
                AccessibilityNotification.Announcement(current.text).post()
                guard !voiceOverEnabled else { return }
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return  // A newer toast replaced this one.
                }
                if message?.id == current.id { message = nil }
            }
    }

    private func toast(_ current: LabToastMessage) -> some View {
        HStack(spacing: LabSpacing.sm) {
            Image(systemName: current.systemImage)
                .font(.title3)
                .foregroundStyle(theme.text(.positive))
                .accessibilityHidden(true)
            Text(verbatim: current.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = current.actionTitle {
                Button {
                    onAction(current)
                    message = nil
                } label: {
                    Text(verbatim: actionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                message = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(theme.secondaryLabel)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Đóng thông báo"))
        }
        .padding(.leading, LabSpacing.md)
        .padding(.trailing, LabSpacing.xxs)
        .padding(.vertical, LabSpacing.xxs)
        // Solid, not glass: the text must stay readable over any content.
        .background(theme.surface, in: RoundedRectangle(cornerRadius: LabRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LabRadius.lg, style: .continuous).strokeBorder(theme.separator)
        }
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
    }
}
#endif
