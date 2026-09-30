import AppIntents

/// The ledger's quick entry in Spotlight, the Shortcuts app and Siri, ready
/// without setup, and for the Action button on iPhones that have one. Each
/// phrase names the app, as App Shortcuts require.
struct QuickEntryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
    }
}
