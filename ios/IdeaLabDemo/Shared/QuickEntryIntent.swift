import AppIntents
import IdeaLabCore

// In both the app and its controls (IdeaLabDemoControls): a control opens
// the app with an intent the two share, as Apple asks. It runs in the app.

/// Thu or chi, as Siri, Shortcuts and the controls name them.
enum EntryKindOption: String, AppEnum {
    case expense
    case income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Loại khoản"
    static let caseDisplayRepresentations: [EntryKindOption: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "Khoản chi", image: .init(systemName: "minus.circle")),
        .income: DisplayRepresentation(title: "Khoản thu", image: .init(systemName: "plus.circle")),
    ]

    var kind: LedgerEntry.Kind {
        switch self {
        case .expense: .expense
        case .income: .income
        }
    }
}

/// Opens the ledger's ten-second entry for a kind: from a control in
/// Control Center, on the Lock Screen or the Action button, from Siri,
/// Spotlight or a shortcut. The system brings the app to the front, then
/// runs this there; the ledger's home takes the request
/// (`QuickEntryRouter`).
struct OpenQuickEntryIntent: OpenIntent {
    static let title: LocalizedStringResource = "Ghi một khoản"
    static let description = IntentDescription("Mở sổ thu chi ở màn ghi nhanh, đúng loại khoản.")

    @Parameter(title: "Loại khoản")
    var target: EntryKindOption

    init() {}

    init(target: EntryKindOption) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickEntryRouter.shared.ask(target.kind)
        return .result()
    }
}
