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
public struct DoseWidgetView: View {
    private let entry: DoseWidgetEntry
    private let layout: DoseWidgetLayout
    private let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameter calendar: the parent's (`DoseWidgetSnapshot.calendar`),
    ///   whose clock the times are written in.
    public init(entry: DoseWidgetEntry, layout: DoseWidgetLayout, calendar: Calendar) {
        self.entry = entry
        self.layout = layout
        self.calendar = calendar
    }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: DoseWidgetCopy.spoken(for: entry, calendar: calendar)))
    }

    @ViewBuilder private var content: some View {
        switch layout {
        case .small: small
        case .medium: medium
        case .rectangular: rectangular
        case .circular: circular
        case .inline: inline
        }
    }

    // MARK: - Home Screen

    /// What is due and when, then which pill: the headline and the time
    /// always show in full, the medicine takes two lines when there is room
    /// for them. At accessibility sizes, the words and the time alone; the
    /// medium widget names the medicine beside them.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            headline
                .layoutPriority(2)
            Spacer(minLength: 0)
            if let time = DoseWidgetCopy.time(for: entry, calendar: calendar) {
                HStack(spacing: 8) {
                    Text(verbatim: time)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    // The pill as the parent knows it.
                    if let dose = entry.dose, !isLarge {
                        DosePillGlyph(style: dose.medication.style)
                            .frame(width: 30, height: 30)
                    }
                }
                .layoutPriority(2)
            }
            if let dose = entry.dose, !isLarge {
                medicine(dose, lines: 2)
                    .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            VStack(alignment: .leading, spacing: 6) {
                if isLarge {
                    // The medicine, for which the first column has no room.
                    if let dose = entry.dose {
                        medicine(dose, lines: 3)
                            .layoutPriority(1)
                    }
                    alsoWaiting
                } else {
                    if let progress = DoseWidgetCopy.progress(for: entry) {
                        Text(verbatim: progress)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    alsoWaiting
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
    /// the room.
    private var headline: some View {
        Group {
            if isLarge {
                Text(verbatim: DoseWidgetCopy.title(for: entry))
                    .lineLimit(3)
            } else {
                Label {
                    Text(verbatim: DoseWidgetCopy.title(for: entry))
                        .lineLimit(2)
                } icon: {
                    Image(systemName: symbol)
                }
            }
        }
        .font(.footnote.weight(.semibold))
        .minimumScaleFactor(0.7)
        .foregroundStyle(tint)
        .widgetAccentable()
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
        case .noMedicines:
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
        case .noMedicines: return Color(palette.secondaryLabel)
        }
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

private extension Color {
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
