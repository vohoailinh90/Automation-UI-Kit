#if os(iOS)
import IdeaLabCore
import SwiftUI

/// Swipe through one category: progress on top, the deck, and the three
/// buttons under it. When the deck is empty — or whenever the user taps
/// "Xem lại" — the review step takes over; nothing is deleted from here.
public struct CleanupSwipeScreen<Thumbnail: View>: View {
    @Binding private var session: CleanupSession
    private let calendar: Calendar
    private let thumbnail: (CleanupItem) -> Thumbnail
    private let onReview: () -> Void
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - thumbnail: the photo for a card or tile, filling the frame it gets.
    ///   - onReview: open `CleanupReviewScreen` for this session.
    public init(
        session: Binding<CleanupSession>,
        calendar: Calendar = .current,
        @ViewBuilder thumbnail: @escaping (CleanupItem) -> Thumbnail,
        onReview: @escaping () -> Void
    ) {
        _session = session
        self.calendar = calendar
        self.thumbnail = thumbnail
        self.onReview = onReview
    }

    public var body: some View {
        VStack(spacing: LabSpacing.md) {
            progress
            SwipeDeck(session: $session, calendar: calendar, thumbnail: thumbnail) {
                finishedCard
            }
        }
        .padding(.horizontal, LabSpacing.md)
        .padding(.top, LabSpacing.xs)
        .padding(.bottom, LabSpacing.md)
        .background(theme.canvas.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onReview()
                } label: {
                    Text(verbatim: "Xem lại")
                }
                .disabled(session.swipedToDelete.isEmpty)
            }
        }
    }

    private var progress: some View {
        VStack(spacing: LabSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(VietnameseNumber.grouped(session.decidedCount))/\(VietnameseNumber.grouped(session.items.count))")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(theme.label)
                    .contentTransition(.numericText())
                Spacer(minLength: LabSpacing.xs)
                Label {
                    Text(verbatim: "\(VietnameseNumber.grouped(session.toDelete.count)) ảnh · \(ByteSize.string(session.bytesToFree))")
                        .contentTransition(.numericText())
                } icon: {
                    Image(systemName: "trash")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text(.negative))
            }
            ProgressView(value: Double(session.decidedCount), total: Double(max(session.items.count, 1)))
                .tint(theme.fill(.accent))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Đã xem \(session.decidedCount) trên \(session.items.count) ảnh"))
        .accessibilityValue(Text(verbatim: "Chọn xoá \(session.toDelete.count) ảnh, \(ByteSize.string(session.bytesToFree))"))
        .animation(.snappy, value: session.decidedCount)
    }

    private var finishedCard: some View {
        let count = session.toDelete.count
        return VStack(spacing: LabSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(theme.text(.positive))
                .symbolEffect(.bounce, value: session.isFinished)
                .accessibilityHidden(true)
            Text(verbatim: "Đã xem hết \(VietnameseNumber.grouped(session.items.count)) ảnh")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            Text(verbatim: count > 0
                ? "Chọn xoá \(VietnameseNumber.grouped(count)) ảnh · \(ByteSize.string(session.bytesToFree)). Xem lại một lần trước khi xoá."
                : "Bạn giữ lại tất cả. Không có gì để xoá.")
                .font(.body)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
            if count > 0 {
                Button {
                    onReview()
                } label: {
                    Text(verbatim: "Xem lại trước khi xoá")
                }
                .buttonStyle(.labFilled)
            }
        }
        .padding(LabSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: LabRadius.xl, style: .continuous))
    }
}
#endif
