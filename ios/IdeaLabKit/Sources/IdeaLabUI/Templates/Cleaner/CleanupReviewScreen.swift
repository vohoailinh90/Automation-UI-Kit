#if os(iOS)
import IdeaLabCore
import SwiftUI

/// The last look before anything is deleted: every photo swiped to delete, in
/// a grid. Tap one to keep it after all. The button says exactly how many
/// photos and how much space, and the note under it says where they go.
///
/// The free tier is honest here too: when the marked photos are more than the
/// allowance left, the screen offers both — delete the free ones now, or
/// unlock the full version — instead of a paywall at the last second.
///
/// `onDelete` should call PhotoKit (`PHAssetChangeRequest.deleteAssets`), which
/// shows iOS's own confirmation; don't add a second dialog on top of it. The
/// buttons stay disabled until it returns, so a double tap cannot ask twice.
public struct CleanupReviewScreen<Thumbnail: View>: View {
    @Binding private var session: CleanupSession
    private let allowance: FreeAllowance?
    private let thumbnail: (CleanupItem) -> Thumbnail
    private let onDelete: @MainActor ([CleanupItem]) async -> Void
    private let onUnlock: () -> Void
    @Environment(\.labTheme) private var theme
    @State private var isDeleting = false

    /// - Parameters:
    ///   - allowance: free deletions left, `nil` for the full version.
    ///   - onDelete: delete these photos (all of `toDelete`, or the ones the
    ///     free allowance covers); return once iOS has answered.
    ///   - onUnlock: open the paywall.
    public init(
        session: Binding<CleanupSession>,
        allowance: FreeAllowance?,
        @ViewBuilder thumbnail: @escaping (CleanupItem) -> Thumbnail,
        onDelete: @escaping @MainActor ([CleanupItem]) async -> Void,
        onUnlock: @escaping () -> Void
    ) {
        _session = session
        self.allowance = allowance
        self.thumbnail = thumbnail
        self.onDelete = onDelete
        self.onUnlock = onUnlock
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LabSpacing.md) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: LabSpacing.xxs)], spacing: LabSpacing.xxs) {
                    ForEach(session.swipedToDelete) { item in
                        ReviewTile(item, isMarked: session.isMarkedForDeletion(item.id)) {
                            session.toggleMark(item.id)
                        } thumbnail: {
                            thumbnail(item)
                        }
                    }
                }
                // The marks are what is being deleted: frozen until iOS answers.
                .disabled(isDeleting)
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            actionTray
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LabSpacing.xxs) {
            Text(verbatim: "\(VietnameseNumber.grouped(session.toDelete.count)) ảnh · \(ByteSize.string(session.bytesToFree))")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .contentTransition(.numericText())
                .animation(.snappy, value: session.toDelete.count)
            Text(verbatim: "Chạm vào ảnh để giữ lại. Chưa có gì bị xoá cho tới khi bạn bấm nút bên dưới.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionTray: some View {
        let marked = session.toDelete
        let covered = allowance.map { $0.covered(of: marked.count) } ?? marked.count
        return VStack(spacing: LabSpacing.xs) {
            if marked.isEmpty {
                Button {} label: {
                    Text(verbatim: "Chưa chọn ảnh nào để xoá")
                }
                .buttonStyle(.labFilled(.negative))
                .disabled(true)
            } else if covered == marked.count {
                Button {
                    delete(marked)
                } label: {
                    Label {
                        Text(verbatim: "Xoá \(VietnameseNumber.grouped(marked.count)) ảnh · \(ByteSize.string(session.bytesToFree))")
                    } icon: {
                        Image(systemName: "trash.fill")
                    }
                }
                .buttonStyle(.labFilled(.negative))
                .disabled(isDeleting)
            } else {
                Text(verbatim: covered > 0
                    ? "Bản miễn phí còn xoá được \(VietnameseNumber.grouped(covered)) ảnh."
                    : "Bạn đã dùng hết lượt xoá miễn phí.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.center)
                Button {
                    onUnlock()
                } label: {
                    Text(verbatim: "Mở khoá để xoá cả \(VietnameseNumber.grouped(marked.count)) ảnh")
                }
                .buttonStyle(.labFilled)
                .disabled(isDeleting)
                if covered > 0 {
                    Button {
                        delete(Array(marked.prefix(covered)))
                    } label: {
                        Text(verbatim: "Xoá \(VietnameseNumber.grouped(covered)) ảnh miễn phí")
                    }
                    .buttonStyle(.labTonal(.negative))
                    .disabled(isDeleting)
                }
            }
            Text(verbatim: "iOS sẽ hỏi lại một lần. Ảnh xoá nằm trong Đã xoá gần đây 30 ngày.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LabSpacing.md)
        .labGlass(in: RoundedRectangle(cornerRadius: LabRadius.xl, style: .continuous))
        .padding(.horizontal, LabSpacing.xs)
        .padding(.bottom, LabSpacing.xxs)
    }

    /// Asks once: the buttons are disabled before `onDelete` starts.
    private func delete(_ items: [CleanupItem]) {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            await onDelete(items)
            isDeleting = false
        }
    }
}
#endif
