@testable import IdeaLabCore
import Testing

@MainActor
@Suite("Quick entry from outside the app: the sheet a request opens, and when")
struct QuickEntryRouterTests {
    @Test("No sheet open: the request opens one for its kind, once")
    func opens() {
        let router = QuickEntryRouter()
        #expect(router.take(showing: nil) == nil)
        router.ask(.expense)
        #expect(router.take(showing: nil) == .expense)
        #expect(router.pending == nil)
        #expect(router.take(showing: nil) == nil)
    }

    @Test("The sheet already open for that kind: nothing more to do")
    func sameKind() {
        let router = QuickEntryRouter()
        router.ask(.income)
        #expect(router.take(showing: .income) == nil)
        #expect(router.pending == nil)
        // It closes: no second sheet.
        #expect(router.take(showing: nil) == nil)
    }

    @Test("Open for the other kind: the half-written entry stays; the request opens once it closes")
    func otherKind() {
        let router = QuickEntryRouter()
        router.ask(.expense)
        #expect(router.take(showing: .income) == nil)
        #expect(router.pending == .expense)
        #expect(router.take(showing: nil) == .expense)
        #expect(router.pending == nil)
    }

    @Test("A newer request replaces one not yet taken")
    func newest() {
        let router = QuickEntryRouter()
        router.ask(.income)
        router.ask(.expense)
        #expect(router.take(showing: nil) == .expense)
    }
}
