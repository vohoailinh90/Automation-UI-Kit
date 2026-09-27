#if os(iOS)
import IdeaLabCore
import SwiftUI

/// "Ảnh gần giống nhau": each moment shot several times, as one card with
/// every shot in it. The sharpest shot and every favourite are kept, and
/// the rest are marked. Tap a shot to keep it or let it go, or keep the
/// whole group. Every group keeps at least one shot, and a favourite is never
/// deleted; a tap that would break either says so under its group.
///
/// Every shot is shown, kept or not, and none is dimmed: the shots are there
/// to be compared. The marks start as a suggestion nobody has looked at yet,
/// so the delete button takes only the marked shots that have been on
/// screen — their middle in view, clear of the bars and the tray, for a
/// moment (`SeenOnScreen`) — and the tray asks to scroll to the rest:
/// nothing is deleted unseen.
///
/// `onDelete` and `onUnlock` work as in `CleanupReviewScreen`, with the same
/// free allowance: the first marked photos seen, from the top group down,
/// are the free ones.
public struct SimilarPhotosScreen<Thumbnail: View>: View {
    @Binding private var review: SimilarReview
    private let allowance: FreeAllowance?
    private let now: Date
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
    /// The shots that have been on screen: the only ones the delete button
    /// takes.
    @State private var seen = SeenShots()

    private struct Refusal: Equatable {
        let group: SimilarGroup.ID
        let message: String
        /// Each refusal is new, so the same one twice still buzzes twice.
        let id = UUID()
    }

    /// - Parameters:
    ///   - allowance: free deletions left, `nil` for the full version.
    ///   - now: injected so previews and screenshots are stable; a moment
    ///     from another year shows its year.
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
        now: Date = .now,
        calendar: Calendar = .current,
        @ViewBuilder thumbnail: @escaping (SimilarPhoto) -> Thumbnail,
        onDelete: @escaping @MainActor ([CleanupItem]) async -> Set<CleanupItem.ID>,
        onUnlock: @escaping () -> Void
    ) {
        _review = review
        self.allowance = allowance
        self.now = now
        self.calendar = calendar
        self.thumbnail = thumbnail
        self.onDelete = onDelete
        self.onUnlock = onUnlock
    }

    public var body: some View {
        let marked = review.toDelete
        let shown = marked.filter { seen.ids.contains($0.id) }
        ScrollView {
            // Lazy: a library can hold thousands of groups, and only the
            // ones near the screen are drawn.
            LazyVStack(alignment: .leading, spacing: LabSpacing.md) {
                header(marked)
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
                // After the groups, not above them as in the review grid: at
                // these sizes the header already fills the first screen, and
                // the photos should not wait for two more notes.
                if !notesInTray {
                    CleanupDeleteNotes(marked: shown, free: free(of: shown), place: Self.place)
                }
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
            // The marks are what is being deleted: frozen until iOS answers.
            .disabled(isDeleting)
        }
        .background(theme.canvas.ignoresSafeArea())
        // Where the photos can be seen. SwiftUI lays the scroll view out in
        // the safe area — below the bars and, from the modifier below, above
        // the tray — and lets only its content run under them. Its safe
        // area insets are the container's, already outside this frame.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            seen.scrollFrame = frame
        }
        .safeAreaInset(edge: .bottom) {
            CleanupDeleteTray(
                marked: shown,
                free: free(of: shown),
                unseen: marked.count - shown.count,
                isDeleting: isDeleting,
                showsNotes: notesInTray,
                place: Self.place,
                // What is marked and seen when the button is tapped, not when
                // it was drawn — and never more than the free allowance covers.
                onDelete: { delete(free(of: shownMarks)) },
                onUnlock: onUnlock
            )
            .labBottomBar()
            // Measured too, so a host that lets the scroll view run under
            // the tray still cannot count what the tray covers.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                seen.trayTop = top
            }
        }
        .sensoryFeedback(.warning, trigger: refusal) { _, new in new != nil }
    }

    /// The count of every marked shot, seen or not: what the review will
    /// free once it is done.
    private func header(_ marked: [CleanupItem]) -> some View {
        VStack(alignment: .leading, spacing: LabSpacing.xxs) {
            Text(verbatim: "\(VietnameseNumber.grouped(marked.count)) ảnh · \(ByteSize.string(CleanupMath.bytes(of: marked)))")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .contentTransition(.numericText())
                .animation(.snappy, value: marked.count)
            // The sparkles are the ones on the sharpest shot of each group.
            Text("Mỗi nhóm giữ tấm nét nhất \(Image(systemName: "sparkles")) và ảnh yêu thích. Chạm vào ảnh để giữ hay bỏ.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: "Mỗi nhóm giữ tấm nét nhất và ảnh yêu thích. Chạm vào ảnh để giữ hay bỏ."))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - A group

    private func groupCard(_ group: SimilarGroup) -> some View {
        // From the group in hand: looking each group up again in the review
        // would make drawing them all take time squared in their number.
        let marked = group.photos.filter { !review.isKept($0.id) }
        let keptCount = group.photos.count - marked.count
        let sharpest = group.sharpest.id
        return VStack(alignment: .leading, spacing: LabSpacing.sm) {
            groupHeader(group, marked: marked)
            LazyVGrid(columns: columns, spacing: LabSpacing.xxs) {
                ForEach(Array(group.photos.enumerated()), id: \.element.id) { index, photo in
                    SimilarTile(
                        photo,
                        isKept: review.isKept(photo.id),
                        isOnlyKept: keptCount == 1,
                        isSharpest: photo.id == sharpest,
                        position: (index + 1, group.photos.count)
                    ) {
                        tap(photo, in: group)
                    } thumbnail: {
                        thumbnail(photo)
                    }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        seen.report(photo.id, at: frame)
                    }
                    .onDisappear { seen.forget(photo.id) }
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

    /// "5 ảnh · Thứ Tư, 23/9 · 19:12" on a line of its own, then what goes
    /// and "Giữ cả nhóm" — under it at accessibility sizes, where beside it
    /// the button would squeeze the words into a column.
    private func groupHeader(_ group: SimilarGroup, marked: [SimilarPhoto]) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LabSpacing.sm))
        // "Gợi ý lại" only where the suggestion would mark something: a group
        // of favourites and its sharpest shot keeps everything anyway.
        let canSuggest = group.suggestedKeep.count < group.photos.count
        return VStack(alignment: .leading, spacing: LabSpacing.xxs) {
            Text(verbatim: "\(VietnameseNumber.grouped(group.photos.count)) ảnh · \(when(group))")
                .font(.headline)
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            layout {
                Text(verbatim: marked.isEmpty
                    ? "Giữ cả nhóm"
                    : "Xoá \(VietnameseNumber.grouped(marked.count)) ảnh · \(ByteSize.string(CleanupMath.bytes(of: marked.map(\.item))))")
                    .font(.subheadline)
                    .foregroundStyle(marked.isEmpty ? theme.secondaryLabel : theme.text(.negative))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !marked.isEmpty || canSuggest {
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
        }
    }

    /// Three shots across, two at accessibility sizes, where the marks' words
    /// grow.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 96), spacing: LabSpacing.xxs)]
    }

    /// "Thứ Tư, 23/9 · 19:12", with the year when it is not this one, and
    /// the time as the locale writes it: "7:12 PM" in English.
    private func when(_ group: SimilarGroup) -> String {
        let date = group.photos[0].item.date
        var day = calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            day = day.year()
        }
        let time = calendar.dateFormat(locale: locale).hour().minute()
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

    /// The marked shots that have been on screen, from the top group down.
    private var shownMarks: [CleanupItem] {
        review.toDelete.filter { seen.ids.contains($0.id) }
    }

    /// The first of `marks` the free allowance covers: all of them in the
    /// full version.
    private func free(of marks: [CleanupItem]) -> [CleanupItem] {
        Array(marks.prefix(allowance.map { $0.covered(of: marks.count) } ?? marks.count))
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

/// The screen's `SeenOnScreen`. A reference, so the frames that stream in
/// while the photos scroll never redraw the screen: only a shot seen for
/// the first time does.
@MainActor
@Observable
private final class SeenShots {
    /// The shots that have been on screen, the only part the screen draws
    /// from.
    private(set) var ids: Set<CleanupItem.ID> = []
    @ObservationIgnored private var log = SeenOnScreen<CleanupItem.ID>()
    /// A check for when the next shot waiting in view is due: a screen at
    /// rest reports no frames.
    @ObservationIgnored private var settling: Task<Void, Never>?

    /// The scroll view's frame, in global coordinates.
    @ObservationIgnored var scrollFrame = CGRect.null {
        didSet { updateViewport() }
    }

    /// Where the tray starts, in global coordinates.
    @ObservationIgnored var trayTop = CGFloat.infinity {
        didSet { updateViewport() }
    }

    func report(_ id: CleanupItem.ID, at frame: CGRect) {
        log.report(id, at: frame, time: Self.now)
        changed()
    }

    /// A shot the lazy stack let go of.
    func forget(_ id: CleanupItem.ID) {
        log.forget(id)
    }

    /// The scroll view's frame, cut off where the tray starts.
    private func updateViewport() {
        var viewport = scrollFrame
        if !viewport.isNull, viewport.maxY > trayTop {
            viewport.size.height = max(trayTop - viewport.minY, 0)
        }
        log.setViewport(viewport, at: Self.now)
        changed()
    }

    private func changed() {
        // Seen shots only ever grow in number, so the count says when to copy.
        if log.ids.count != ids.count { ids = log.ids }
        guard settling == nil, let due = log.nextSettle else { return }
        settling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(due - Self.now, 0)))
            guard let self else { return }
            settling = nil
            log.settle(at: Self.now)
            changed()
        }
    }

    /// Seconds since the device started: a clock that only goes forward.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
#endif
