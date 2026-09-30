import Observation

/// Writing an entry down from outside the app: a control in Control
/// Center, on the Lock Screen or the Action button, Siri, Spotlight, a
/// shortcut. The App Intent behind it opens the app and asks for the kind
/// here; the ledger's home, which presents the entry sheet, takes it.
///
/// A half-written entry is never lost to a request: with the sheet open for
/// the other kind, the request waits until the sheet closes, then opens;
/// with the sheet open for the same kind, there is nothing more to do.
@MainActor
@Observable
public final class QuickEntryRouter {
    /// The one the app's intents and its ledger share.
    public static let shared = QuickEntryRouter()

    /// The kind asked for, until the ledger's home takes it.
    public private(set) var pending: LedgerEntry.Kind?

    public init() {}

    /// From an App Intent: a newer request replaces one not yet taken.
    public func ask(_ kind: LedgerEntry.Kind) {
        pending = kind
    }

    /// The ledger's home takes the request, given the entry sheet it shows:
    /// returns the kind of the sheet to open now. Call it when the home
    /// appears, when `pending` changes, and when its sheet closes.
    public func take(showing: LedgerEntry.Kind?) -> LedgerEntry.Kind? {
        guard let kind = pending else { return nil }
        guard let showing else {
            pending = nil
            return kind
        }
        if showing == kind {
            pending = nil
        }
        return nil
    }
}
