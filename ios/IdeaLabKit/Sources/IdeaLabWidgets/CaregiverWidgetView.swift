#if os(iOS)
import IdeaLabCore
import SwiftUI
import WidgetKit

/// The family's widget (`CaregiverWidgetEntry`), as their screen
/// (`CaregiverScreen`) says it: how many of the parent's doses so far were
/// taken, the dose late by its time, and when the parent's phone last sent
/// news, so old news does not look fresh.
///
/// The words say it all, with a symbol beside them, as the Lock Screen and
/// a tinted Home Screen draw widgets in one colour; a late dose is amber on
/// the Home Screen, as on the family's screen. The Lock Screen names no
/// medicine, as anyone near the phone can read it; the Home Screen names
/// the late one, marked private (`privacySensitive`). A tap opens the app
/// (its `widgetURL`), where "Gọi" and "Nhắc lại" are. Safe in a widget
/// extension: SwiftUI and WidgetKit only, no `IdeaLabUI`.
public struct CaregiverWidgetView: View {
    private let entry: CaregiverWidgetEntry
    private let layout: DoseWidgetLayout
    private let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - layout: one of `families`; a medium widget is drawn as a small one.
    ///   - calendar: the parent's (`CaregiverWidgetSnapshot.calendar`), on
    ///     whose clock the times are written.
    public init(entry: CaregiverWidgetEntry, layout: DoseWidgetLayout, calendar: Calendar) {
        self.entry = entry
        self.layout = layout
        self.calendar = calendar
    }

    /// The families to list in the widget's `supportedFamilies`: the small
    /// one on the Home Screen, and the Lock Screen's three.
    public static var families: [WidgetFamily] {
        [.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline]
    }

    public var body: some View {
        Group {
            switch layout {
            case .small, .medium: small
            case .rectangular: rectangular
            case .circular: circular
            case .inline: inline
            }
        }
        // One element for VoiceOver, read in sentences; on the Lock Screen,
        // with no medicine named, as it shows none.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CaregiverWidgetCopy.spoken(
            for: entry, calendar: calendar, namingMedicines: layout == .small || layout == .medium
        )))
    }

    // MARK: - Home Screen

    /// The parent's name, then the news in large type: the late dose's
    /// time, or the day's count; what it means under it, then how fresh it
    /// is. At accessibility sizes, the headline's words and the time of the
    /// news alone.
    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            name
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Spacer(minLength: 0)
            if isLarge {
                Text(verbatim: CaregiverWidgetCopy.title(for: entry, calendar: calendar))
                    .font(.headline)
                    .foregroundStyle(tint)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(2)
            } else {
                if let value = largeValue {
                    Text(verbatim: value)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(entry.late.isEmpty ? Color(LabPalette.meds.label) : tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .layoutPriority(2)
                }
                Text(verbatim: caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(entry.late.isEmpty ? Color(LabPalette.meds.secondaryLabel) : tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(2)
                    .widgetAccentable()
                if let first = entry.late.first {
                    Text(verbatim: CaregiverWidgetCopy.moreLate(for: entry) ?? first.medication.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                        .layoutPriority(1)
                }
            }
            if let updated = CaregiverWidgetCopy.updated(for: entry, calendar: calendar) {
                Text(verbatim: updated)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)
                    .layoutPriority(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The late dose's time, or "1/3"; none before any dose was due.
    private var largeValue: String? {
        if let first = entry.late.first {
            return LedgerExport.time(first.time, calendar)
        }
        return entry.soFar > 0 ? "\(entry.taken)/\(entry.soFar)" : nil
    }

    /// What `largeValue` means: "chưa xác nhận" ("… hôm qua" for last
    /// night's), "liều đã uống", or the headline itself when there is no
    /// value.
    private var caption: String {
        if let first = entry.late.first {
            return calendar.isDate(first.time, inSameDayAs: entry.date) ? "chưa xác nhận" : "hôm qua, chưa xác nhận"
        }
        return entry.soFar > 0 ? "liều đã uống đến giờ" : CaregiverWidgetCopy.title(for: entry, calendar: calendar)
    }

    // MARK: - Lock Screen

    /// The parent's name, the headline, the time of the news: one line
    /// each. At accessibility sizes, the headline and the time of the news,
    /// shrunk to fit, without the symbol or the name, as the words need the
    /// room: the line above the clock names the parent. With the name, a
    /// line does not fit even at half size (AX-L's body is 33 points).
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLarge {
                Text(verbatim: CaregiverWidgetCopy.title(for: entry, calendar: calendar))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                Text(verbatim: CaregiverWidgetCopy.updated(for: entry, calendar: calendar) ?? entry.personName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                name
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(spacing: 4) {
                    Text(verbatim: CaregiverWidgetCopy.title(for: entry, calendar: calendar))
                        .fontWeight(.semibold)
                    if entry.late.count > 1 {
                        Text(verbatim: "+\(entry.late.count - 1)")
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let updated = CaregiverWidgetCopy.updated(for: entry, calendar: calendar) {
                    Text(verbatim: updated)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The late dose's time under a warning; else a ring filled by the doses
    /// taken so far, "1/3" inside it. At accessibility sizes, the value
    /// alone.
    @ViewBuilder private var circular: some View {
        if entry.late.isEmpty, entry.soFar > 0 {
            Gauge(value: Double(entry.taken), in: 0...Double(entry.soFar)) {
                Image(systemName: symbol)
            } currentValueLabel: {
                Text(verbatim: "\(entry.taken)/\(entry.soFar)")
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if !isLarge {
                        Image(systemName: symbol)
                            .font(.caption.weight(.semibold))
                            .widgetAccentable()
                    }
                    Text(verbatim: largeValue ?? "–")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(6)
            }
        }
    }

    private var inline: some View {
        Label {
            Text(verbatim: CaregiverWidgetCopy.inline(for: entry, calendar: calendar))
        } icon: {
            Image(systemName: symbol)
        }
    }

    // MARK: - Parts

    /// The parent's name with the news as a symbol; the name alone at
    /// accessibility sizes.
    @ViewBuilder private var name: some View {
        if isLarge {
            Text(verbatim: entry.personName)
                .lineLimit(1)
        } else {
            Label {
                Text(verbatim: entry.personName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: symbol)
            }
        }
    }

    private var isLarge: Bool {
        typeSize.isAccessibilitySize
    }

    /// What the news means, as a symbol, so it reads without colour: a
    /// warning while a dose is late, a tick once every dose so far was
    /// taken, a half circle while some were not, pills before any was due.
    private var symbol: String {
        if !entry.late.isEmpty { return "exclamationmark.triangle.fill" }
        if entry.allTaken { return "checkmark.circle.fill" }
        return entry.soFar > 0 ? "circle.lefthalf.filled" : "pills"
    }

    /// Amber while a dose is late, green once every dose so far was taken,
    /// the meds app's teal otherwise.
    private var tint: Color {
        let palette = LabPalette.meds
        if !entry.late.isEmpty { return Color(palette.warning) }
        if entry.allTaken { return Color(palette.positive) }
        return Color(palette.accentText)
    }
}
#endif
