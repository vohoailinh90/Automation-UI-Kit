import Foundation
import IdeaLabCore
@testable import IdeaLabDemo
import IdeaLabStore
import StoreKit
import StoreKitTest
import Testing

/// `LabStore` against StoreKit's own test environment (`SKTestSession`), on
/// an iOS simulator: the products of `Products.storekit`, bought, approved,
/// refunded, restored and changed for one another, with no App Store
/// account and no dialog. StoreKit keeps a test environment for each app:
/// hosted by the demo, the tests set up the demo's, and buy as the demo
/// does. Not on the iOS 26.3 to 26.5 simulators, where every test session
/// fails (the CI job picks another, with
/// `ios/scripts/storekit-test-simulator.py`).
///
/// One test at a time: every session drives the same test environment. A
/// test that waits on StoreKit for two minutes fails, rather than hang the
/// run: on CI, the same test takes one second on one run and fifteen on the
/// next.
@Suite("LabStore against StoreKit's test environment", .serialized, .timeLimit(.minutes(2)))
@MainActor
struct LabStoreTests {
    private static let sold = ["pro.yearly", "pro.monthly", "pro.lifetime"]

    /// A test environment with no transactions yet, that asks nothing, and
    /// renews in real time. StoreKit forgets the last test's transactions in
    /// the background, so this waits until it reports none, nor a Pro
    /// subscription that still gives access or that it tries to charge for:
    /// a store made before then would read the last test's purchases, a
    /// plan kept for good or a subscription, and offer its plans
    /// accordingly.
    private func freshSession() async throws -> SKTestSession {
        let url = try #require(Bundle(for: TestBundle.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        let forgotten = await eventually {
            guard await entitlements().isEmpty, await unfinished().isEmpty else { return false }
            return await openSubscriptions().isEmpty
        }
        let left = forgotten ? "" : await leftover()
        try #require(forgotten, "StoreKit still reports the last test's transactions: \(left)")
        return session
    }

    /// What StoreKit still reports, for a test that waited in vain.
    private func leftover() async -> String {
        let entitled = await entitlements().sorted()
        let unfinished = await unfinished().sorted()
        let open = await openSubscriptions().count
        return "entitlements \(entitled), unfinished \(unfinished), open subscriptions \(open)"
    }

    /// Finishes what other code of the app sells (`invoice.templates`), as
    /// that code would: a test leaves it unfinished on purpose, and the next
    /// one should not wait on StoreKit to forget it.
    private func finishOthers() async {
        for await result in StoreKit.Transaction.unfinished {
            if case let .verified(transaction) = result, !Self.sold.contains(transaction.productID) {
                await transaction.finish()
            }
        }
    }

    /// Whether `condition` holds within `timeout`, asked every tenth of a
    /// second: for what reaches the store through `Transaction.updates`. A
    /// refund takes several seconds to, and a slow simulator many more.
    private func eventually(timeout: Duration = .seconds(60), _ condition: () async -> Bool) async -> Bool {
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

    /// The products the customer may use, as StoreKit reports them now.
    private func entitlements() async -> Set<String> {
        var ids: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            if case let .verified(transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        return ids
    }

    /// The Pro group's subscriptions that still give access, or that the
    /// App Store tries to charge for, as StoreKit reports their status now.
    private func openSubscriptions() async -> [Product.SubscriptionInfo.Status] {
        let statuses = (try? await Product.SubscriptionInfo.status(for: DemoContent.proGroup)) ?? []
        return statuses.filter { [.subscribed, .inGracePeriod, .inBillingRetryPeriod].contains($0.state) }
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

    /// Buys `id` with the store, as the paywall does.
    private func buy(_ id: String, with store: LabStore) async throws -> PurchaseOutcome {
        let plan = try plan(id, of: store)
        return await store.purchase(plan) { product, options in try await product.purchase(options: options) }
    }

    /// When the customer's subscription period ends, as the store read it.
    private func periodEnd(of store: LabStore) throws -> Date {
        try #require(store.subscriptions.first?.periodEnds)
    }

    /// Whether the store comes to read `ids` as the customer's subscriptions:
    /// the App Store's status of them may trail a purchase, and the store
    /// reads it again when told it changed (`Status.updates`).
    private func subscribes(to ids: [String], _ store: LabStore) async -> Bool {
        await eventually { store.subscriptions.map(\.productID) == ids }
    }

    @Test("The configuration loads, in Viet Nam's storefront")
    func configuration() async throws {
        let session = try await freshSession()
        #expect(session.storefront == "VNM")
    }

    @Test("The demo knows it hosts the tests, and its store sells nothing")
    func hostSellsNothing() {
        // Its store would finish the transactions of the plans below, before
        // a test could see whether its own store does. Asked directly: that
        // a transaction stays unfinished for a while would not show it.
        #expect(DemoLaunch.isTestHost)
        #expect(DemoLaunch.soldProductIDs.isEmpty)
    }

    @Test("Plans load in the app's order, priced by the App Store, the yearly one with its free week")
    func plans() async throws {
        let session = try await freshSession()
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
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        let outcome = await store.purchase(try plan("pro.yearly", of: store)) { product, options in
            try await product.purchase(options: options)
        }
        #expect(outcome == .purchased(productID: "pro.yearly"))
        #expect(store.owns(anyOf: ["pro.yearly"]))
        #expect(!store.owns(anyOf: ["pro.lifetime"]))
        #expect(try plan("pro.yearly", of: store).freeTrial == nil)
        #expect(await !unfinished().contains("pro.yearly"))
        withExtendedLifetime(session) {}
    }

    @Test("Ask to Buy: pending until a parent approves, then unlocked from outside the purchase")
    func askToBuy() async throws {
        let session = try await freshSession()
        session.askToBuyEnabled = true
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        let outcome = await store.purchase(try plan("pro.lifetime", of: store)) { product, options in
            try await product.purchase(options: options)
        }
        #expect(outcome == .pending)
        #expect(!store.owns(anyOf: ["pro.lifetime"]))
        let waiting = try #require(session.allTransactions().first { $0.productIdentifier == "pro.lifetime" })
        try session.approveAskToBuyTransaction(identifier: waiting.identifier)
        #expect(await eventually { store.owns(anyOf: ["pro.lifetime"]) })
        withExtendedLifetime(session) {}
    }

    @Test("A refund takes access away, through the transactions the store listens to")
    func refund() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        let outcome = await store.purchase(try plan("pro.lifetime", of: store)) { product, options in
            try await product.purchase(options: options)
        }
        #expect(outcome == .purchased(productID: "pro.lifetime"))
        #expect(store.owns(anyOf: ["pro.lifetime"]))
        let bought = try #require(session.allTransactions().first { $0.productIdentifier == "pro.lifetime" })
        try session.refundTransaction(identifier: bought.identifier)
        #expect(await eventually { !store.owns(anyOf: ["pro.lifetime"]) })
        withExtendedLifetime(session) {}
    }

    @Test("Purchase help: what the customer paid for here, newest first, named and priced; a refund shows on it")
    func purchaseHistory() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        #expect(try await buy("pro.monthly", with: store) == .purchased(productID: "pro.monthly"))
        #expect(try await buy("pro.lifetime", with: store) == .purchased(productID: "pro.lifetime"))
        // Sold by other code of the app: not this store's to list.
        _ = try await session.buyProduct(identifier: "invoice.templates")
        await store.loadPurchases()
        let purchases = try #require(store.purchases)
        #expect(purchases.map(\.productID) == ["pro.lifetime", "pro.monthly"])
        #expect(purchases.map(\.title) == ["Mua một lần", "Gói tháng"])
        #expect(purchases.map(\.price) == [599_000, 39_000])
        #expect(purchases.allSatisfy { $0.displayPrice != nil && !$0.isRenewal && $0.revocationDate == nil }, "\(purchases)")
        let lifetime = try #require(session.allTransactions().first { $0.productIdentifier == "pro.lifetime" })
        try session.refundTransaction(identifier: lifetime.identifier)
        // Read again when the refund comes in.
        #expect(await eventually { store.purchases?.first?.revocationDate != nil }, "\(String(describing: store.purchases))")
        await finishOthers()
        withExtendedLifetime(session) {}
    }

    @Test("Purchase help after the plans failed to load: loaded again, so the payments have their names")
    func purchaseHistoryAfterFailedLoad() async throws {
        let session = try await freshSession()
        let bought = LabStore(productIDs: Self.sold)
        await bought.loadProducts()
        #expect(try await buy("pro.lifetime", with: bought) == .purchased(productID: "pro.lifetime"))
        // The app opened again, offline: the plans do not load. StoreKit may
        // throw, or find none.
        let store = LabStore(productIDs: Self.sold)
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await store.loadProducts()
        #expect(store.plans.isEmpty)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.loadPurchases()
        #expect(store.loadState == .loaded)
        #expect(store.purchases?.map(\.title) == ["Mua một lần"], "\(String(describing: store.purchases))")
        withExtendedLifetime(session) {}
    }

    @Test("Restore: nothing on a new account, then what was bought outside the app")
    func restore() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        #expect(await store.restore() == .nothingToRestore)
        _ = try await session.buyProduct(identifier: "pro.lifetime")
        #expect(await store.restore() == .restored(["pro.lifetime"]))
        #expect(store.owns(anyOf: ["pro.lifetime"]))
        withExtendedLifetime(session) {}
    }

    @Test("On the monthly plan: theirs renews, the yearly one is an upgrade, buying for good leaves monthly renewing")
    func monthlySubscriber() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        #expect(try await buy("pro.monthly", with: store) == .purchased(productID: "pro.monthly"))
        #expect(await subscribes(to: ["pro.monthly"], store), "\(store.subscriptions)")
        let renewal = try periodEnd(of: store)
        #expect(renewal > .now)
        #expect(try plan("pro.monthly", of: store).standing == .current(.renews(on: renewal), ownedForGood: false))
        #expect(try plan("pro.yearly", of: store).standing == .upgrade(replacing: "Gói tháng"))
        #expect(try plan("pro.lifetime", of: store).standing == .alongside(subscription: "Gói tháng"))
        withExtendedLifetime(session) {}
    }

    @Test("Upgrading from monthly to yearly: yearly at once, monthly then only for a later period")
    func upgrade() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        _ = try await buy("pro.monthly", with: store)
        #expect(await subscribes(to: ["pro.monthly"], store), "\(store.subscriptions)")
        #expect(try await buy("pro.yearly", with: store) == .purchased(productID: "pro.yearly"))
        #expect(await subscribes(to: ["pro.yearly"], store), "\(store.subscriptions)")
        #expect(store.owns(anyOf: ["pro.yearly"]))
        let renewal = try periodEnd(of: store)
        #expect(try plan("pro.yearly", of: store).standing == .current(.renews(on: renewal), ownedForGood: false))
        #expect(try plan("pro.monthly", of: store).standing == .nextPeriod(replacing: "Gói năm", from: renewal))
        withExtendedLifetime(session) {}
    }

    @Test("Downgrading from yearly to monthly: scheduled for the renewal, yearly kept until then")
    func downgrade() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        _ = try await buy("pro.yearly", with: store)
        #expect(await subscribes(to: ["pro.yearly"], store), "\(store.subscriptions)")
        let renewal = try periodEnd(of: store)
        #expect(try plan("pro.monthly", of: store).standing == .nextPeriod(replacing: "Gói năm", from: renewal))
        let outcome = try await buy("pro.monthly", with: store)
        #expect(outcome == .scheduled(productID: "pro.monthly", from: renewal))
        // The App Store's status says so as well, once the store has it.
        let chosen = await eventually { (try? plan("pro.monthly", of: store).standing) == .scheduled(from: renewal) }
        #expect(chosen, "\(store.subscriptions)")
        #expect(try plan("pro.yearly", of: store).standing == .current(.switches(to: "Gói tháng", on: renewal), ownedForGood: false))
        #expect(store.subscriptions.map(\.productID) == ["pro.yearly"])
        #expect(store.owns(anyOf: ["pro.yearly"]))
        withExtendedLifetime(session) {}
    }

    @Test("Renewal turned off outside the app: the plan ends, and buying for good no longer warns")
    func renewalTurnedOff() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        _ = try await buy("pro.monthly", with: store)
        let bought = try #require(session.allTransactions().first { $0.productIdentifier == "pro.monthly" })
        // No transaction comes of it: the store hears of it as a status change.
        try session.disableAutoRenewForTransaction(identifier: bought.identifier)
        #expect(await eventually {
            guard case .current(.ends, _)? = try? plan("pro.monthly", of: store).standing else { return false }
            return true
        })
        #expect(try plan("pro.lifetime", of: store).standing == nil)
        withExtendedLifetime(session) {}
    }

    @Test("Bought for good: no subscription is offered any more")
    func lifetimeOwner() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        await store.loadProducts()
        #expect(try await buy("pro.lifetime", with: store) == .purchased(productID: "pro.lifetime"))
        #expect(store.plans.map(\.id) == ["pro.lifetime"])
        #expect(try plan("pro.lifetime", of: store).standing == .owned(renewing: nil))
        withExtendedLifetime(session) {}
    }

    @Test("A purchase of what the store does not sell is left unfinished, for the code that sells it")
    func othersLeftUnfinished() async throws {
        let session = try await freshSession()
        let store = LabStore(productIDs: Self.sold)
        // Time for the store to start listening to Transaction.updates.
        try await Task.sleep(for: .seconds(1))
        // Bought outside the app: the invoice templates, which other code of
        // the app sells, then Pro. Both reach the store in turn, from outside
        // the purchases. (Not coins: an unfinished consumable, bought outside
        // the app or approved by a parent, is not among the unfinished
        // transactions here.)
        _ = try await session.buyProduct(identifier: "invoice.templates")
        _ = try await session.buyProduct(identifier: "pro.lifetime")
        // Pro unlocked, so its transaction is there, and no longer unfinished:
        // the store has finished its own, and heard of the templates before
        // it. (Not unfinished alone would hold before the purchase arrives;
        // unlocked alone, before the store finishes it, as access counts
        // unfinished transactions too.)
        let finished = await eventually {
            guard store.owns(anyOf: ["pro.lifetime"]) else { return false }
            return await !unfinished().contains("pro.lifetime")
        }
        let reported = await entitlements().sorted()
        let leftUnfinished = await unfinished().sorted()
        #expect(finished, "store: \(store.entitled.sorted()); StoreKit: \(reported), unfinished \(leftUnfinished)")
        #expect(await unfinished().contains("invoice.templates"))
        await finishOthers()
        withExtendedLifetime(session) {}
    }
}

/// A class of the test bundle, to find its resources.
private final class TestBundle {}
