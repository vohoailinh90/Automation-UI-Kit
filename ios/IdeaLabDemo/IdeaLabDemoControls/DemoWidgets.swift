import SwiftUI
import WidgetKit

/// The demo's widget extension: the parent's medicine widget, from iOS 17
/// like the app, and the ledger's controls, from iOS 18.
@main
struct DemoWidgets: WidgetBundle {
    var body: some Widget {
        MedsWidget()
        if #available(iOS 18.0, *) {
            ExpenseControl()
        }
        if #available(iOS 18.0, *) {
            IncomeControl()
        }
    }
}
