import Foundation

/// Why the App Store sends a message (`Message.Reason`): what its sheet is
/// about.
public enum StoreMessageReason: Hashable, Sendable {
    /// A renewal the App Store could not charge for (iOS 16.4 and later).
    case billingIssue
    /// A price increase the customer has to agree to.
    case priceIncreaseConsent
    /// An offer to come back, for a subscription that is over (iOS 18
    /// and later).
    case winBackOffer
    /// Anything else the App Store has to say (`generic`), or a reason
    /// newer than the kit.
    case other
}

/// When the App Store's messages show. StoreKit shows each as a sheet over
/// the app as soon as the app launches; an app that listens for them shows
/// them itself, when it is ready (`LabMessages`). This decides when: at
/// once, unless a screen that needs the customer's attention holds them
/// (a parent answering a dose, a ten-second entry), then when the last
/// such screen goes, in the order they came; never, for the reasons the
/// app says in its own way. One that could not show is put back, and
/// shows the next time messages do, first.
///
/// Generic over what a message is, for tests: StoreKit's `Message` in the
/// app.
public struct StoreMessageQueue<Message> {
    /// Reasons never shown: the app's own screens say the same, as its
    /// paywall offers to come back.
    public var suppressed: Set<StoreMessageReason>
    /// What holds the messages, one identifier per screen.
    public private(set) var holds: Set<String> = []
    /// The messages held, and those that could not show, oldest first.
    public private(set) var waiting: [Message] = []

    public init(suppressing suppressed: Set<StoreMessageReason> = []) {
        self.suppressed = suppressed
    }

    /// Whether a screen holds the messages.
    public var isHeld: Bool { !holds.isEmpty }

    /// A message came: returns it to show now, after any that could not
    /// show before, unless its reason is never shown, or a screen holds
    /// it, which keeps it for later.
    public mutating func receive(_ message: Message, reason: StoreMessageReason) -> [Message] {
        guard !suppressed.contains(reason) else { return [] }
        waiting.append(message)
        return retry()
    }

    /// A screen that needs the customer's attention came: the messages wait
    /// until it goes. The same screen holding twice holds once.
    public mutating func hold(_ id: String) {
        holds.insert(id)
    }

    /// That screen went: returns the messages to show now, oldest first,
    /// once no screen holds them any more.
    public mutating func release(_ id: String) -> [Message] {
        holds.remove(id)
        return retry()
    }

    /// Messages given out that could not show (StoreKit threw): they wait,
    /// before any that came after them.
    public mutating func putBack(_ messages: [Message]) {
        waiting.insert(contentsOf: messages, at: 0)
    }

    /// The app can show messages again, as it came back to the front:
    /// returns those waiting, oldest first, unless a screen holds them.
    public mutating func retry() -> [Message] {
        guard !isHeld else { return [] }
        defer { waiting = [] }
        return waiting
    }
}
