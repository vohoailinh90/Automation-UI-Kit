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
/// The photos it reports gone leave the session, so they are not offered
/// again; the rest stay marked. It must record what it deleted in the free
/// allowance before it returns: the buttons come back as soon as it does,
/// and they read `allowance` to know what is still free.
public struct CleanupReviewScreen<Thumbnail: View>: View {
    @Binding private var session: CleanupSession
    private let allowance: FreeAllowance?
    private let thumbnail: (CleanupItem) -> Thumbnail
    private let onDelete: @MainActor ([CleanupItem]) async -> Set<CleanupItem.ID>
    private let onUnlock: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isDeleting = false

    /// - Parameters:
    ///   - allowance: free deletions left, `nil` for the full version.
    ///   - onDelete: delete these photos (all of `toDelete`, or the first
    ///     ones the free allowance covers), record the ones it deleted in the
    ///     allowance before returning — only the app can tell those from
    ///     photos that were already gone — and return the ids no longer in
    ///     the library: deleted now, or already gone. None if the user
    ///     cancelled iOS's dialog or it failed.
    ///   - onUnlock: open the paywall.
    public init(
        session: Binding<CleanupSession>,
        allowance: FreeAllowance?,
        @ViewBuilder thumbnail: @escaping (CleanupItem) -> Thumbnail,
        onDelete: @escaping @MainActor ([CleanupItem]) async -> Set<CleanupItem.ID>,
        onUnlock: @escaping () -> Void
    ) {
        _session = session
        self.allowance = allowance
        self.thumbnail = thumbnail
        self.onDelete = onDelete
        self.onUnlock = onUnlock
    }

    public var body: some View {
        let free = freeItems
        ScrollView {
            VStack(alignment: .leading, spacing: LabSpacing.md) {
                header
                if !notesInTray {
                    CleanupDeleteNotes(marked: session.toDelete, free: free, place: Self.place)
                }
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
            CleanupDeleteTray(
                marked: session.toDelete,
                free: free,
                isDeleting: isDeleting,
                showsNotes: notesInTray,
                place: Self.place,
                // What the button counted, less any photo unmarked before
                // the tap reached it: never one it did not count.
                onDelete: { delete(CleanupMath.stillMarked(free, in: session.toDelete)) },
                onUnlock: onUnlock
            )
            .labBottomBar()
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

    /// At accessibility text sizes the notes scroll with the grid and the
    /// pinned tray keeps only the buttons: with the notes, it would cover
    /// most of the photos.
    private var notesInTray: Bool { !typeSize.isAccessibilitySize }

    /// Where the first marked photos are, for the allowance note.
    private static var place: String { "trong lưới" }

    /// The first marked photos, in the grid's order, that the free allowance
    /// covers: all of them in the full version.
    private var freeItems: [CleanupItem] {
        let marked = session.toDelete
        return Array(marked.prefix(allowance.map { $0.covered(of: marked.count) } ?? marked.count))
    }

    /// Asks once: the buttons are disabled before `onDelete` starts. What iOS
    /// deleted leaves the session; a cancelled dialog leaves everything marked.
    private func delete(_ items: [CleanupItem]) {
        guard !isDeleting, !items.isEmpty else { return }
        isDeleting = true
        Task {
            let deleted = await onDelete(items)
            session.remove(deleted.intersection(items.map(\.id)))
            isDeleting = false
        }
    }
}
#endif
