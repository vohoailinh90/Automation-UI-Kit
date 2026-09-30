#if os(iOS)
import IdeaLabCore
import StoreKit
// For `PurchaseAction`. SwiftUI has a `Transaction` of its own, so
// StoreKit's is always written in full.
import SwiftUI

/// Selling with StoreKit 2, for `PaywallScreen`, `SettingsScreen` and
/// `PurchaseHelpScreen`: the plans with the App Store's prices, the
/// purchase, "Khôi phục mua hàng", what the customer owns, kept current,
/// and what they paid, for help and refunds.
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
    /// Among `entitled`, the products the customer has only through Family
    /// Sharing: a family member bought them, and may stop sharing them.
    public private(set) var sharedByFamily: Set<String> = []
    /// The customer's subscriptions in the groups of the products loaded,
    /// one per group, while they give access (subscribed, or in the
    /// billing grace period) or the App Store keeps trying to charge for
    /// them (billing retry): what they have, what it renews as, when, and
    /// whether the App Store could not charge for a renewal
    /// (`Product.SubscriptionInfo.status(for:)`). The plans say where each
    /// stands against them.
    public private(set) var subscriptions: [StoreSubscription] = []
    /// Per subscription group of the products loaded, the win-back offers
    /// the customer may redeem, best first: the App Store's list
    /// (`RenewalInfo.eligibleWinBackOfferIDs`, iOS 18 and later) for their
    /// own subscription there once it is over (`StoreCustomer.winBackOfferIDs`).
    /// The plans carry the offer, and buying the plan applies it.
    public private(set) var winBackOffers: [String: [String]] = [:]
    /// Where `loadProducts()` is, for the paywall to say so while `plans`
    /// is empty (`PaywallScreen(isLoadingPlans:onReloadPlans:)`).
    public private(set) var loadState: LoadState = .idle
    /// The offer code the customer redeemed for a product sold here, once
    /// it is unlocked, until the app has welcomed them to it: in the app's
    /// sheet for offer codes, in the App Store or through a link, the app
    /// running or not yet opened (its transaction then comes unfinished at
    /// launch). The app welcomes them to what it unlocked
    /// (`StoreCopy.redeemMessage`), as Apple asks, where they can see it,
    /// then calls `welcomed(_:)`. Kept across launches
    /// (`StoreRedemptionInbox`), so a closed app never loses the welcome;
    /// given only while its product is theirs, read again each time, and
    /// forgotten once it is not (refunded, over, another account). The
    /// plans are loaded before it is given, so the welcome can name them.
    public private(set) var redemption: StoreRedemption?
    /// The customer's own payments for the products sold here, newest
    /// first, for the purchase help (`PurchaseHelpScreen`,
    /// `PurchaseHistory.listed`): `nil` until `loadPurchases()` reads them,
    /// then read again with every transaction that comes in, a renewal or a
    /// refund say.
    public private(set) var purchases: [StorePurchase]?
    /// The payments with a refund request, sent from the app or known to
    /// the App Store (`StoreRefundRequests`): kept across launches, so the
    /// help says a request is under way rather than offer another.
    public private(set) var refundRequests: Set<UInt64> = []

    /// What the customer has, for the plans and for a notice of a renewal
    /// the App Store could not charge for, outside the paywall
    /// (`StoreCopy.billingNotice(for:plans:)`). Their subscriptions are
    /// only read once the products are loaded (`loadProducts()`), as their
    /// groups come from them: an app showing the notice loads them at
    /// launch.
    public var customer: StoreCustomer {
        StoreCustomer(owned: entitled, sharedByFamily: sharedByFamily, subscriptions: subscriptions, winBackOffers: winBackOffers)
    }

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
    /// `refresh()`'s reads, one at a time.
    private let reads = SerialRefresh()
    /// `redemption`, kept across launches until welcomed.
    private let inbox = StoreRedemptionInbox()
    /// `refundRequests`, kept across launches.
    private let refunds = StoreRefundRequests()

    public init(productIDs: [String]) {
        self.productIDs = productIDs
        refundRequests = refunds.requested
        Task { [weak self] in
            // What the customer owns, and the plans too if they load
            // before this read starts.
            await self?.refresh()
            // Unfinished transactions come first, once, right after launch.
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.receive(result)
            }
        }
        // What makes no transaction: renewal turned off or on again, or a
        // plan chosen for the next period, in the App Store's page for the
        // customer's subscriptions.
        Task { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                guard let self else { return }
                await self.refresh()
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
            // What the customer owns read afresh, rather than left to the
            // read at launch, which may not have finished: a lifetime owner
            // would be offered subscriptions.
            await refresh()
            loadState = .loaded
        } catch {
            loadState = .failed
            // A redemption waiting for the plans is welcomed without them.
            await refresh()
        }
    }

    /// Makes `plans` from the loaded products, asking the App Store afresh
    /// whether each introductory offer is still the customer's (buying any
    /// plan of a subscription group ends the trials of the whole group), and
    /// what they subscribe to, for where each plan stands. Only as part of
    /// a read (`refresh()`).
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
        await refreshSubscriptions()
        let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        plans = PaywallCatalog.plans(
            from: loaded.map { StoreProduct($0) }, in: productIDs, introOfferEligible: eligible, customer: customer
        ) { product, amount in
            byID[product.id].map { amount.formatted($0.priceFormatStyle) } ?? product.displayPrice
        }
    }

    /// Reads the customer's subscription in each group of the loaded
    /// products. Several statuses in a group come from Family Sharing: their
    /// own subscription comes before one a family member shares with them.
    /// One in billing retry gives no access, but is read too: the App Store
    /// keeps trying to charge for it, and the customer can fix that. So
    /// are the win-back offers the App Store lists for their own
    /// subscription once it is over (iOS 18 and later). A group whose
    /// status could not be read keeps what was known of it, rather than
    /// showing a subscriber as a new customer.
    private func refreshSubscriptions() async {
        let groups = Set(products.values.compactMap { $0.subscription?.subscriptionGroupID })
        var found: [StoreSubscription] = []
        var offers: [String: [String]] = [:]
        for group in groups.sorted() {
            guard let statuses = try? await Product.SubscriptionInfo.status(for: group) else {
                found += subscriptions.filter { $0.groupID == group }
                offers[group] = winBackOffers[group]
                continue
            }
            if #available(iOS 18.0, *) {
                offers[group] = statuses.lazy.compactMap { status -> [String]? in
                    guard case let .verified(renewal) = status.renewalInfo,
                          case let .verified(transaction) = status.transaction,
                          let state = StoreSubscription.State(status.state)
                    else { return nil }
                    let ids = StoreCustomer.winBackOfferIDs(
                        state: state, willAutoRenew: renewal.willAutoRenew,
                        isFamilyShared: transaction.ownershipType == .familyShared, eligible: renewal.eligibleWinBackOfferIDs
                    )
                    return ids.isEmpty ? nil : ids
                }.first
            }
            let known: [StoreSubscription] = statuses.compactMap { status in
                guard case let .verified(renewal) = status.renewalInfo,
                      case let .verified(transaction) = status.transaction,
                      let state = StoreSubscription.State(status.state)
                else { return nil }
                return StoreSubscription(
                    groupID: group, state: state, currentProductID: renewal.currentProductID,
                    willAutoRenew: renewal.willAutoRenew, autoRenewPreference: renewal.autoRenewPreference,
                    renewalDate: renewal.renewalDate, expirationDate: transaction.expirationDate,
                    gracePeriodExpirationDate: renewal.gracePeriodExpirationDate,
                    isFamilyShared: transaction.ownershipType == .familyShared
                )
            }
            if let theirs = known.first(where: { !$0.isFamilyShared }) ?? known.first {
                found.append(theirs)
            }
        }
        subscriptions = found
        winBackOffers = offers
    }

    /// After anything that may change what the customer owns or has: access
    /// read again, and the plans made again, so a trial the customer no
    /// longer has is not still promised.
    ///
    /// One read at a time (`SerialRefresh`): a read waits on StoreKit
    /// several times, and two under way together could finish in any
    /// order, the older one last, leaving what it saw. Returns once a read
    /// that started after the call has finished, so what the store shows is
    /// at least as new as the call.
    private func refresh() async {
        await reads.run {
            await self.readEntitlements()
            if !self.products.isEmpty {
                await self.refreshPlans()
            }
            self.refreshRedemption()
            if self.purchases != nil {
                await self.readPurchases()
            }
        }
    }

    /// The redemption waiting for its welcome, while its product is theirs
    /// (`entitled`, just read), once the plans can name it: not loaded yet,
    /// they are, and the read after the load gives it. If the load failed,
    /// or the App Store has none of the plans, it is given unnamed.
    private func refreshRedemption() {
        let waiting = inbox.waiting(entitled: entitled)
        guard waiting != nil, products.isEmpty, loadState == .idle || loadState == .loading else {
            redemption = waiting
            return
        }
        redemption = nil
        if loadState == .idle {
            Task { [weak self] in await self?.loadProducts() }
        }
    }

    /// Buys `plan`'s product with the view's purchase action
    /// (`@Environment(\.purchase)`), finishes the transaction and unlocks it,
    /// and makes the plans again: a subscription bought ends its group's
    /// trials, and a plan of the customer's group may start only when their
    /// period ends (`.scheduled`). The paywall's button stays busy until this
    /// returns, so it never offers the old plans in between.
    public func purchase(_ plan: PaywallPlan, with action: PurchaseAction) async -> PurchaseOutcome {
        await purchase(plan) { product, options in
            try await action(product, options: options)
        }
    }

    /// The same, buying with `buy` and the options it is given, which apply
    /// the plan's win-back offer: a UIKit app's
    /// `product.purchase(confirmIn:options:)`, or a test's
    /// `product.purchase(options:)`.
    public func purchase(
        _ plan: PaywallPlan, using buy: (Product, Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult
    ) async -> PurchaseOutcome {
        guard let product = products[plan.id] else { return .unavailable }
        var options: Set<Product.PurchaseOption> = []
        if let offerID = plan.winBackOffer?.id {
            // Never at another price than the paywall said: an offer no
            // longer there fails the purchase, and the plans are made again.
            guard #available(iOS 18.0, *), let offer = product.subscription?.winBackOffers.first(where: { $0.id == offerID }) else {
                await refresh()
                return .failed("ưu đãi quay lại không còn")
            }
            options.insert(.winBackOffer(offer))
        }
        do {
            switch try await buy(product, options) {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refresh()
                // A downgrade: the customer keeps their plan until it renews
                // as this one, when the paywall said it would, whatever the
                // App Store's status says the moment after.
                if case let .nextPeriod(_, from)? = plan.standing {
                    return .scheduled(productID: plan.id, from: from)
                }
                if case let .scheduled(from)? = plans.first(where: { $0.id == plan.id })?.standing {
                    return .scheduled(productID: plan.id, from: from)
                }
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
        await refresh()
        let restored = entitled.intersection(productIDs)
        return restored.isEmpty ? .nothingToRestore : .restored(restored)
    }

    /// Reads what the customer owns now, and makes the plans again. The
    /// store does so by itself at launch, and after each purchase, restore,
    /// and transaction or change of subscription that comes in.
    public func refreshEntitlements() async {
        await refresh()
    }

    /// Reads `entitled` and `sharedByFamily`. Only as part of a read
    /// (`refresh()`).
    private func readEntitlements() async {
        var owned: [StoreTransaction] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            owned.append(StoreTransaction(transaction))
        }
        entitled = StoreEntitlements.productIDs(from: owned)
        sharedByFamily = StoreEntitlements.familyShared(from: owned)
    }

    /// Reads the customer's payments for the purchase help (`purchases`),
    /// once the products are loaded, which name them and give the format of
    /// their prices. Call when the help appears; the store reads them again
    /// with every transaction that comes in, a refund say.
    public func loadPurchases() async {
        if products.isEmpty, loadState == .idle {
            await loadProducts()
        }
        await reads.run {
            await self.readPurchases()
        }
    }

    /// Reads `purchases`: the signed transactions of the products sold
    /// here, among all the customer's (`Transaction.all`), renewals and
    /// refunded ones included. Only as part of a read (`refresh()`).
    private func readPurchases() async {
        var found: [StorePurchase] = []
        for await result in StoreKit.Transaction.all {
            guard case let .verified(transaction) = result, productIDs.contains(transaction.productID) else { continue }
            found.append(StorePurchase(transaction, product: products[transaction.productID]))
        }
        purchases = PurchaseHistory.listed(found)
    }

    /// The App Store's refund sheet for `purchase` closed with `outcome`
    /// (`PurchaseHelpScreen`'s `onRefund`): a request sent, or one the App
    /// Store already had, is kept.
    public func refundRequestEnded(_ outcome: RefundOutcome, for purchase: StorePurchase) {
        refundRequests = refunds.record(outcome, for: purchase.id)
    }

    /// The app welcomed the customer to `redemption`: it no longer waits.
    public func welcomed(_ redemption: StoreRedemption) {
        inbox.welcomed(redemption)
        if self.redemption == redemption {
            self.redemption = nil
        }
    }

    /// A transaction from outside the app, or one left unfinished: access is
    /// read again, and the transaction finished if the App Store signed it
    /// and it is for a product this store sells, once delivered: access
    /// read, and an offer code's welcome kept. Finished before, it would not
    /// come back if the app closed meanwhile. Finishing another's, a
    /// consumable say, would tell the App Store it was delivered before the
    /// code that sells it had the chance, and it would not come back.
    private func receive(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case let .verified(transaction) = result else { return }
        await refresh()
        guard productIDs.contains(transaction.productID) else { return }
        // After the refresh: the app welcomes them only once the code's
        // product is theirs to use, not when a refund takes it back.
        if let redeemed = StoreRedemption(transaction, entitled: entitled) {
            inbox.keep(redeemed)
            refreshRedemption()
        }
        await transaction.finish()
    }
}

extension StoreTransaction {
    /// What decides access in StoreKit's transaction.
    init(_ transaction: StoreKit.Transaction) {
        self.init(
            productID: transaction.productID, revocationDate: transaction.revocationDate, isUpgraded: transaction.isUpgraded,
            isFamilyShared: transaction.ownershipType == .familyShared
        )
    }
}

extension StorePurchase {
    /// A payment as StoreKit records it, named and priced as `product`, once
    /// loaded, has it: in the App Store's own format for the product's
    /// currency, as the paywall writes prices.
    init(_ transaction: StoreKit.Transaction, product: Product?) {
        var displayPrice: String?
        if let price = transaction.price, let currency = transaction.currency {
            if let product, product.priceFormatStyle.currencyCode == currency.identifier {
                displayPrice = price.formatted(product.priceFormatStyle)
            } else {
                displayPrice = price.formatted(.currency(code: currency.identifier))
            }
        }
        self.init(
            id: transaction.id, productID: transaction.productID, title: product?.displayName, date: transaction.purchaseDate,
            price: transaction.price, displayPrice: displayPrice, isRenewal: transaction.reason == .renewal,
            isFamilyShared: transaction.ownershipType == .familyShared, revocationDate: transaction.revocationDate
        )
    }
}

extension StoreRedemption {
    /// The offer code `transaction` redeemed, if any (`StoreRedemption`'s
    /// rule), with `entitled` read after it came: its offer, read from
    /// `offer` from iOS 17.2, `offerType` before.
    init?(_ transaction: StoreKit.Transaction, entitled: Set<String>) {
        let offer: StoreOfferKind?
        let offerID: String?
        if #available(iOS 17.2, *) {
            offer = transaction.offer.map { StoreOfferKind($0.type) }
            offerID = transaction.offer?.id
        } else {
            offer = transaction.offerType.map(StoreOfferKind.init)
            offerID = transaction.offerID
        }
        self.init(
            transactionID: transaction.id, transaction: StoreTransaction(transaction),
            offer: offer, offerID: offerID, isRenewal: transaction.reason == .renewal, entitled: entitled
        )
    }
}

extension StoreOfferKind {
    /// What StoreKit's offer type says; `.other` for one the kit does not
    /// know.
    init(_ type: StoreKit.Transaction.OfferType) {
        if type == .code {
            self = .code
        } else if type == .introductory {
            self = .introductory
        } else if type == .promotional {
            self = .promotional
        } else if #available(iOS 18.0, *), type == .winBack {
            self = .winBack
        } else {
            self = .other
        }
    }
}

extension StoreSubscription.State {
    /// `state` as the core names it; `nil` for one StoreKit may add later.
    init?(_ state: Product.SubscriptionInfo.RenewalState) {
        switch state {
        case .subscribed: self = .subscribed
        case .inGracePeriod: self = .inGracePeriod
        case .inBillingRetryPeriod: self = .inBillingRetryPeriod
        case .expired: self = .expired
        case .revoked: self = .revoked
        default: return nil
        }
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
            kind = .autoRenewable(
                period: period,
                introOffer: subscription.introductoryOffer.flatMap { IntroOffer($0) },
                group: Group(id: subscription.subscriptionGroupID, level: subscription.groupLevel)
            )
        } else {
            kind = .other
        }
        var winBackOffers: [Offer] = []
        if #available(iOS 18.0, *), let subscription = product.subscription {
            winBackOffers = subscription.winBackOffers.compactMap { Offer($0) }
        }
        self.init(
            id: product.id, displayName: product.displayName, displayPrice: product.displayPrice, price: product.price, kind: kind,
            winBackOffers: winBackOffers
        )
    }
}

extension StoreProduct.Offer {
    /// An offer StoreKit describes; `nil` without an identifier (an
    /// introductory offer has none), or in a period or payment the paywall
    /// cannot write.
    init?(_ offer: Product.SubscriptionOffer) {
        guard let id = offer.id, let terms = StoreProduct.IntroOffer(offer) else { return nil }
        self.init(id: id, payment: terms.payment, displayPrice: offer.displayPrice, period: terms.period, periodCount: terms.periodCount)
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
