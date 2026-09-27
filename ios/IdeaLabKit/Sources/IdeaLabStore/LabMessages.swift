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
/// `holdsStoreMessages()`. They show in the window in the foreground that
/// came there last (`StoreMessageWindows`), and wait while none is there.
/// One StoreKit could not show waits too, and tries again when a window
/// comes to the foreground, a screen lets go, or another message comes.
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
    /// How each window's root view shows a message, while it is there.
    @ObservationIgnored private var windows = StoreMessageWindows<@MainActor (Message) throws -> Void>()

    /// Held while no window is in the foreground to show the messages.
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

    /// A window's root view came, its scene in the foreground or not.
    func attach(_ id: String, isActive: Bool, show: @escaping @MainActor (Message) throws -> Void) {
        windows.attach(id, isActive: isActive, show: show)
        update()
    }

    /// It went.
    func detach(_ id: String) {
        windows.detach(id)
        update()
    }

    /// Its scene came to the foreground, or left it.
    func setActive(_ id: String, _ isActive: Bool) {
        windows.setActive(id, isActive)
        update()
    }

    /// A screen that needs the customer's attention came.
    func hold(_ id: String) {
        queue.hold(id)
    }

    /// It went: what waited shows now, unless another screen holds it.
    func release(_ id: String) {
        present(queue.release(id))
    }

    /// With a window in the foreground, the messages that waited show
    /// there, those StoreKit could not show before included; with none,
    /// they wait for one.
    private func update() {
        if windows.front == nil {
            queue.hold(Self.noWindow)
        } else {
            present(queue.release(Self.noWindow))
        }
    }

    /// Shows each message in the window in front, as Apple's example does
    /// with the messages it deferred; one StoreKit could not show waits for
    /// the next try, without holding up the others. The queue gives out
    /// messages only while nothing holds them, the lack of a window in the
    /// foreground included, so there is always one to show them.
    private func present(_ messages: [Message]) {
        guard let show = windows.front else {
            queue.putBack(messages)
            return
        }
        var failed: [Message] = []
        for message in messages {
            do {
                try show(message)
            } catch {
                failed.append(message)
            }
        }
        queue.putBack(failed)
    }
}

extension StoreMessageReason {
    /// What StoreKit's reason says; `.other` for one the kit does not know.
    init(_ reason: Message.Reason) {
        if reason == .billingIssue {
            self = .billingIssue
        } else if reason == .priceIncreaseConsent {
            self = .priceIncreaseConsent
        } else if #available(iOS 18.0, *), reason == .winBackOffer {
            self = .winBackOffer
        } else {
            self = .other
        }
    }
}
#endif
