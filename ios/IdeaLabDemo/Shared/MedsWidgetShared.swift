import Foundation
import IdeaLabCore

/// What the app and its widget extension agree on for the parent's medicine
/// widget (`MedsWidget`): in both targets.
enum MedsWidgetShared {
    /// The widget's kind: the app asks WidgetKit to reload it by this.
    static let kind = "dev.idealab.demo.widgets.meds"
    /// The App Group both belong to (their entitlements), where the app
    /// leaves the snapshot the widget reads.
    static let appGroup = "group.dev.idealab.demo"
    /// Where a tap on the widget opens the app: the parent's screen, with
    /// "ĐÃ UỐNG".
    static let url = URL(string: "idealabdemo://meds-today")!

    static var store: DoseWidgetStore {
        DoseWidgetStore(defaults: UserDefaults(suiteName: appGroup))
    }
}
