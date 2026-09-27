#if os(iOS)
import IdeaLabCore
import SwiftUI

/// "Ảnh gần giống nhau": each moment shot several times, as one card with
/// every shot in it. The sharpest shot and every favourite are kept, and
/// the rest are marked. Tap a shot to keep it or let it go, or keep the
/// whole group. Every group keeps at least one shot, and a favourite is never
/// deleted; a tap that would break either says so under its group.
///
/// Every shot is on screen, kept or not, and none is dimmed: nothing is
/// deleted unseen, and the shots are there to be compared.
///
/// `onDelete` and `onUnlock` work as in `CleanupReviewScreen`, with the same
/// free allowance: the first marked photos, from the top group down, are the
/// free ones.
public struct SimilarPhotosScreen<Thumbnail: View>: View {
    @Binding private var review: SimilarReview
    private let allowance: FreeAllowance?
    private let calendar: Calendar
    private let thumbnail: (SimilarPhoto) -> Thumbnail
    private let onDelete: @MainActor ([CleanupItem]) async -> Set<CleanupItem.ID>
    private let onUnlock: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isDeleting = false
    /// The last tap that was refused, and why, shown under its group.
    @State private var refusal: Refusal?

    private struct Refusal: Equatable {
        let group: SimilarGroup.ID
        let message: String
        /// Each refusal is new, so the same one twice still buzzes twice.
        let id = UUID()
    }

    /// - Parameters:
    ///   - allowance: free deletions left, `nil` for the full version.
    ///   - calendar: the user's, for when each moment was shot.
    ///   - thumbnail: the shot, filling whatever frame it is given (in an app,
    ///     an image from `PHCachingImageManager`).
    ///   - onDelete: as in `CleanupReviewScreen`: delete these photos, record
    ///     the ones it deleted in the allowance before returning, and return
    ///     the ids no longer in the library.
    ///   - onUnlock: open the paywall.
    public init(
        review: Binding<SimilarReview>,
        allowance: FreeAllowance?,
        calendar: Calendar = .current,
        @ViewBuilder thumbnail: @escaping (SimilarPhoto) -> Thumbnail,
        onDelete: @escaping @MainActor ([CleanupItem]) async -> Set<CleanupItem.ID>,
        onUnlock: @escaping () -> Void
    ) {
        _review = review
        self.allowance = allowance
        self.calendar = calendar
        self.thumbnail = thumbnail
        self.onDelete = onDelete
        self.onUnlock = onUnlock
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LabSpacing.md) {
                header
                if !notesInTray {
                    CleanupDeleteNotes(marked: review.toDelete, free: freeItems, place: Self.place)
                }
                if review.groups.isEmpty {
                    Label {
                        Text(verbatim: "Không còn nhóm ảnh gần giống nào.")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.text(.positive))
                    }
                    .font(.headline)
                    .foregroundStyle(theme.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LabSpacing.xl)
                }
                ForEach(review.groups) { group in
                    groupCard(group)
                }
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
            // The marks are what is being deleted: frozen until iOS answers.
            .disabled(isDeleting)
        }
        .background(theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CleanupDeleteTray(
                marked: review.toDelete,
                free: freeItems,
                isDeleting: isDeleting,
                showsNotes: notesInTray,
                place: Self.place,
                // What is marked when the button is tapped, not when it was
                // drawn — and never more than the free allowance covers.
                onDelete: { delete(freeItems) },
                onUnlock: onUnlock
            )
            .labBottomBar()
        }
        .sensoryFeedback(.warning, trigger: refusal) { _, new in new != nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LabSpacing.xxs) {
            Text(verbatim: "\(VietnameseNumber.grouped(review.toDelete.count)) ảnh · \(ByteSize.string(review.bytesToFree))")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .contentTransition(.numericText())
                .animation(.snappy, value: review.toDelete.count)
            Text(verbatim: "Mỗi nhóm giữ tấm nét nhất và ảnh yêu thích. Chạm vào ảnh để giữ hay bỏ. Chưa có gì bị xoá cho tới khi bạn bấm nút bên dưới.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - A group

    private func groupCard(_ group: SimilarGroup) -> some View {
        let marked = review.toDelete(in: group.id)
        let sharpest = group.sharpest.id
        return VStack(alignment: .leading, spacing: LabSpacing.sm) {
            groupHeader(group, marked: marked)
            LazyVGrid(columns: columns, spacing: LabSpacing.xxs) {
                ForEach(Array(group.photos.enumerated()), id: \.element.id) { index, photo in
                    SimilarTile(
                        photo,
                        isKept: review.isKept(photo.id),
                        isSharpest: photo.id == sharpest,
                        position: (index + 1, group.photos.count)
                    ) {
                        tap(photo, in: group)
                    } thumbnail: {
                        thumbnail(photo)
                    }
                }
            }
            if let refusal, refusal.group == group.id {
                Label {
                    Text(verbatim: refusal.message)
                } icon: {
                    Image(systemName: "info.circle.fill")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
        .labCard()
        .animation(.snappy, value: refusal)
    }

    /// "5 ảnh · Thứ Tư, 23/9 · 19:12", what goes, and "Giữ cả nhóm" — under
    /// the words at accessibility sizes, where beside them it would squeeze
    /// them into a column.
    private func groupHeader(_ group: SimilarGroup, marked: [SimilarPhoto]) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LabSpacing.sm))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(VietnameseNumber.grouped(group.photos.count)) ảnh · \(when(group))")
                    .font(.headline)
                    .foregroundStyle(theme.label)
                Text(verbatim: marked.isEmpty
                    ? "Giữ cả nhóm"
                    : "Xoá \(VietnameseNumber.grouped(marked.count)) ảnh · \(ByteSize.string(CleanupMath.bytes(of: marked.map(\.item))))")
                    .font(.subheadline)
                    .foregroundStyle(marked.isEmpty ? theme.secondaryLabel : theme.text(.negative))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button {
                if marked.isEmpty {
                    review.suggest(in: group.id)
                } else {
                    review.keepAll(in: group.id)
                }
                refusal = nil
            } label: {
                Text(verbatim: marked.isEmpty ? "Gợi ý lại" : "Giữ cả nhóm")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accentText)
                    .padding(.horizontal, LabSpacing.sm)
                    .frame(minHeight: 44)
                    .background(theme.tonalFill(.accent), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(verbatim: marked.isEmpty
                ? "Giữ lại tấm nét nhất và ảnh yêu thích, bỏ các ảnh còn lại"
                : "Không xoá ảnh nào trong nhóm này"))
        }
    }

    /// Three shots across, two at accessibility sizes, where the marks' words
    /// grow.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 96), spacing: LabSpacing.xxs)]
    }

    /// "Thứ Tư, 23/9 · 19:12", with the year when it is not this one.
    private func when(_ group: SimilarGroup) -> String {
        let date = group.photos[0].item.date
        var day = calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits)
        if !calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            day = day.year()
        }
        let time = calendar.dateFormat(locale: locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return "\(date.formatted(day)) · \(date.formatted(time))"
    }

    /// Keeps or lets go of a shot. A refused tap — a favourite, or the last
    /// shot its group keeps — says why under the group, and to VoiceOver.
    private func tap(_ photo: SimilarPhoto, in group: SimilarGroup) {
        if review.toggle(photo.id) {
            if refusal?.group == group.id { refusal = nil }
            return
        }
        let message = photo.item.isFavorite
            ? "Ảnh yêu thích luôn được giữ."
            : "Mỗi nhóm giữ lại ít nhất một ảnh. Chọn giữ một ảnh khác trước."
        refusal = Refusal(group: group.id, message: message)
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - Deleting

    /// At accessibility text sizes the notes scroll with the groups and the
    /// pinned tray keeps only the buttons: with the notes, it would cover
    /// most of the photos.
    private var notesInTray: Bool { !typeSize.isAccessibilitySize }

    /// Where the first marked photos are, for the allowance note.
    private static var place: String { "tính từ nhóm trên cùng" }

    /// The first marked photos, from the top group down, that the free
    /// allowance covers: all of them in the full version.
    private var freeItems: [CleanupItem] {
        let marked = review.toDelete
        return Array(marked.prefix(allowance.map { $0.covered(of: marked.count) } ?? marked.count))
    }

    /// Asks once: the buttons are disabled before `onDelete` starts. What iOS
    /// deleted leaves the review; a cancelled dialog leaves everything marked.
    private func delete(_ items: [CleanupItem]) {
        guard !isDeleting, !items.isEmpty else { return }
        isDeleting = true
        refusal = nil
        Task {
            let deleted = await onDelete(items)
            review.remove(deleted.intersection(items.map(\.id)))
            isDeleting = false
        }
    }
}
#endif
