#if os(iOS)
import IdeaLabCore
import SwiftUI
import UIKit
import WidgetKit

/// The sizes the parent's widget comes in: on the Home Screen, small and
/// medium; on the Lock Screen, a rectangle and a circle below the clock and
/// a line above it.
public enum DoseWidgetLayout: String, Hashable, Sendable, CaseIterable {
    case small
    case medium
    case rectangular
    case circular
    case inline

    /// The layout for a WidgetKit family; `nil` for one the widget does not
    /// come in.
    public init?(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .accessoryRectangular: self = .rectangular
        case .accessoryCircular: self = .circular
        case .accessoryInline: self = .inline
        default: return nil
        }
    }

    /// The families to list in the widget's `supportedFamilies`.
    public static var families: [WidgetFamily] {
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
    }
}

/// The parent's widget (`DoseWidgetEntry`): the dose waiting for an answer,
/// else today's next, else how the day went, with the dose's time large and
/// the pill as the parent knows it.
///
/// The words say it all, with a symbol beside them, as the Lock Screen and a
/// tinted Home Screen draw widgets in one colour. A medicine's name is
/// marked private (`privacySensitive`): with Lock Screen widgets turned off
/// under Settings › Face ID & Passcode › Allow Access When Locked, the
/// locked phone shows the time and what is due, not which medicine. Safe in
/// a widget extension: SwiftUI and WidgetKit only, no `IdeaLabUI`.
///
/// The medium widget can answer the dose waiting with "ĐÃ UỐNG"
/// (`answerButton`). Taken there, it shows "Đã uống" with "Hoàn tác" for a
/// moment before moving on, "Hoàn tác" at the top, away from where "ĐÃ
/// UỐNG" stood, so a second tap undoes nothing and answers no other dose.
/// The other sizes open the app: a small widget is one tap target, and the
/// Lock Screen's buttons wait for the phone to be unlocked.
public struct DoseWidgetView<AnswerButton: View>: View {
    private let entry: DoseWidgetEntry
    private let layout: DoseWidgetLayout
    private let calendar: Calendar
    private let answerButton: ((DoseWidgetAnswer) -> AnswerButton)?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - calendar: the parent's (`DoseWidgetSnapshot.calendar`), whose
    ///     clock the times are written in.
    ///   - answerButton: the medium widget's button for `entry.answer`: a
    ///     `Button(intent:)` with the app's intent that records the answer
    ///     (`DoseWidgetStore.record`), labelled
    ///     `DoseWidgetAnswerLabel(answer)`.
    public init(
        entry: DoseWidgetEntry, layout: DoseWidgetLayout, calendar: Calendar,
        @ViewBuilder answerButton: @escaping (DoseWidgetAnswer) -> AnswerButton
    ) {
        self.init(entry: entry, layout: layout, calendar: calendar, button: answerButton)
    }

    private init(
        entry: DoseWidgetEntry, layout: DoseWidgetLayout, calendar: Calendar, button: ((DoseWidgetAnswer) -> AnswerButton)?
    ) {
        self.entry = entry
        self.layout = layout
        self.calendar = calendar
        answerButton = button
    }

    public var body: some View {
        switch layout {
        case .small: whole(small)
        case .medium: medium
        case .rectangular: whole(rectangular, showingAnswered: false)
        case .circular: whole(circular, showingAnswered: false)
        case .inline: whole(inline, showingAnswered: false)
        }
    }

    /// One element for VoiceOver, read in sentences.
    private func whole(_ content: some View, showingAnswered: Bool = true) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: DoseWidgetCopy.spoken(for: entry, calendar: calendar, showingAnswered: showingAnswered)))
    }

    // MARK: - Home Screen

    /// What is due and when, then which pill: the headline and the time
    /// always show in full, the medicine takes two lines when there is room
    /// for them. At accessibility sizes, the words and the time alone; the
    /// medium widget names the medicine beside them. A dose just taken on
    /// the widget shows in place of the headline's.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            headline
                .layoutPriority(2)
            Spacer(minLength: 0)
            if let time = shownTime {
                HStack(spacing: 8) {
                    Text(verbatim: time)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    // The pill as the parent knows it.
                    if let dose = shownDose, !isLarge {
                        DosePillGlyph(style: dose.medication.style)
                            .frame(width: 30, height: 30)
                    }
                }
                .layoutPriority(2)
            }
            if let dose = shownDose, !isLarge {
                medicine(dose, lines: 2)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The small widget, and beside it the day: the count, other doses
    /// waiting, the doses to come. With a button, "ĐÃ UỐNG" at the foot of
    /// the second column, or "Hoàn tác" at its head.
    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            // The whole widget in sentences; the buttons after.
            whole(small)
            VStack(alignment: .leading, spacing: 6) {
                if let answer = entry.answer, let answerButton, !offersTake {
                    button(answer, answerButton)
                }
                day
                    .accessibilityHidden(true)
                if let answer = entry.answer, let answerButton, offersTake {
                    Spacer(minLength: 4)
                    button(answer, answerButton)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Whether the medium widget offers "ĐÃ UỐNG": a dose waits, and the app
    /// gave a button.
    private var offersTake: Bool {
        guard answerButton != nil, case .take = entry.answer else { return false }
        return true
    }

    /// Whether the medium widget shows a button, "ĐÃ UỐNG" or "Hoàn tác".
    private var offersButton: Bool {
        answerButton != nil && entry.answer != nil
    }

    /// The second column's words: VoiceOver has read them with the first. A
    /// button takes the room of the doses to come, and at accessibility
    /// sizes that of the other doses waiting too: they show once it goes.
    @ViewBuilder private var day: some View {
        if isLarge {
            // The medicine, for which the first column has no room.
            if let dose = shownDose {
                medicine(dose, lines: offersButton ? 2 : 3)
                    .layoutPriority(1)
            }
            if !offersButton {
                alsoWaiting
            }
        } else {
            if let progress = DoseWidgetCopy.progress(for: entry) {
                Text(verbatim: progress)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            alsoWaiting
            if !offersButton {
                ForEach(entry.laterToday) { dose in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: LedgerExport.time(dose.time, calendar))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                        Text(verbatim: dose.medication.name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                if entry.laterToday.isEmpty, entry.total > 0 {
                    Text(verbatim: "Không còn liều nào sau đó hôm nay")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The app's button for `answer`, read with its dose's name.
    private func button(_ answer: DoseWidgetAnswer, _ make: (DoseWidgetAnswer) -> AnswerButton) -> some View {
        make(answer)
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: DoseWidgetCopy.spoken(for: answer, on: entry.date, calendar: calendar)))
    }

    // MARK: - Lock Screen

    /// The headline, then the time and the medicine, then the day's count,
    /// one line each; at accessibility sizes the first two, and the
    /// headline's words without their symbol.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if isLarge {
                    Text(verbatim: DoseWidgetCopy.title(for: entry))
                } else {
                    Label {
                        Text(verbatim: DoseWidgetCopy.title(for: entry))
                    } icon: {
                        Image(systemName: symbol)
                    }
                }
            }
            .font(.headline)
            .widgetAccentable()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let dose = entry.dose, let time = DoseWidgetCopy.time(for: entry, calendar: calendar) {
                HStack(spacing: 4) {
                    Text(verbatim: time)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(verbatim: DoseWidgetCopy.medicine(dose))
                        .privacySensitive()
                }
                .lineLimit(1)
                .minimumScaleFactor(isLarge ? 0.7 : 1)
            }
            if !isLarge, let progress = DoseWidgetCopy.progress(for: entry) {
                Text(verbatim: progress)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The symbol over the time, or the day's count; at accessibility sizes
    /// the time alone, as large as the circle holds.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if !isLarge {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .widgetAccentable()
                }
                Text(verbatim: circularValue)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .padding(6)
        }
    }

    private var inline: some View {
        Label {
            Text(verbatim: DoseWidgetCopy.inline(for: entry, calendar: calendar))
        } icon: {
            Image(systemName: symbol)
        }
    }

    // MARK: - Parts

    /// What the dose needs, in the headline's colour, with its symbol; at
    /// accessibility sizes the words alone, across the widget, as they need
    /// the room. "Đã uống" while a dose just taken on the widget shows.
    private var headline: some View {
        let title = entry.answered == nil ? DoseWidgetCopy.title(for: entry) : DoseWidgetCopy.answered
        return Group {
            if isLarge {
                Text(verbatim: title)
                    .lineLimit(3)
            } else {
                Label {
                    Text(verbatim: title)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: entry.answered == nil ? symbol : "checkmark.circle.fill")
                }
            }
        }
        .font(.footnote.weight(.semibold))
        .minimumScaleFactor(0.7)
        .foregroundStyle(entry.answered == nil ? tint : Color(LabPalette.meds.positive))
        .widgetAccentable()
    }

    /// The dose the Home Screen shows: the one just taken on the widget, else
    /// the headline's.
    private var shownDose: ScheduledDose? {
        entry.answered?.dose ?? entry.dose
    }

    private var shownTime: String? {
        if let answered = entry.answered {
            return DoseWidgetCopy.clock(of: answered.dose, on: entry.date, calendar: calendar)
        }
        return DoseWidgetCopy.time(for: entry, calendar: calendar)
    }

    /// "Thuốc huyết áp · 1 viên", marked private.
    private func medicine(_ dose: ScheduledDose, lines: Int) -> some View {
        Text(verbatim: DoseWidgetCopy.medicine(dose))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(lines)
            .minimumScaleFactor(isLarge ? 0.7 : 1)
            .privacySensitive()
    }

    /// "+1 liều khác chưa uống", in the headline's colour.
    @ViewBuilder private var alsoWaiting: some View {
        if let also = DoseWidgetCopy.alsoWaiting(for: entry) {
            Text(verbatim: also)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(isLarge ? 0.7 : 1)
                .widgetAccentable()
        }
    }

    private var isLarge: Bool {
        typeSize.isAccessibilitySize
    }

    /// The dose's time, or the day's count once it is over.
    private var circularValue: String {
        switch entry.headline {
        case let .due(dose), let .late(dose), let .next(dose):
            LedgerExport.time(dose.time, calendar)
        case .dayOver:
            entry.total > 0 ? "\(entry.taken)/\(entry.total)" : "–"
        case .noMedicines, .openApp:
            "–"
        }
    }

    /// What the headline means, as a symbol, so it reads without colour.
    private var symbol: String {
        switch entry.headline {
        case .due: "bell.fill"
        case .late: "exclamationmark.circle.fill"
        case .next: "clock"
        case .dayOver:
            if entry.total == 0 {
                "pills"
            } else {
                entry.taken < entry.total ? "circle.lefthalf.filled" : "checkmark.circle.fill"
            }
        case .noMedicines: "pills"
        case .openApp: "questionmark.circle"
        }
    }

    /// Teal as the meds app's accent, amber for a late dose, green for a day
    /// with every dose taken.
    private var tint: Color {
        let palette = LabPalette.meds
        switch entry.headline {
        case .due, .next: return Color(palette.accentText)
        case .late: return Color(palette.warning)
        case .dayOver: return entry.total > 0 && entry.taken == entry.total ? Color(palette.positive) : Color(palette.secondaryLabel)
        case .noMedicines, .openApp: return Color(palette.secondaryLabel)
        }
    }
}

public extension DoseWidgetView where AnswerButton == EmptyView {
    /// The widget without buttons: a tap opens the app.
    init(entry: DoseWidgetEntry, layout: DoseWidgetLayout, calendar: Calendar) {
        self.init(entry: entry, layout: layout, calendar: calendar, button: nil)
    }
}

/// The words and look of the widget's buttons (`DoseWidgetAnswer`), for the
/// app's `Button(intent:)`: "ĐÃ UỐNG" filled in the meds app's colour, as
/// wide as its column and 44 points tall; "Hoàn tác" small and outlined. On
/// a tinted or clear Home Screen, which draws a widget in one colour, "ĐÃ
/// UỐNG" is outlined too, so its words do not vanish into its fill.
public struct DoseWidgetAnswerLabel: View {
    private let answer: DoseWidgetAnswer
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ answer: DoseWidgetAnswer) {
        self.answer = answer
    }

    public var body: some View {
        let palette = LabPalette.meds
        let filled = renderingMode == .fullColor
        switch answer {
        case .take:
            words(symbol: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(filled ? Color(palette.onFill) : Color(palette.accentText))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if filled {
                        Capsule().fill(Color(palette.accent))
                    } else {
                        Capsule().strokeBorder(lineWidth: 2)
                    }
                }
                .contentShape(Capsule())
                .widgetAccentable()
        case .undo:
            words(symbol: "arrow.uturn.backward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(palette.accentText))
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().strokeBorder(Color(palette.accentText), lineWidth: 1.5))
                .contentShape(Capsule())
                .widgetAccentable()
        }
    }

    /// The words with their symbol; at accessibility sizes the words alone,
    /// which then need the room.
    @ViewBuilder private func words(symbol: String) -> some View {
        let title = DoseWidgetCopy.title(for: answer)
        Group {
            if typeSize.isAccessibilitySize {
                Text(verbatim: title)
            } else {
                Label(title, systemImage: symbol)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The widget's background on the Home Screen: the meds app's card colour,
/// light or dark. Pass it to `containerBackground(for: .widget)`.
public struct DoseWidgetBackground: View {
    public init() {}

    public var body: some View {
        Color(LabPalette.meds.surface)
    }
}

/// A pill drawn from its style (`PillStyle`): its shape and colour, the two
/// halves of a capsule, with an outline so a white pill shows on white.
struct DosePillGlyph: View {
    let style: PillStyle

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            shape
                .frame(width: size.width, height: height(for: size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func height(for width: CGFloat) -> CGFloat {
        switch style.shape {
        case .round: width
        case .oval: width * 0.72
        case .oblong, .capsule: width * 0.46
        }
    }

    @ViewBuilder private var shape: some View {
        let outline = Color(LabPalette.meds.separator)
        switch style.shape {
        case .round:
            Circle().fill(Color(style.color.rgb)).overlay(Circle().strokeBorder(outline, lineWidth: 1))
        case .oval:
            Ellipse().fill(Color(style.color.rgb)).overlay(Ellipse().strokeBorder(outline, lineWidth: 1))
        case .oblong:
            Capsule().fill(Color(style.color.rgb)).overlay(Capsule().strokeBorder(outline, lineWidth: 1))
        case .capsule:
            HStack(spacing: 0) {
                Rectangle().fill(Color(style.color.rgb))
                Rectangle().fill(Color((style.secondColor ?? style.color).rgb))
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(outline, lineWidth: 1))
        }
    }
}

extension Color {
    /// A palette role, light or dark, and with more contrast when asked.
    init(_ swatch: Swatch) {
        self.init(uiColor: UIColor { traits in
            let rgb = swatch.resolve(dark: traits.userInterfaceStyle == .dark, highContrast: traits.accessibilityContrast == .high)
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
#endif
