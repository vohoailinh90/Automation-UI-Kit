import Foundation
import IdeaLabCore

/// What the app and its widget extension agree on for the family's widget
/// (`CaregiverWidget`): in both targets.
enum CaregiverWidgetShared {
    /// The widget's kind: the app asks WidgetKit to reload it by this.
    static let kind = "dev.idealab.demo.widgets.caregiver"
    /// Where a tap on the widget opens the app: the family's screen, with
    /// "Gọi" and "Nhắc lại".
    static let url = URL(string: "idealabdemo://meds-caregiver")!
    /// How the family calls the parent, on the widget as on their screen.
    static let personName = "Mẹ"

    /// In the App Group of the parent's widget (`MedsWidgetShared`): the
    /// demo is both phones at once. A family's app has its own.
    static var store: CaregiverWidgetStore {
        CaregiverWidgetStore(defaults: UserDefaults(suiteName: MedsWidgetShared.appGroup))
    }
}
