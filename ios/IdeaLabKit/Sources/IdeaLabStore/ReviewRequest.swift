#if os(iOS)
import IdeaLabCore
import StoreKit
import SwiftUI

extension View {
    /// Asks for an App Store rating with StoreKit's own prompt, at the end
    /// of something people came to do: while `isDone`, once they have
    /// stayed on this screen for `pause` with the app in the foreground
    /// (Apple's sample waits two seconds, so the prompt does not catch
    /// them on their way elsewhere), and only if `store` says it is time
    /// (`ReviewPrompt.shouldAsk`). It then keeps that it asked, as the app
    /// cannot know whether the prompt showed.
    ///
    /// `isDone` is true on a screen that shows a task's end, such as a
    /// cleanup's result, or while a screen rests right after one: an entry
    /// saved, its toast with "Hoàn tác" gone, no sheet open over it. The
    /// app turns it false once that moment has passed, when the next task
    /// starts. Never at launch, nor in answer to a tap: StoreKit's prompt
    /// may not show, so a button that asks would do nothing. The app
    /// counts its tasks with `ReviewPromptStore.completedTask`, apart.
    ///
    /// The system shows the prompt three times a year at most, and never
    /// to people who turned it off: a Settings row that writes a review
    /// stays (`SettingsScreen`'s `reviewURL`). A build run from Xcode shows
    /// it every time it is asked, and a TestFlight build never does.
    public func requestsReview(
        _ store: ReviewPromptStore,
        when isDone: Bool,
        version: String = ReviewPromptStore.appVersion,
        calendar: Calendar = .current,
        rules: ReviewPrompt.Rules = .standard,
        pause: Duration = .seconds(2)
    ) -> some View {
        modifier(RequestsReview(store: store, isDone: isDone, version: version, calendar: calendar, rules: rules, pause: pause))
    }
}

private struct RequestsReview: ViewModifier {
    let store: ReviewPromptStore
    let isDone: Bool
    let version: String
    let calendar: Calendar
    let rules: ReviewPrompt.Rules
    let pause: Duration
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    /// How many times the scene left the foreground or came back while
    /// this screen was up: a pause that saw either was no pause on the
    /// screen, and the prompt would greet people coming back to the app.
    @State private var phaseChanges = 0

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) {
                phaseChanges += 1
            }
            .task(id: isDone) {
                guard isDone, scenePhase == .active else { return }
                let changes = phaseChanges
                do {
                    try await Task.sleep(for: pause)
                } catch {
                    return  // Gone from the screen, or the moment passed.
                }
                let now = Date.now
                guard phaseChanges == changes,
                      store.shouldAsk(at: now, version: version, calendar: calendar, rules: rules)
                else { return }
                store.asked(at: now, version: version)
                requestReview()
            }
    }
}
#endif
