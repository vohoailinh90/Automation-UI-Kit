import AppIntents

/// The demo's App Shortcuts, in Spotlight, the Shortcuts app and Siri,
/// ready without setup, and for the Action button on iPhones that have one.
/// An app has one provider, so the demo's apps share this one; an app built
/// from the kit lists its own. Each phrase names the app, as App Shortcuts
/// require; Siri hears Vietnamese from iOS 26.1.
struct DemoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // The ledger's quick entry (`OpenQuickEntryIntent`).
        AppShortcut(
            intent: OpenQuickEntryIntent(target: .expense),
            phrases: [
                "Ghi khoản chi trong \(.applicationName)",
                "Ghi chi tiêu với \(.applicationName)",
            ],
            shortTitle: "Ghi khoản chi",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: OpenQuickEntryIntent(target: .income),
            phrases: [
                "Ghi khoản thu trong \(.applicationName)",
                "Ghi tiền thu với \(.applicationName)",
            ],
            shortTitle: "Ghi khoản thu",
            systemImageName: "plus.circle"
        )
        // The medicine app's (`MedsSiriIntents.swift`): the parent's
        // answer, then the family's question. "Tôi" for the parent, never
        // "mẹ", so the two do not sound alike.
        AppShortcut(
            intent: TookMedicineIntent(),
            phrases: [
                "\(.applicationName) ơi, tôi uống thuốc rồi",
                "Báo \(.applicationName) tôi uống thuốc rồi",
                "Ghi đã uống thuốc trong \(.applicationName)",
            ],
            shortTitle: "Đã uống thuốc",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: AskMedsNewsIntent(),
            phrases: [
                "\(.applicationName) ơi, mẹ uống thuốc chưa",
                "Hỏi \(.applicationName) mẹ uống thuốc chưa",
            ],
            shortTitle: "Mẹ uống thuốc chưa?",
            systemImageName: "pills"
        )
    }
}
