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
            controls
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: decisions)
        .sensoryFeedback(.selection, trigger: isPastThreshold)
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
        .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .top)
        .offset(y: CGFloat(depth) * 16)
        .offset(isTop ? drag : .zero)
        .rotationEffect(.degrees(isTop && !reduceMotion ? Double(drag.width / 24) : 0), anchor: .bottom)
        .opacity(isTop && isLeaving && reduceMotion ? 0 : 1)
        .zIndex(Double(3 - depth))
        .allowsHitTesting(isTop)
        .gesture(dragGesture)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isLeaving else { return }
                drag = value.translation
                let isPast = abs(value.translation.width) > threshold
                if isPast != isPastThreshold { isPastThreshold = isPast }
            }
            .onEnded { value in
                guard !isLeaving else { return }
                let width = value.translation.width
                let flung = value.predictedEndTranslation.width
                // Where the card is decides first — it matches the stamp on
                // it — and a fling only for a card still near the middle.
                if width < -threshold || (abs(width) <= threshold && flung < -threshold * 2.5) {
                    commit(.delete)
                } else if width > threshold || (abs(width) <= threshold && flung > threshold * 2.5) {
                    commit(.keep)
                } else {
                    isPastThreshold = false
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .bouncy) { drag = .zero }
                }
            }
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

    /// Brings the last card back, in from the side it left.
    private func undo() {
        guard !isLeaving, let last = session.lastDecision else { return }
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
#endif
