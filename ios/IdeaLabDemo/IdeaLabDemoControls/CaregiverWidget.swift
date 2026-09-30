import IdeaLabCore
import IdeaLabWidgets
import SwiftUI
import WidgetKit

/// "Thuốc của Mẹ": on the family's phone, how many of the parent's doses so
/// far were taken, the one late by its time, and when the parent's phone
/// last sent news (`CaregiverWidgetView`), on the Lock Screen and the Home
/// Screen, from iOS 17. The app shares what the parent's phone sent through
/// the App Group and reloads the widget when it changes
/// (`CaregiverWidgetStore`); the timeline changes by itself as doses fall
/// due, turn late and stop waiting (`CaregiverWidgetTimeline`). A tap opens
/// the family's screen.
struct CaregiverWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CaregiverWidgetShared.kind, provider: CaregiverTimelineProvider()) { entry in
            CaregiverWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Thuốc của \(CaregiverWidgetShared.personName)")
        .description("\(CaregiverWidgetShared.personName) đã uống mấy liều, liều nào chưa xác nhận, và lúc máy cập nhật.")
        .supportedFamilies(CaregiverWidgetView.families)
    }
}

/// One moment of the widget, on the parent's clock.
struct CaregiverTimelineEntry: TimelineEntry {
    let news: CaregiverWidgetEntry
    let calendar: Calendar

    var date: Date { news.date }

    /// The sample morning, for the widget gallery and while loading: the
    /// 07:00 pill not taken, news from the parent's phone at 09:41.
    static var sample: CaregiverTimelineEntry {
        let calendar = LedgerSamples.calendar
        let now = LedgerSamples.referenceNow
        let entry = CaregiverWidgetTimeline.entry(
            at: now, personName: CaregiverWidgetShared.personName, medications: MedicationSamples.medications,
            log: MedicationSamples.log(), updatedAt: now, calendar: calendar
        )
        return CaregiverTimelineEntry(news: entry, calendar: calendar)
    }
}

struct CaregiverTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaregiverTimelineEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (CaregiverTimelineEntry) -> Void) {
        guard !context.isPreview, let snapshot = CaregiverWidgetShared.store.snapshot, let now = snapshot.entries(from: .now).first else {
            completion(.sample)
            return
        }
        completion(CaregiverTimelineEntry(news: now, calendar: snapshot.calendar))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaregiverTimelineEntry>) -> Void) {
        let now = Date.now
        guard let snapshot = CaregiverWidgetShared.store.snapshot else {
            // Nothing from the parent's phone yet, or nothing readable: "Chưa
            // có tin", not "no medicine". The app reloads the widget when news
            // comes.
            let calendar = Calendar.current
            let unknown = CaregiverWidgetEntry.awaitingNews(at: now, personName: CaregiverWidgetShared.personName, calendar: calendar)
            completion(Timeline(entries: [CaregiverTimelineEntry(news: unknown, calendar: calendar)], policy: .never))
            return
        }
        let calendar = snapshot.calendar
        // Nothing changes after the last entry until tomorrow ends.
        completion(Timeline(
            entries: snapshot.entries(from: now).map { CaregiverTimelineEntry(news: $0, calendar: calendar) },
            policy: .after(snapshot.timelineEnd(from: now))
        ))
    }
}

struct CaregiverWidgetEntryView: View {
    let entry: CaregiverTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        CaregiverWidgetView(entry: entry.news, layout: DoseWidgetLayout(family) ?? .small, calendar: entry.calendar)
            .containerBackground(for: .widget) {
                DoseWidgetBackground()
            }
            .widgetURL(CaregiverWidgetShared.url)
    }
}
