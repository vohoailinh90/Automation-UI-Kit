#if os(iOS)
import IdeaLabCore
import SwiftUI

public extension CleanupCategory {
    /// SF Symbol for the category.
    var systemImage: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .similar: "square.on.square"
        case .blurry: "camera.aperture"
        case .documents: "doc.text.viewfinder"
        case .qrCodes: "qrcode"
        }
    }
}

/// The phone's storage as a ring: what is in use, the part this cleanup can
/// free — in the accent colour and drawn thicker, so even a thin slice shows —
/// and what is left. The number in the middle is the one people came for.
public struct StorageRing: View {
    private let storage: StorageStatus
    private let freeable: Int64
    @Environment(\.labTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 200
    @State private var isShown = false

    public init(storage: StorageStatus, freeable: Int64) {
        self.storage = storage
        self.freeable = freeable
    }

    public var body: some View {
        let reveal = isShown || reduceMotion ? 1.0 : 0.0
        let used = storage.usedFraction * reveal
        let afterCleanup = storage.usedFraction(afterFreeing: freeable) * reveal
        ZStack {
            Circle()
                .stroke(theme.surfaceSecondary, lineWidth: 16)
            Circle()
                .trim(from: 0, to: afterCleanup)
                .stroke(theme.secondaryLabel.opacity(0.45), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: afterCleanup, to: used)
                .stroke(theme.fill(.accent), style: StrokeStyle(lineWidth: 26, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(verbatim: ByteSize.string(freeable))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.accentText)
                    .contentTransition(.numericText())
                Text(verbatim: "có thể giải phóng")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(32)
        }
        .frame(width: min(diameter, 280), height: min(diameter, 280))
        .onAppear {
            withAnimation(.smooth(duration: 0.9)) { isShown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Bộ nhớ iPhone"))
        .accessibilityValue(Text(verbatim: "Đã dùng \(ByteSize.string(storage.used)) trên \(ByteSize.string(storage.capacity)). Có thể giải phóng \(ByteSize.string(freeable))."))
    }
}

/// The ring's key, in words: every colour in the ring is also said in text.
public struct StorageLegend: View {
    private let storage: StorageStatus
    private let freeable: Int64
    @Environment(\.labTheme) private var theme

    public init(storage: StorageStatus, freeable: Int64) {
        self.storage = storage
        self.freeable = freeable
    }

    public var body: some View {
        let cleanable = min(max(freeable, 0), storage.used)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LabSpacing.md) { items(cleanable) }
            VStack(alignment: .leading, spacing: LabSpacing.xs) { items(cleanable) }
        }
        .font(.footnote)
        .foregroundStyle(theme.secondaryLabel)
    }

    @ViewBuilder
    private func items(_ cleanable: Int64) -> some View {
        item(theme.fill(.accent), "Có thể dọn \(ByteSize.string(cleanable))")
        item(theme.secondaryLabel.opacity(0.45), "Dữ liệu khác \(ByteSize.string(storage.used - cleanable))")
        item(theme.surfaceSecondary, "Còn trống \(ByteSize.string(storage.available))")
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: LabSpacing.xxs) {
            Circle()
                .fill(color)
                .overlay { Circle().strokeBorder(theme.separator, lineWidth: 1) }
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One category on the home screen: icon, name, how many photos and how much
/// space, and a bar with its share of everything that can be freed.
public struct CleanupCategoryRow: View {
    private let summary: CategorySummary
    private let share: Double
    @Environment(\.labTheme) private var theme

    /// - Parameter share: this category's part of all freeable bytes, `0...1`.
    public init(_ summary: CategorySummary, share: Double) {
        self.summary = summary
        self.share = min(max(share, 0), 1)
    }

    public var body: some View {
        HStack(spacing: LabSpacing.sm) {
            Image(systemName: summary.category.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accentText)
                .frame(width: 44, height: 44)
                .background(theme.tonalFill(.accent), in: RoundedRectangle(cornerRadius: LabRadius.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                Text(verbatim: summary.category.title)
                    .font(.headline)
                    .foregroundStyle(theme.label)
                Text(verbatim: "\(VietnameseNumber.grouped(summary.count)) ảnh · \(ByteSize.string(summary.bytes))")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
                GeometryReader { proxy in
                    Capsule()
                        .fill(theme.fill(.accent))
                        .frame(width: max(6, proxy.size.width * share))
                }
                .frame(height: 6)
                .background(theme.surfaceSecondary, in: Capsule())
                .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryLabel)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LabSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Keep or delete, one photo at a time: swipe left to delete, right to keep —
/// or press the buttons under the deck, which do exactly the same, since a
/// gesture must never be the only way. VoiceOver users get the same actions
/// on the card; a hardware keyboard gets ← → and ⌘Z.
///
/// The deck only records decisions in `session`. Nothing is deleted until the
/// review step, and a swipe can be undone.
public struct SwipeDeck<Thumbnail: View, Finished: View>: View {
    @Binding private var session: CleanupSession
    private let calendar: Calendar
    private let thumbnail: (CleanupItem) -> Thumbnail
    private let finished: Finished

    @State private var drag: CGSize = .zero
    /// A finger is dragging the top card. Unlike `drag`, this resets when the
    /// system cancels the drag (a system gesture takes over), which never
    /// reaches `onEnded`.
    @GestureState private var isDragging = false
    @State private var isLeaving = false
    @State private var returningID: CleanupItem.ID?
    @State private var returningFrom: CleanupSession.Decision = .keep
    @State private var decisions = 0
    @State private var isPastThreshold = false
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a card must travel before letting go decides it.
    private let threshold: CGFloat = 110
    /// How much of each card behind the top one shows below it.
    private let peek: CGFloat = 10

    /// - Parameters:
    ///   - thumbnail: the photo, filling whatever frame it is given (in an app,
    ///     an image from `PHCachingImageManager`).
    ///   - finished: shown in place of the deck once every photo is decided.
    public init(
        session: Binding<CleanupSession>,
        calendar: Calendar = .current,
        @ViewBuilder thumbnail: @escaping (CleanupItem) -> Thumbnail,
        @ViewBuilder finished: () -> Finished
    ) {
        _session = session
        self.calendar = calendar
        self.thumbnail = thumbnail
        self.finished = finished()
    }

    public var body: some View {
        VStack(spacing: LabSpacing.lg) {
            ZStack {
                if session.current == nil {
                    finished
                        .transition(.opacity)
                }
                ForEach(Array(visibleCards.enumerated().reversed()), id: \.element.id) { entry in
                    card(entry.element, depth: entry.offset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Room for the two cards peeking out below the top one.
            .padding(.bottom, peek * 2)
            controls
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: decisions)
        .sensoryFeedback(.selection, trigger: isPastThreshold)
        .onChange(of: isDragging) { _, dragging in
            // A cancelled drag never reaches `onEnded`: put the card back.
            if !dragging { settle() }
        }
    }

    /// The card on top and the two peeking out behind it.
    private var visibleCards: [CleanupItem] {
        Array(session.items.lazy.filter { session.decision(for: $0.id) == nil }.prefix(3))
    }

    private func card(_ item: CleanupItem, depth: Int) -> some View {
        let isTop = depth == 0
        let returning = item.id == returningID && !reduceMotion
        let entry: AnyTransition = returning
            ? .offset(x: returningFrom == .delete ? -700 : 700, y: 40)
            : .opacity
        return CleanupCard(item: item, calendar: calendar, locale: locale) {
            thumbnail(item)
        }
        .overlay(alignment: .topLeading) {
            if isTop { stamp(.keep).opacity(stampOpacity(for: .keep)) }
        }
        .overlay(alignment: .topTrailing) {
            if isTop { stamp(.delete).opacity(stampOpacity(for: .delete)) }
        }
        // Narrower and lower, so each card behind shows a strip below the one
        // in front of it.
        .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .bottom)
        .offset(y: CGFloat(depth) * peek)
        .offset(isTop ? drag : .zero)
        .rotationEffect(.degrees(isTop && !reduceMotion ? Double(drag.width / 24) : 0), anchor: .bottom)
        .opacity(isTop && isLeaving && reduceMotion ? 0 : 1)
        .zIndex(Double(3 - depth))
        .allowsHitTesting(isTop)
        .gesture(dragGesture(for: item.id))
        .transition(.asymmetric(insertion: entry, removal: .identity))
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!isTop)
        .accessibilityHint(Text(verbatim: "Chọn hành động Xoá hoặc Giữ"))
        .accessibilityAction(named: Text(verbatim: "Xoá")) { commit(.delete) }
        .accessibilityAction(named: Text(verbatim: "Giữ")) { commit(.keep) }
    }

    private func stampOpacity(for decision: CleanupSession.Decision) -> Double {
        let toward = decision == .delete ? -drag.width : drag.width
        return Double(min(max(toward / threshold, 0), 1))
    }

    /// "XOÁ" / "GIỮ" stamped on the corner the card is heading away from.
    private func stamp(_ decision: CleanupSession.Decision) -> some View {
        let isDelete = decision == .delete
        return Label {
            Text(verbatim: isDelete ? "XOÁ" : "GIỮ")
        } icon: {
            Image(systemName: isDelete ? "trash.fill" : "checkmark")
        }
        .font(.title3.weight(.heavy))
        .foregroundStyle(theme.onFill)
        .padding(.horizontal, LabSpacing.sm)
        .padding(.vertical, LabSpacing.xs)
        .background(theme.fill(isDelete ? .negative : .positive), in: Capsule())
        .rotationEffect(.degrees(isDelete ? 12 : -12))
        .padding(LabSpacing.lg)
        .accessibilityHidden(true)
    }

    /// The drag on card `id`. It moves and decides that card only while it is
    /// on top: if the deck changes under the finger, letting go decides
    /// nothing and the card goes back.
    private func dragGesture(for id: CleanupItem.ID) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !isLeaving, id == session.current?.id else { return }
                drag = value.translation
                let isPast = abs(value.translation.width) >= threshold
                if isPast != isPastThreshold { isPastThreshold = isPast }
            }
            .onEnded { value in
                guard !isLeaving else { return }
                guard id == session.current?.id else {
                    settle()
                    return
                }
                let width = value.translation.width
                let flung = value.predictedEndTranslation.width
                // Where the card is decides first — it matches the stamp on
                // it, fully shown from the threshold on — and a fling only
                // for a card that has not reached it.
                if width <= -threshold || (abs(width) < threshold && flung < -threshold * 2.5) {
                    commit(.delete)
                } else if width >= threshold || (abs(width) < threshold && flung > threshold * 2.5) {
                    commit(.keep)
                } else {
                    settle()
                }
            }
    }

    /// Puts the top card back in the middle, unless it is flying off.
    private func settle() {
        guard !isLeaving else { return }
        isPastThreshold = false
        guard drag != .zero else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .bouncy) { drag = .zero }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: LabSpacing.xl) {
            DeckButton("Xoá", systemImage: "trash", tint: .negative, size: 68) { commit(.delete) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(session.current == nil)
            DeckButton("Hoàn tác", systemImage: "arrow.uturn.backward", tint: nil, size: 52) { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(session.lastDecision == nil)
                .padding(.top, 8)
            DeckButton("Giữ", systemImage: "checkmark", tint: .positive, size: 68) { commit(.keep) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(session.current == nil)
        }
    }

    /// Flies the top card off in the decision's direction (fades it with
    /// Reduce Motion), then records the decision.
    private func commit(_ decision: CleanupSession.Decision) {
        guard !isLeaving, let item = session.current else { return }
        decisions += 1
        isPastThreshold = false
        let direction: CGFloat = decision == .delete ? -1 : 1
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeIn(duration: 0.2)) {
            isLeaving = true
            if !reduceMotion {
                drag = CGSize(width: direction * 700, height: drag.height + 60)
            }
        } completion: {
            let decided: CleanupItem? = withAnimation(.snappy(duration: 0.3)) {
                drag = .zero
                isLeaving = false
                // The card that flew off, not whatever is on top now: the
                // deck may have changed while it was in the air.
                return session.decide(decision, expecting: item.id)
            }
            guard decided != nil else { return }
            let verb = decision == .delete ? "Sẽ xoá" : "Giữ"
            let message: String = "\(verb) \(item.category.title.lowercased()). Còn \(session.remainingCount) ảnh."
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Brings the last card back, in from the side it left — not while a card
    /// is being dragged, which would put the finger on the card coming back.
    private func undo() {
        guard !isLeaving, !isDragging, let last = session.lastDecision else { return }
        returningFrom = last
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.35)) {
            returningID = session.undo()?.id
        } completion: {
            returningID = nil
        }
    }
}

/// A photo card: the picture, and under it when it was taken and its size.
private struct CleanupCard<Content: View>: View {
    let item: CleanupItem
    let calendar: Calendar
    let locale: Locale
    let content: Content
    @Environment(\.labTheme) private var theme

    init(item: CleanupItem, calendar: Calendar, locale: Locale, @ViewBuilder content: () -> Content) {
        self.item = item
        self.calendar = calendar
        self.locale = locale
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LabRadius.xl, style: .continuous)
        let date = item.date.formatted(calendar.dateFormat(locale: locale).day().month(.twoDigits).year())
        VStack(spacing: 0) {
            // Clear, then the photo on top: an aspect-filled image fills the
            // card and is cropped, instead of stretching the layout.
            Color.clear
                .overlay { content }
                .clipped()
            HStack(spacing: LabSpacing.xs) {
                Label {
                    Text(verbatim: date)
                } icon: {
                    Image(systemName: "calendar")
                }
                Spacer(minLength: LabSpacing.xs)
                Text(verbatim: ByteSize.string(item.bytes))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.secondaryLabel)
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
            .background(theme.surface)
        }
        .background(theme.surfaceSecondary)
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.separator, lineWidth: 1) }
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.category.title), chụp ngày \(date), \(ByteSize.string(item.bytes))"))
    }
}

/// A round deck button with its word under it, so it never relies on the
/// icon alone.
private struct DeckButton: View {
    let title: String
    let systemImage: String
    /// `nil`: a neutral secondary button.
    let tint: LabTint?
    let size: CGFloat
    let action: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String, tint: LabTint?, size: CGFloat, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: LabSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(tint.map { theme.text($0) } ?? theme.label)
                    .frame(width: size, height: size)
                    .background(tint.map { theme.tonalFill($0) } ?? theme.surfaceSecondary, in: Circle())
                    .overlay { Circle().strokeBorder(theme.separator, lineWidth: 1) }
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.label)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

/// A photo in the review grid. Marked photos carry a red check; tapping one
/// keeps it (dimmed, "Giữ lại"), tapping again marks it again.
public struct ReviewTile<Thumbnail: View>: View {
    private let item: CleanupItem
    private let isMarked: Bool
    private let thumbnail: Thumbnail
    private let action: () -> Void
    @Environment(\.labTheme) private var theme

    public init(_ item: CleanupItem, isMarked: Bool, action: @escaping () -> Void, @ViewBuilder thumbnail: () -> Thumbnail) {
        self.item = item
        self.isMarked = isMarked
        self.action = action
        self.thumbnail = thumbnail()
    }

    public var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail }
                .clipped()
                .overlay {
                    if !isMarked { theme.canvas.opacity(0.55) }
                }
                .overlay(alignment: .topTrailing) { badge }
                .overlay(alignment: .bottomLeading) {
                    if !isMarked {
                        Text(verbatim: "Giữ lại")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.onFill)
                            .padding(.horizontal, LabSpacing.xs)
                            .padding(.vertical, 2)
                            .background(theme.fill(.positive), in: Capsule())
                            .padding(LabSpacing.xs)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isMarked)
        .accessibilityLabel(Text(verbatim: "\(item.category.title), \(ByteSize.string(item.bytes))"))
        .accessibilityValue(Text(verbatim: isMarked ? "Sẽ xoá" : "Giữ lại"))
        .accessibilityAddTraits(isMarked ? .isSelected : [])
        .accessibilityHint(Text(verbatim: isMarked ? "Chạm hai lần để giữ lại" : "Chạm hai lần để xoá"))
    }

    private var badge: some View {
        ZStack {
            if isMarked {
                Circle().fill(theme.fill(.negative))
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(theme.onFill)
            }
            Circle().strokeBorder(.white, lineWidth: 2)
        }
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.35), radius: 2)
        .padding(LabSpacing.xs)
        .accessibilityHidden(true)
    }
}

// MARK: - Deleting

/// What the delete buttons of a cleanup review say: shared by
/// `CleanupReviewScreen` and `SimilarPhotosScreen`.
enum CleanupDeleteText {
    static let deletionNote = "iOS sẽ hỏi lại một lần. Ảnh xoá nằm trong Đã xoá gần đây 30 ngày."

    /// How far the free tier goes, when it does not cover every marked photo.
    /// - Parameter place: where the first photos are, after "đầu tiên":
    ///   "trong lưới".
    static func allowanceNote(free: Int, place: String) -> String {
        free == 0
            ? "Bạn đã dùng hết lượt xoá miễn phí."
            : "Lượt miễn phí còn lại đủ xoá \(VietnameseNumber.grouped(free)) ảnh đầu tiên \(place)."
    }

    /// Marked photos the buttons leave out until they have been on screen.
    static func unseenNote(_ unseen: Int) -> String {
        "Cuộn để xem nốt \(VietnameseNumber.grouped(unseen)) ảnh sẽ xoá."
    }
}

/// The delete buttons at the bottom of a cleanup review. The button says
/// exactly how many photos and how much space. When the marked photos are
/// more than the free allowance left, it offers both: delete the free ones
/// now, or unlock the full version.
struct CleanupDeleteTray: View {
    /// Marked for deletion, in the screen's order: what the buttons delete.
    let marked: [CleanupItem]
    /// The first of `marked` the free allowance covers: all of them in the
    /// full version.
    let free: [CleanupItem]
    /// Also marked, but not on screen yet, so left out of `marked`: the
    /// buttons say they take the photos seen ("đã xem"), and a line asks to
    /// scroll to the rest — at every text size, since it is why the buttons
    /// count fewer photos than the screen.
    var unseen = 0
    let isDeleting: Bool
    /// Off at accessibility text sizes. The notes then scroll with the photos
    /// (`CleanupDeleteNotes`): in the pinned tray they would cover most of
    /// them.
    let showsNotes: Bool
    /// Where the free photos are, for the allowance note.
    let place: String
    /// Deletes what this tray counted (`free`), less any photo no longer
    /// marked when tapped (`CleanupMath.stillMarked`): never one it did not
    /// count, nor more than the free allowance covers.
    let onDelete: () -> Void
    let onUnlock: () -> Void
    @Environment(\.labTheme) private var theme

    var body: some View {
        VStack(spacing: LabSpacing.xs) {
            if marked.isEmpty {
                Button {} label: {
                    Text(verbatim: unseen > 0
                        ? "Cuộn để xem \(VietnameseNumber.grouped(unseen)) ảnh sẽ xoá"
                        : "Chưa chọn ảnh nào để xoá")
                }
                .buttonStyle(.labFilled(.negative))
                .disabled(true)
            } else if free.count == marked.count {
                Button(action: onDelete) {
                    Label {
                        Text(verbatim: "Xoá \(VietnameseNumber.grouped(marked.count)) ảnh\(seenSuffix) · \(ByteSize.string(CleanupMath.bytes(of: marked)))")
                    } icon: {
                        Image(systemName: "trash.fill")
                    }
                }
                .buttonStyle(.labFilled(.negative))
                .disabled(isDeleting)
            } else {
                if showsNotes {
                    Text(verbatim: CleanupDeleteText.allowanceNote(free: free.count, place: place))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.label)
                        .multilineTextAlignment(.center)
                }
                Button(action: onUnlock) {
                    Text(verbatim: "Mở khoá để xoá cả \(VietnameseNumber.grouped(marked.count)) ảnh\(seenSuffix)")
                }
                .buttonStyle(.labFilled)
                .disabled(isDeleting)
                if !free.isEmpty {
                    Button(action: onDelete) {
                        Text(verbatim: "Xoá \(VietnameseNumber.grouped(free.count)) ảnh đầu tiên · \(ByteSize.string(CleanupMath.bytes(of: free)))")
                    }
                    .buttonStyle(.labTonal(.negative))
                    .disabled(isDeleting)
                }
            }
            if unseen > 0, !marked.isEmpty {
                Text(verbatim: CleanupDeleteText.unseenNote(unseen))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsNotes {
                Text(verbatim: CleanupDeleteText.deletionNote)
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

    /// After the count, when some marked photos are not on screen yet.
    private var seenSuffix: String { unseen > 0 ? " đã xem" : "" }
}

/// The delete tray's notes, above the photos at accessibility text sizes.
struct CleanupDeleteNotes: View {
    let marked: [CleanupItem]
    let free: [CleanupItem]
    let place: String
    @Environment(\.labTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: LabSpacing.xs) {
            if !marked.isEmpty, free.count < marked.count {
                Text(verbatim: CleanupDeleteText.allowanceNote(free: free.count, place: place))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: CleanupDeleteText.deletionNote)
                .font(.footnote)
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Similar photos

/// A shot in a group of similar photos. Every shot is shown at full
/// strength, kept or not, since the point is to compare them:
/// - kept: a green "Giữ" under it;
/// - marked for deletion: the red check of the review grid;
/// - the sharpest: sparkles in the top corner, kept or not, which
///   `SimilarPhotosScreen`'s header explains, and VoiceOver reads as "nét nhất";
/// - a favourite: a heart, and it cannot be marked.
public struct SimilarTile<Thumbnail: View>: View {
    private let photo: SimilarPhoto
    private let isKept: Bool
    private let isOnlyKept: Bool
    private let isSharpest: Bool
    private let position: (number: Int, count: Int)
    private let thumbnail: Thumbnail
    private let action: () -> Void
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - isOnlyKept: the one shot its group keeps, which cannot be marked
    ///     until another is kept; VoiceOver's hint says so instead of
    ///     offering a tap that would be refused.
    ///   - position: the shot's place in its group, for VoiceOver:
    ///     "Ảnh 2 trong 5".
    public init(
        _ photo: SimilarPhoto,
        isKept: Bool,
        isOnlyKept: Bool = false,
        isSharpest: Bool,
        position: (number: Int, count: Int),
        action: @escaping () -> Void,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) {
        self.photo = photo
        self.isKept = isKept
        self.isOnlyKept = isKept && isOnlyKept
        self.isSharpest = isSharpest
        self.position = position
        self.action = action
        self.thumbnail = thumbnail()
    }

    public var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail }
                .clipped()
                .overlay(alignment: .topLeading) {
                    if isSharpest {
                        // An icon, as small as the mark across from it: a word
                        // here runs into the mark on a tile a third of the
                        // screen wide. The screen's header says what it means.
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(LabSpacing.xs)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !photo.item.isFavorite { badge }
                }
                .overlay(alignment: .bottomLeading) {
                    if isKept {
                        Text(verbatim: "Giữ")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.onFill)
                            .padding(.horizontal, LabSpacing.xs)
                            .padding(.vertical, 2)
                            .background(theme.fill(.positive), in: Capsule())
                            .padding(LabSpacing.xxs)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if photo.item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 2)
                            .padding(LabSpacing.xs)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isKept ? theme.fill(.positive) : .clear, lineWidth: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isKept)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: isKept ? "Giữ" : "Sẽ xoá"))
        .accessibilityAddTraits(isKept ? [] : .isSelected)
        .accessibilityHint(Text(verbatim: hint))
    }

    private var label: String {
        var parts = ["Ảnh \(position.number) trong \(position.count)"]
        if isSharpest { parts.append("nét nhất") }
        if photo.item.isFavorite { parts.append("yêu thích") }
        parts.append(ByteSize.string(photo.item.bytes))
        return parts.joined(separator: ", ")
    }

    /// What a double tap does, or why it does nothing: the screen refuses
    /// to mark a favourite or the last shot its group keeps.
    private var hint: String {
        if photo.item.isFavorite { return "Ảnh yêu thích luôn được giữ" }
        if isOnlyKept { return "Mỗi nhóm giữ lại ít nhất một ảnh" }
        return isKept ? "Chạm hai lần để đánh dấu xoá" : "Chạm hai lần để giữ lại"
    }

    /// The review grid's mark: a red check when it will be deleted, an empty
    /// ring when it is kept and can be marked.
    private var badge: some View {
        ZStack {
            if !isKept {
                Circle().fill(theme.fill(.negative))
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(theme.onFill)
            }
            Circle().strokeBorder(.white, lineWidth: 2)
        }
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.35), radius: 2)
        .padding(LabSpacing.xs)
        .accessibilityHidden(true)
    }
}
#endif
