import AppIntents
import IdeaLabCore
import WidgetKit

/// "ĐÃ UỐNG" and "Hoàn tác" on the parent's medium widget
/// (`DoseWidgetAnswer`): in both the app and its widget extension, as Apple
/// asks, and run in the extension. It records the answer in the App Group
/// (`DoseWidgetStore.record`), unless the dose was answered since the
/// widget was drawn; the widget shows it at once, and the app takes it into
/// its log when it next becomes active (`DemoMedsStore.syncWithWidget`).
///
/// An app that schedules the parent's reminders plans them again here, from
/// the log `record` returns (`DoseAlerts`, `DoseNotifications` of
/// IdeaLabNotifications), so no "Nhắc lại" rings for a dose answered. The
/// demo schedules none.
struct AnswerDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Trả lời liều thuốc"
    static let description = IntentDescription("Ghi đã uống, hay hoàn tác, một liều thuốc từ widget.")
    /// A widget's button only: not offered in Shortcuts or Spotlight.
    static let isDiscoverable = false

    /// The answer, as the widget drew it (`DoseWidgetAction.encoded`).
    @Parameter(title: "Câu trả lời")
    var answer: String

    init() {}

    init(_ answer: DoseWidgetAnswer) {
        self.answer = answer.action.encoded
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let action = DoseWidgetAction(encoded: answer), MedsWidgetShared.store.record(action, at: .now) != nil {
            // WidgetKit reloads the widget tapped; the parent's other ones too.
            WidgetCenter.shared.reloadTimelines(ofKind: MedsWidgetShared.kind)
        }
        return .result()
    }
}
