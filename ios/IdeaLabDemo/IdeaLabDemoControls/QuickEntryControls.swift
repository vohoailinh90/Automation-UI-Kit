import AppIntents
import SwiftUI
import WidgetKit

/// The demo's controls (iOS 18): "Ghi khoản chi" and "Ghi khoản thu", for
/// Control Center, the Lock Screen and the Action button. Each opens the
/// app at the ledger's ten-second entry for its kind
/// (`OpenQuickEntryIntent`, shared with the app).
@main
struct QuickEntryControls: WidgetBundle {
    var body: some Widget {
        ExpenseControl()
        IncomeControl()
    }
}

struct ExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.idealab.demo.controls.expense") {
            ControlWidgetButton(action: OpenQuickEntryIntent(target: .expense)) {
                Label("Ghi khoản chi", systemImage: "minus.circle.fill")
            }
        }
        .displayName("Ghi khoản chi")
        .description("Mở sổ thu chi ở màn ghi nhanh một khoản chi.")
    }
}

struct IncomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.idealab.demo.controls.income") {
            ControlWidgetButton(action: OpenQuickEntryIntent(target: .income)) {
                Label("Ghi khoản thu", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Ghi khoản thu")
        .description("Mở sổ thu chi ở màn ghi nhanh một khoản thu.")
    }
}
