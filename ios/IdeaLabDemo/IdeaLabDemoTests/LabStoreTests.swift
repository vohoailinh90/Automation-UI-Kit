import Foundation
import IdeaLabCore
import IdeaLabStore
import StoreKit
import StoreKitTest
import Testing

/// `LabStore` against StoreKit's own test environment (`SKTestSession`), on
/// an iOS simulator: the products of `Products.storekit`, bought, approved,
/// refunded and restored with no App Store account and no dialog. StoreKit
/// keeps a test environment for each app: hosted by the demo, the tests set
/// up the demo's, and buy as the demo does. Not on the iOS 26.3 to 26.5
/// simulators, where every test session fails (the CI job picks another,
/// with `ios/scripts/storekit-test-simulator.py`).
///
/// One test at a time: every session drives the same test environment. A
/// test that waits on StoreKit for a minute fails, rather than hang the run.
@Suite("LabStore against StoreKit's test environment", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct LabStoreTests {
    private static let sold = ["pro.yearly", "pro.monthly", "pro.lifetime"]

    /// A test environment with no transactions yet, that asks nothing.
    private func freshSession() throws -> SKTestSession {
        let url = try #require(Bundle(for: TestBundle.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        return session
    }

    /// Whether `condition` holds within `timeout`, asked every tenth of a
    /// second: for what reaches the store through `Transaction.updates`. A
    /// refund takes several seconds to.
    private func eventually(timeout: Duration = .seconds(30), _ condition: () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    /// The products of the transactions no one has finished.
    private func unfinished() async -> Set<String> {
        var ids: Set<String> = []
        for await result in StoreKit.Transaction.unfinished {
            if case let .verified(transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        return ids
    }

    private func plan(_ id: String, of store: LabStore) throws -> PaywallPlan {
        try #require(store.plans.first { $0.id == id })
    }

    @Test("The configuration loads, in Viet Nam's storefront")
    func configuration() throws {
        let session = try freshSession()
        #expect(session.storefront == "VNM")
    }

    @Test("The demo hosting the tests sells nothing: a transaction left alone stays unfinished")
    func hostSellsNothing() async throws {
        let session = try freshSession()
        // No store of the test's: whatever finishes this, the demo's own did.
        _ = try await session.buyProduct(identifier: "pro.lifetime")
        try await Task.sleep(for: .seconds(2))
        #expect(await unfinished().contains("pro.lifetime"))
        withExtendedLifetime(session) {}
    }

    @Test("Plans load in the app's order, priced by the App Store, the yearly one with its free week")
    func plans() async throws {
        let session = try freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        #expect(store.loadState == .loaded)
        #expect(store.plans.map(\.id) == Self.sold)
        #expect(store.plans.map(\.term) == [.yearly, .monthly, .lifetime])
        #expect(store.plans.map(\.title) == ["Gói năm", "Gói tháng", "Mua một lần"])
        #expect(try plan("pro.yearly", of: store).freeTrial == .days(7))
        #expect(try plan("pro.yearly", of: store).badge == "Tiết kiệm 36%")
        #expect(try plan("pro.monthly", of: store).freeTrial == nil)
        withExtendedLifetime(session) {}
    }

    @Test("Buying the yearly plan unlocks it, and the paywall no longer promises the group's trial")
    func purchase() async throws {
        let session = try freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        let outcome = await store.purchase(try plan("pro.yearly", of: store)) { try await $0.purchase() }
        #expect(outcome == .purchased(productID: "pro.yearly"))
        #expect(store.owns(anyOf: ["pro.yearly"]))
        #expect(!store.owns(anyOf: ["pro.lifetime"]))
        #expect(try plan("pro.yearly", of: store).freeTrial == nil)
        #expect(await !unfinished().contains("pro.yearly"))
        withExtendedLifetime(session) {}
    }

    @Test("Ask to Buy: pending until a parent approves, then unlocked from outside the purchase")
    func askToBuy() async throws {
        let session = try freshSession()
        session.askToBuyEnabled = true
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        let outcome = await store.purchase(try plan("pro.lifetime", of: store)) { try await $0.purchase() }
        #expect(outcome == .pending)
        #expect(!store.owns(anyOf: ["pro.lifetime"]))
        let waiting = try #require(session.allTransactions().first { $0.productIdentifier == "pro.lifetime" })
        try session.approveAskToBuyTransaction(identifier: waiting.identifier)
        #expect(await eventually { store.owns(anyOf: ["pro.lifetime"]) })
        withExtendedLifetime(session) {}
    }

    @Test("A refund takes access away, through the transactions the store listens to")
    func refund() async throws {
        let session = try freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        let outcome = await store.purchase(try plan("pro.lifetime", of: store)) { try await $0.purchase() }
        #expect(outcome == .purchased(productID: "pro.lifetime"))
        #expect(store.owns(anyOf: ["pro.lifetime"]))
        let bought = try #require(session.allTransactions().first { $0.productIdentifier == "pro.lifetime" })
        try session.refundTransaction(identifier: bought.identifier)
        #expect(await eventually { !store.owns(anyOf: ["pro.lifetime"]) })
        withExtendedLifetime(session) {}
    }

    @Test("Restore: nothing on a new account, then what was bought outside the app")
    func restore() async throws {
        let session = try freshSession()
        let store = LabStore(productIDs: Self.sold)
        #expect(await store.restore() == .nothingToRestore)
        _ = try await session.buyProduct(identifier: "pro.lifetime")
        #expect(await store.restore() == .restored(["pro.lifetime"]))
        #expect(store.owns(anyOf: ["pro.lifetime"]))
        withExtendedLifetime(session) {}
    }

    @Test("A purchase of what the store does not sell is left unfinished, for the code that sells it")
    func othersLeftUnfinished() async throws {
        let session = try freshSession()
        session.askToBuyEnabled = true
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        // The app's other code buys coins, and the store buys Pro. Both wait
        // for a parent, whose yes reaches the store from outside the
        // purchases (Transaction.updates), the coins' first. Not coins bought
        // outside the app: bought on another device, they never reach this one.
        let products = try await Product.products(for: ["coins.10"])
        let coins = try #require(products.first)
        guard case .pending = try await coins.purchase() else {
            Issue.record("The coins were bought without a parent's yes")
            return
        }
        let pro = await store.purchase(try plan("pro.lifetime", of: store)) { try await $0.purchase() }
        #expect(pro == .pending)
        for id in ["coins.10", "pro.lifetime"] {
            let waiting = try #require(session.allTransactions().first { $0.productIdentifier == id })
            try session.approveAskToBuyTransaction(identifier: waiting.identifier)
        }
        // Pro unlocked, so its transaction is there, and no longer unfinished:
        // the store has finished its own, and heard of the coins before it.
        // (Not unfinished alone would hold before the parent's yes arrives;
        // unlocked alone, before the store finishes it, as access counts
        // unfinished transactions too.)
        #expect(await eventually {
            guard store.owns(anyOf: ["pro.lifetime"]) else { return false }
            return await !unfinished().contains("pro.lifetime")
        })
        #expect(await unfinished().contains("coins.10"))
        withExtendedLifetime(session) {}
    }
}

/// A class of the test bundle, to find its resources.
private final class TestBundle {}
