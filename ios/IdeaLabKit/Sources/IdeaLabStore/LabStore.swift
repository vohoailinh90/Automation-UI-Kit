#if os(iOS)
import IdeaLabCore
import StoreKit
// For `PurchaseAction`. SwiftUI has a `Transaction` of its own, so
// StoreKit's is always written in full.
import SwiftUI

/// Selling with StoreKit 2, for `PaywallScreen` and `SettingsScreen`: the
/// plans with the App Store's prices, the purchase, "Khôi phục mua hàng",
/// and what the customer owns, kept current.
///
/// Create one when the app starts and keep it: from the start it listens
/// for what happens outside the app, a parent approving an Ask to Buy, a
/// purchase on another device or in the App Store, a refund
/// (`Transaction.updates`), as Apple asks, and finishes the transactions of
/// the products it sells. Those of other products are left to the code
/// that sells them, which must deliver before it finishes.
///
///     @main struct SoThuChiApp: App {
///         @State private var store = LabStore(productIDs: ["pro.yearly", "pro.monthly", "pro.lifetime"])
///
///         var body: some Scene {
///             WindowGroup { RootView().environment(store) }
///         }
///     }
///
/// A purchase goes through SwiftUI's purchase action, which puts the App
/// Store's sheet over the right window:
///
///     @Environment(\.purchase) private var purchase
///     …
///     let outcome = await store.purchase(plan, with: purchase)
///     toast = StoreCopy.purchaseMessage(for: outcome, plans: store.plans).map { LabToastMessage($0) }
@MainActor
@Observable
public final class LabStore {
    /// The products sold, in the paywall's order.
    public let productIDs: [String]
    /// The paywall's plans (`PaywallCatalog`), once `loadProducts()` has
    /// loaded them.
    public private(set) var plans: [PaywallPlan] = []
    /// The products the customer may use now, from
    /// `Transaction.currentEntitlements` (`StoreEntitlements`).
    public private(set) var entitled: Set<String> = []
    /// Where `loadProducts()` is, for the paywall to say so while `plans`
    /// is empty (`PaywallScreen(isLoadingPlans:onReloadPlans:)`).
    public private(set) var loadState: LoadState = .idle

    public enum LoadState: Hashable, Sendable {
        /// Not asked yet.
        case idle
        case loading
        /// Loaded. `plans` is still empty if the App Store knows none of
        /// `productIDs`.
        case loaded
        /// No network, or the App Store down: offer to try again.
        case failed
    }

    @ObservationIgnored private var products: [String: Product] = [:]

    public init(productIDs: [String]) {
        self.productIDs = productIDs
        Task { [weak self] in
            await self?.refreshEntitlements()
            // Unfinished transactions come first, once, right after launch.
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.receive(result)
            }
        }
    }

    /// Whether the customer owns any of `ids`, such as any Pro plan.
    public func owns(anyOf ids: some Sequence<String>) -> Bool {
        ids.contains { entitled.contains($0) }
    }

    /// Loads the plans from the App Store, priced in the customer's own
    /// currency, with a free trial only if it is still theirs to have. Call
    /// when the paywall appears, and again to retry after `.failed`.
    public func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: productIDs)
            products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            await refreshPlans()
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    /// Makes `plans` from the loaded products, asking the App Store afresh
    /// whether each introductory offer is still the customer's: buying any
    /// plan of a subscription group ends the trials of the whole group.
    private func refreshPlans() async {
        let loaded = Array(products.values)
        var eligible: Set<String> = []
        for product in loaded {
            // True even for a product with no offer, so the offer is checked too.
            if let subscription = product.subscription, subscription.introductoryOffer != nil,
               await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        plans = PaywallCatalog.plans(from: loaded.map { StoreProduct($0) }, in: productIDs, introOfferEligible: eligible) { product, amount in
            byID[product.id].map { amount.formatted($0.priceFormatStyle) } ?? product.displayPrice
        }
    }

    /// After anything that may change what the customer owns: access read
    /// again, and the plans made again, so a trial the customer no longer
    /// has is not still promised.
    private func refreshAfterTransaction() async {
        await refreshEntitlements()
        if !products.isEmpty {
            await refreshPlans()
        }
    }

    /// Buys `plan`'s product with the view's purchase action
    /// (`@Environment(\.purchase)`), finishes the transaction and unlocks it,
    /// and makes the plans again: a subscription bought ends its group's
    /// trials. The paywall's button stays busy until this returns, so it
    /// never offers the old plans in between.
    public func purchase(_ plan: PaywallPlan, with action: PurchaseAction) async -> PurchaseOutcome {
        guard let product = products[plan.id] else { return .unavailable }
        do {
            switch try await action(product) {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refreshAfterTransaction()
                return .purchased(productID: transaction.productID)
            case .success(.unverified):
                // Not signed by the App Store: nothing to unlock.
                return .unverified
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// "Khôi phục mua hàng": asks the App Store for the customer's
    /// purchases (`AppStore.sync()`), which asks them to sign in. Only for
    /// that button: StoreKit keeps purchases current by itself, on every
    /// device, even after a reinstall.
    public func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        await refreshAfterTransaction()
        let restored = entitled.intersection(productIDs)
        return restored.isEmpty ? .nothingToRestore : .restored(restored)
    }

    /// Reads what the customer owns now. The store does so at launch, and
    /// after each purchase, restore and transaction that comes in, when it
    /// also makes the plans again.
    public func refreshEntitlements() async {
        var owned: [StoreTransaction] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            owned.append(StoreTransaction(
                productID: transaction.productID, revocationDate: transaction.revocationDate, isUpgraded: transaction.isUpgraded
            ))
        }
        entitled = StoreEntitlements.productIDs(from: owned)
    }

    /// A transaction from outside the app, or one left unfinished: access is
    /// read again, and the transaction finished if the App Store signed it
    /// and it is for a product this store sells. Finishing another's, a
    /// consumable say, would tell the App Store it was delivered before the
    /// code that sells it had the chance, and it would not come back.
    private func receive(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case let .verified(transaction) = result else { return }
        if productIDs.contains(transaction.productID) {
            await transaction.finish()
        }
        await refreshAfterTransaction()
    }
}

extension StoreProduct {
    /// What `PaywallCatalog` needs of `product`.
    init(_ product: Product) {
        let kind: Kind
        if product.type == .nonConsumable {
            kind = .nonConsumable
        } else if product.type == .autoRenewable, let subscription = product.subscription,
                  let period = Period(subscription.subscriptionPeriod) {
            kind = .autoRenewable(period: period, introOffer: subscription.introductoryOffer.flatMap { IntroOffer($0) })
        } else {
            kind = .other
        }
        self.init(id: product.id, displayName: product.displayName, displayPrice: product.displayPrice, price: product.price, kind: kind)
    }
}

extension StoreProduct.Period {
    init?(_ period: Product.SubscriptionPeriod) {
        let units: [(Product.SubscriptionPeriod.Unit, Unit)] = [(.day, .day), (.week, .week), (.month, .month), (.year, .year)]
        guard let unit = units.first(where: { $0.0 == period.unit })?.1 else { return nil }
        self.init(period.value, unit)
    }
}

extension StoreProduct.IntroOffer {
    init?(_ offer: Product.SubscriptionOffer) {
        let payments: [(Product.SubscriptionOffer.PaymentMode, Payment)] = [
            (.freeTrial, .freeTrial), (.payAsYouGo, .payAsYouGo), (.payUpFront, .payUpFront),
        ]
        guard let payment = payments.first(where: { $0.0 == offer.paymentMode })?.1,
              let period = StoreProduct.Period(offer.period)
        else { return nil }
        self.init(payment: payment, period: period, periodCount: offer.periodCount)
    }
}
#endif
