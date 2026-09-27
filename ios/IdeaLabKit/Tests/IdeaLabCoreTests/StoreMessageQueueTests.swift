@testable import IdeaLabCore
import Testing

@Suite("The App Store's messages: at once, after the screens that hold them, or never")
struct StoreMessageQueueTests {
    @Test("Nothing holds them: each shows as it comes")
    func atOnce() {
        var queue = StoreMessageQueue<String>()
        #expect(queue.receive("billing", reason: .billingIssue) == ["billing"])
        #expect(queue.receive("price", reason: .priceIncreaseConsent) == ["price"])
        #expect(queue.waiting.isEmpty)
    }

    @Test("A screen holds them: they wait, and show in the order they came when it goes")
    func afterTheScreen() {
        var queue = StoreMessageQueue<String>()
        queue.hold("dose")
        #expect(queue.receive("billing", reason: .billingIssue).isEmpty)
        #expect(queue.receive("price", reason: .priceIncreaseConsent).isEmpty)
        #expect(queue.release("dose") == ["billing", "price"])
        // Shown once: nothing is left to show again.
        #expect(queue.waiting.isEmpty)
        #expect(queue.release("dose").isEmpty)
        // Nothing holds them any more: the next shows at once.
        #expect(queue.receive("win-back", reason: .winBackOffer) == ["win-back"])
    }

    @Test("Two screens hold them: they wait for both to go")
    func afterEveryScreen() {
        var queue = StoreMessageQueue<String>()
        queue.hold("entry")
        queue.hold("dose")
        #expect(queue.receive("billing", reason: .billingIssue).isEmpty)
        #expect(queue.release("dose").isEmpty)
        #expect(queue.isHeld)
        #expect(queue.release("entry") == ["billing"])
        #expect(!queue.isHeld)
    }

    @Test("The same screen holding twice holds once; a screen that never held releases nothing")
    func sameScreen() {
        var queue = StoreMessageQueue<String>()
        queue.hold("dose")
        queue.hold("dose")
        #expect(queue.receive("billing", reason: .billingIssue).isEmpty)
        #expect(queue.release("other").isEmpty)
        #expect(queue.release("dose") == ["billing"])
    }

    @Test("One StoreKit could not show waits, and shows first when the next message comes")
    func putBack() {
        var queue = StoreMessageQueue<String>()
        #expect(queue.receive("billing", reason: .billingIssue) == ["billing"])
        queue.putBack(["billing"])
        #expect(queue.waiting == ["billing"])
        #expect(queue.receive("price", reason: .priceIncreaseConsent) == ["billing", "price"])
        #expect(queue.waiting.isEmpty)
    }

    @Test("Put back before the messages that came after it, and tried again only when nothing holds them")
    func retry() {
        var queue = StoreMessageQueue<String>()
        queue.hold("dose")
        #expect(queue.receive("price", reason: .priceIncreaseConsent).isEmpty)
        queue.putBack(["billing"])
        #expect(queue.waiting == ["billing", "price"])
        #expect(queue.retry().isEmpty)
        #expect(queue.release("dose") == ["billing", "price"])
        // The app came back to the front: the one that failed again shows.
        queue.putBack(["price"])
        #expect(queue.retry() == ["price"])
        // Shown: nothing is left to try again.
        #expect(queue.retry().isEmpty)
    }

    @Test("A reason the app says its own way never shows, held or not")
    func suppressed() {
        var queue = StoreMessageQueue<String>(suppressing: [.winBackOffer])
        #expect(queue.receive("win-back", reason: .winBackOffer).isEmpty)
        #expect(queue.receive("other", reason: .other) == ["other"])
        queue.hold("dose")
        #expect(queue.receive("win-back", reason: .winBackOffer).isEmpty)
        #expect(queue.receive("price", reason: .priceIncreaseConsent).isEmpty)
        #expect(queue.release("dose") == ["price"])
    }
}
