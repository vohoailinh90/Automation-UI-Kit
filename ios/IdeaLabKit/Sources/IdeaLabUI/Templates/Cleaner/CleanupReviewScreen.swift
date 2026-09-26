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
/// again; the rest stay marked. Until `allowance` changes, the screen also
/// counts them against the free tier itself, so an app that records the
/// deletion later cannot let a second tap go past it.
public struct CleanupReviewScreen<Thumbnail: View>: View {
    @Binding private var session: CleanupSession
    private let allowance: FreeAllowance?
    private let thumbnail: (CleanupItem) -> Thumbnail
    private let onDelete: @MainActor ([CleanupItem]) async -> Set<CleanupItem.ID>
    private let onUnlock: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDeleting = false
    /// At least this many free deletions are used, counting what this screen
    /// deleted: `allowance` may not show those yet. Reset when it changes.
    @State private var usedAtLeast = 0

    /// - Parameters:
    ///   - allowance: free deletions left, `nil` for the full version.
    ///   - onDelete: delete these photos (all of `toDelete`, or the first
    ///     ones the free allowance covers), record the ones deleted in the
    ///     allowance, and return the ids no longer in the library: deleted
    ///     now, or already gone. None if the user cancelled iOS's dialog or it
    ///     failed.
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
        ScrollView {
            VStack(alignment: .leading, spacing: LabSpacing.md) {
                header
                if !notesInTray {
                    notes
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
            actionTray
        }
        .onChange(of: allowance) {
            // The app has recorded the deletions: its count is the one to use.
            usedAtLeast = 0
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
    private var notesInTray: Bool { !dynamicTypeSize.isAccessibilitySize }

    /// How far the free tier goes, when it does not cover every marked photo.
    private func allowanceNote(free: Int) -> String {
        free == 0
            ? "Bạn đã dùng hết lượt xoá miễn phí."
            : "Lượt miễn phí còn lại đủ xoá \(VietnameseNumber.grouped(free)) ảnh đầu tiên trong lưới."
    }

    private let deletionNote = "iOS sẽ hỏi lại một lần. Ảnh xoá nằm trong Đã xoá gần đây 30 ngày."

    /// The tray's notes, above the grid instead at accessibility text sizes.
    private var notes: some View {
        let marked = session.toDelete
        let free = freeItems
        return VStack(alignment: .leading, spacing: LabSpacing.xs) {
            if !marked.isEmpty, free.count < marked.count {
                Text(verbatim: allowanceNote(free: free.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: deletionNote)
                .font(.footnote)
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The free allowance, counting what this screen deleted that `allowance`
    /// may not show yet.
    private var effectiveAllowance: FreeAllowance? {
        allowance.map { FreeAllowance(limit: $0.limit, used: max($0.used, usedAtLeast)) }
    }

    /// The first marked photos, in the grid's order, that the free allowance
    /// covers: all of them in the full version.
    private var freeItems: [CleanupItem] {
        let marked = session.toDelete
        return Array(marked.prefix(effectiveAllowance.map { $0.covered(of: marked.count) } ?? marked.count))
    }

    private var actionTray: some View {
        let marked = session.toDelete
        let free = freeItems
        return VStack(spacing: LabSpacing.xs) {
            if marked.isEmpty {
                Button {} label: {
                    Text(verbatim: "Chưa chọn ảnh nào để xoá")
                }
                .buttonStyle(.labFilled(.negative))
                .disabled(true)
            } else if free.count == marked.count {
                Button {
                    // What is marked when the button is tapped, not when it was
                    // drawn — and never more than the free allowance covers.
                    delete(freeItems)
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
                if notesInTray {
                    Text(verbatim: allowanceNote(free: free.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.label)
                        .multilineTextAlignment(.center)
                }
                Button {
                    onUnlock()
                } label: {
                    Text(verbatim: "Mở khoá để xoá cả \(VietnameseNumber.grouped(marked.count)) ảnh")
                }
                .buttonStyle(.labFilled)
                .disabled(isDeleting)
                if !free.isEmpty {
                    Button {
                        delete(freeItems)
                    } label: {
                        Text(verbatim: "Xoá \(VietnameseNumber.grouped(free.count)) ảnh đầu tiên · \(ByteSize.string(CleanupMath.bytes(of: free)))")
                    }
                    .buttonStyle(.labTonal(.negative))
                    .disabled(isDeleting)
                }
            }
            if notesInTray {
                Text(verbatim: deletionNote)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LabSpacing.md)
        .labGlass(in: RoundedRectangle(cornerRadius: LabRadius.xl, style: .continuous))
        .padding(.horizontal, LabSpacing.xs)
        .padding(.bottom, LabSpacing.xxs)
    }

    /// Asks once: the buttons are disabled before `onDelete` starts. What iOS
    /// deleted leaves the session; a cancelled dialog leaves everything marked.
    private func delete(_ items: [CleanupItem]) {
        guard !isDeleting, !items.isEmpty else { return }
        isDeleting = true
        let usedBefore = effectiveAllowance?.used
        Task {
            let gone = await onDelete(items).intersection(items.map(\.id))
            session.remove(gone)
            if let usedBefore {
                let (sum, overflow) = usedBefore.addingReportingOverflow(gone.count)
                usedAtLeast = max(usedAtLeast, overflow ? .max : sum)
            }
            isDeleting = false
        }
    }
}
#endif
