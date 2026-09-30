import AppIntents
import IdeaLabCore
import WidgetKit

// Siri for the medicine app (`DemoShortcuts`): both intents read the App
// Group the widgets read, so Siri and the widgets never disagree. Siri runs
// them in the app's process, without bringing the app to the front.

/// "Tôi uống thuốc rồi": the parent tells Siri, the Action button or a
/// shortcut that the medicine waiting is taken. It is recorded as the
/// widget's "ĐÃ UỐNG" records it (`DoseWidgetStore.recordTaken`), one dose
/// each time, and Siri names it. The widget shows it at once, with "Hoàn
/// tác"; the app takes it into its log at once if it is running
/// (`medsAnsweredBySiri`), else when it next becomes active
/// (`DemoMedsStore.syncWithWidget`).
///
/// An app that schedules the parent's reminders plans them again here, as
/// `AnswerDoseIntent` does, and sends the answer to the family's phones:
/// this runs in the app's process, which can.
struct TookMedicineIntent: AppIntent {
    static let title: LocalizedStringResource = "Đã uống thuốc"
    static let description = IntentDescription("Ghi đã uống liều thuốc đang chờ, như bấm ĐÃ UỐNG.")
    /// On the parent's phone unlocked, or once they unlock it: Siri names
    /// the medicine, and an answer decides whether the family hears of a
    /// missed dose.
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = MedsWidgetShared.store.recordTaken(at: .now)
        if reply.answer != nil {
            WidgetCenter.shared.reloadTimelines(ofKind: MedsWidgetShared.kind)
            NotificationCenter.default.post(name: .medsAnsweredBySiri, object: nil)
        }
        return .result(dialog: "\(reply.text)")
    }
}

extension Notification.Name {
    /// Siri recorded a dose (`TookMedicineIntent`), in the app's process:
    /// its screens, if up, take it into their log now, whether or not
    /// Siri's panel made the app inactive meanwhile.
    static let medsAnsweredBySiri = Notification.Name("dev.idealab.demo.medsAnsweredBySiri")
}

/// "Mẹ uống thuốc chưa?": the family asks Siri, and hears what their
/// widget shows (`CaregiverWidgetStore.siriAnswer`), when the news came
/// included. No medicine is named: Siri may say it aloud, to anyone near,
/// and answers on a locked phone too, as the Lock Screen's widget shows.
struct AskMedsNewsIntent: AppIntent {
    static let title: LocalizedStringResource = "Mẹ uống thuốc chưa?"
    static let description = IntentDescription("Nghe tin mới nhất từ máy của Mẹ, như widget của bạn.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = CaregiverWidgetShared.store.siriAnswer(at: .now, personName: CaregiverWidgetShared.personName)
        return .result(dialog: "\(answer)")
    }
}
