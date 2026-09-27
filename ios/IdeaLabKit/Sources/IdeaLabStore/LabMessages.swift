#if os(iOS)
import IdeaLabCore
import Observation
import StoreKit

/// The App Store's messages (`Message`): a renewal it could not charge
/// for, a price increase to agree to, an offer to come back. StoreKit shows
/// each as a sheet over the app as soon as it launches. This listens for
/// them instead, from launch, and shows them once no screen that needs the
/// customer's attention holds them (`StoreMessageQueue`), in the root
/// view's window (`showsStoreMessages(_:)`). A screen holds them with
/// `holdsStoreMessages()`.
///
/// Created once when the app launches, as StoreKit sends the messages then:
///
///     @State private var messages = LabMessages()
///     …
///     WindowGroup {
///         ContentView()
///             .showsStoreMessages(messages)
///     }
@MainActor
@Observable
public final class LabMessages {
    @ObservationIgnored private var queue: StoreMessageQueue<Message>
    /// How the root view shows a message, while it is there.
    @ObservationIgnored private var show: (@MainActor (Message) -> Void)?

    /// Held until a view can show the messages, and while none can.
    private static let noWindow = "LabMessages.noWindow"

    /// - Parameter suppressing: reasons never shown, as the app says the
    ///   same its own way: `.winBackOffer` for an app whose paywall offers
    ///   to come back (`PaywallScreen` does, iOS 18).
    public init(suppressing: Set<StoreMessageReason> = []) {
        queue = StoreMessageQueue(suppressing: suppressing)
        queue.hold(Self.noWindow)
        Task { [weak self] in
            for await message in Message.messages {
                guard let self else { return }
                self.present(self.queue.receive(message, reason: StoreMessageReason(message.reason)))
            }
        }
    }

    /// The root view shows the messages from now on, those that waited
    /// first.
    func attach(_ show: @escaping @MainActor (Message) -> Void) {
        self.show = show
        present(queue.release(Self.noWindow))
    }

    /// The root view went: the messages wait for it again.
    func detach() {
        show = nil
        queue.hold(Self.noWindow)
    }

    /// A screen that needs the customer's attention came.
    func hold(_ id: String) {
        queue.hold(id)
    }

    /// It went: what waited shows now, unless another screen holds it.
    func release(_ id: String) {
        present(queue.release(id))
    }

    /// The queue gives out messages only while nothing holds them, the
    /// root view included, so there is always a view to show them.
    private func present(_ messages: [Message]) {
        guard let show else { return }
        for message in messages {
            show(message)
        }
    }
}

extension StoreMessageReason {
    /// What StoreKit's reason says; `.other` for one the kit does not know.
    init(_ reason: Message.Reason) {
        if reason == .billingIssue {
            self = .billingIssue
        } else if reason == .priceIncrease {
            self = .priceIncrease
        } else if #available(iOS 18.0, *), reason == .winBackOffer {
            self = .winBackOffer
        } else {
            self = .other
        }
    }
}
#endif
