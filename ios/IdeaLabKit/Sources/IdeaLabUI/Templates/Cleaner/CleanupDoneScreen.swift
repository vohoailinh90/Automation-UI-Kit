#if os(iOS)
import IdeaLabCore
import SwiftUI

/// After the deletion: the result, big and plain, and the one fact most
/// cleaner apps leave out — iOS keeps deleted photos and videos in "Đã xoá gần
/// đây" for 30 days, so the space only comes back once that album is emptied.
/// Saying so keeps the number honest and saves a one-star review ("không thấy
/// trống thêm").
public struct CleanupDoneScreen: View {
    private let deletedCount: Int
    private let bytesFreed: Int64
    private let noun: String
    private let onOpenPhotos: () -> Void
    private let onContinue: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false
    /// "Dọn nhóm khác" leaves once, even if tapped twice. It comes back after
    /// a second, in case the app keeps this screen up (a sheet, say).
    @State private var hasContinued = false

    /// - Parameters:
    ///   - noun: what was deleted, "ảnh" or "video" (`CleanupSession.noun`).
    ///   - onOpenPhotos: open the Photos app, where "Đã xoá gần đây" can be
    ///     emptied.
    public init(
        deletedCount: Int, bytesFreed: Int64, noun: String = "ảnh",
        onOpenPhotos: @escaping () -> Void, onContinue: @escaping () -> Void
    ) {
        self.deletedCount = deletedCount
        self.bytesFreed = bytesFreed
        self.noun = noun
        self.onOpenPhotos = onOpenPhotos
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.lg) {
                badge
                    .padding(.top, LabSpacing.xl)
                VStack(spacing: LabSpacing.xs) {
                    Text(verbatim: "Đã dọn \(VietnameseNumber.grouped(deletedCount)) \(noun)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(theme.label)
                    Text(verbatim: ByteSize.string(bytesFreed))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.accentText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(verbatim: "sẽ được trả lại cho iPhone")
                        .font(.headline)
                        .foregroundStyle(theme.secondaryLabel)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                recentlyDeletedCard
            }
            .padding(.horizontal, LabSpacing.md)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                guard !hasContinued else { return }
                hasContinued = true
                onContinue()
            } label: {
                Text(verbatim: "Dọn nhóm khác")
            }
            .buttonStyle(.labFilled)
            .disabled(hasContinued)
            .task(id: hasContinued) {
                guard hasContinued else { return }
                try? await Task.sleep(for: .seconds(1))
                hasContinued = false
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
            .labBottomBar()
        }
        .background(theme.canvas.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: isShown)
        .onAppear { isShown = true }
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(theme.tonalFill(.positive))
                .frame(width: 148, height: 148)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(theme.text(.positive))
                .symbolEffect(.bounce, value: isShown)
            // A few sparkles around the badge; still with Reduce Motion.
            ForEach(Array(sparkles.enumerated()), id: \.offset) { entry in
                Image(systemName: "sparkle")
                    .font(.system(size: entry.element.size, weight: .bold))
                    .foregroundStyle(theme.fill(.accent))
                    .offset(entry.element.offset)
                    .scaleEffect(isShown || reduceMotion ? 1 : 0.2)
                    .opacity(isShown || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.5).delay(0.1 * Double(entry.offset)), value: isShown)
            }
        }
        .frame(height: 190)
        .accessibilityHidden(true)
    }

    private var sparkles: [(offset: CGSize, size: CGFloat)] {
        [
            (CGSize(width: -92, height: -54), 22),
            (CGSize(width: 96, height: -40), 16),
            (CGSize(width: -70, height: 66), 14),
            (CGSize(width: 84, height: 70), 24),
        ]
    }

    private var recentlyDeletedCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            Label {
                Text(verbatim: "\(noun.prefix(1).uppercased() + noun.dropFirst()) vừa xoá vẫn nằm trong Ảnh › Đã xoá gần đây. iPhone lấy lại dung lượng sau 30 ngày, hoặc ngay khi bạn xoá hẳn ở đó.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(theme.accentText)
            }
            .font(.subheadline)
            .foregroundStyle(theme.label)
            Button {
                onOpenPhotos()
            } label: {
                Label {
                    Text(verbatim: "Mở ứng dụng Ảnh")
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
            }
            .buttonStyle(.labTonal)
        }
        .labCard()
    }
}
#endif
