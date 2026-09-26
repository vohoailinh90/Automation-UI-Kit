#if os(iOS)
import SwiftUI

/// Three-to-four page welcome: one idea per page, a big symbol, one button.
/// "Bỏ qua" is always there — onboarding that cannot be skipped is a wall.
public struct OnboardingScreen: View {
    public struct Page: Identifiable, Hashable, Sendable {
        public var systemImage: String
        public var title: String
        public var message: String
        public var id: String { title }

        public init(systemImage: String, title: String, message: String) {
            self.systemImage = systemImage
            self.title = title
            self.message = message
        }
    }

    private let pages: [Page]
    private let onFinish: () -> Void
    @State private var index = 0
    @Environment(\.labTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pages: [Page], onFinish: @escaping () -> Void) {
        precondition(!pages.isEmpty, "OnboardingScreen needs at least one page")
        self.pages = pages
        self.onFinish = onFinish
    }

    private var isLast: Bool { index >= pages.count - 1 }

    public var body: some View {
        VStack(spacing: LabSpacing.lg) {
            HStack {
                Spacer()
                if !isLast {
                    Button("Bỏ qua") { onFinish() }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            .frame(minHeight: 44)

            TabView(selection: $index) {
                ForEach(pages.indices, id: \.self) { i in
                    page(pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: pages.count, index: index)

            Button {
                if isLast {
                    onFinish()
                } else if reduceMotion {
                    index += 1
                } else {
                    withAnimation(.snappy) { index += 1 }
                }
            } label: {
                Text(isLast ? "Bắt đầu" : "Tiếp tục")
            }
            .buttonStyle(.labFilled)
        }
        .padding(.horizontal, LabSpacing.lg)
        .padding(.bottom, LabSpacing.md)
        .background(theme.canvas.ignoresSafeArea())
    }

    private func page(_ page: Page) -> some View {
        VStack(spacing: LabSpacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: page.systemImage)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(theme.accentText)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: index)
                .frame(width: 168, height: 168)
                .background(theme.tonalFill(.accent), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: LabSpacing.sm) {
                Text(verbatim: page.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: page.message)
                    .font(.body)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LabSpacing.xs)
    }
}

/// Page indicator that VoiceOver can read ("Trang 2 trên 3"). The system
/// page dots are hard to see on light backgrounds.
private struct PageDots: View {
    let count: Int
    let index: Int
    @Environment(\.labTheme) private var theme

    var body: some View {
        HStack(spacing: LabSpacing.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? theme.accentText : theme.separator)
                    .frame(width: i == index ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Trang \(index + 1) trên \(count)"))
    }
}
#endif
