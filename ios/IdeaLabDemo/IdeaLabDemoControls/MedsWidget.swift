import IdeaLabCore
import IdeaLabWidgets
import SwiftUI
import WidgetKit

/// "Uống thuốc": the parent's next dose, or the one not taken yet, on the
/// Home Screen and the Lock Screen (`DoseWidgetView`), from iOS 17. The app
/// shares its medicines and answers through the App Group and reloads the
/// widget when they change (`DoseWidgetStore`); the timeline changes by
/// itself as doses fall due, turn late and stop waiting
/// (`DoseWidgetTimeline`). A tap opens the parent's screen.
struct MedsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MedsWidgetShared.kind, provider: MedsTimelineProvider()) { entry in
            MedsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Uống thuốc")
        .description("Liều đến giờ hay chưa uống, và liều tiếp theo.")
        .supportedFamilies(DoseWidgetLayout.families)
    }
}

/// One moment of the widget, on the parent's clock.
struct MedsTimelineEntry: TimelineEntry {
    let dose: DoseWidgetEntry
    let calendar: Calendar

    var date: Date { dose.date }

    /// The sample morning, for the widget gallery and while loading: a pill
    /// not taken at 07:00, and vitamin D due at 09:30.
    static var sample: MedsTimelineEntry {
        let calendar = LedgerSamples.calendar
        let entry = DoseWidgetTimeline.entry(
            at: LedgerSamples.referenceNow, medications: MedicationSamples.medications, log: MedicationSamples.log(), calendar: calendar
        )
        return MedsTimelineEntry(dose: entry, calendar: calendar)
    }
}

struct MedsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedsTimelineEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (MedsTimelineEntry) -> Void) {
        guard !context.isPreview, let snapshot = MedsWidgetShared.store.snapshot,
              let now = snapshot.entries(from: .now).first
        else {
            completion(.sample)
            return
        }
        completion(MedsTimelineEntry(dose: now, calendar: snapshot.calendar))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MedsTimelineEntry>) -> Void) {
        let now = Date.now
        guard let snapshot = MedsWidgetShared.store.snapshot else {
            // The app has shared nothing yet: it reloads the widget when it does.
            let empty = MedsTimelineEntry(dose: DoseWidgetEntry(date: now, headline: .noMedicines), calendar: .current)
            completion(Timeline(entries: [empty], policy: .never))
            return
        }
        let calendar = snapshot.calendar
        let entries = snapshot.entries(from: now).map { MedsTimelineEntry(dose: $0, calendar: calendar) }
        // Nothing changes after the last entry until tomorrow ends.
        completion(Timeline(entries: entries, policy: .after(snapshot.timelineEnd(from: now))))
    }
}

struct MedsWidgetEntryView: View {
    let entry: MedsTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        DoseWidgetView(entry: entry.dose, layout: DoseWidgetLayout(family) ?? .small, calendar: entry.calendar)
            .containerBackground(for: .widget) {
                DoseWidgetBackground()
            }
            .widgetURL(MedsWidgetShared.url)
    }
}
