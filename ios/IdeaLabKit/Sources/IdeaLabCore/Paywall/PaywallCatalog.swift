import Foundation

/// What the App Store says about a product, as plain values: `LabStore`
/// (`IdeaLabStore`) fills it from StoreKit's `Product`, so the rules that
/// turn products into a paywall's plans (`PaywallCatalog`) are tested
/// anywhere.
public struct StoreProduct: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Bought once, kept for good: "Mua một lần".
        case nonConsumable
        /// Renews every `period` until cancelled, perhaps after an
        /// introductory offer; ranked within its subscription `group`.
        case autoRenewable(period: Period, introOffer: IntroOffer?, group: Group)
        /// Consumables and non-renewing subscriptions: not a paywall plan.
        case other
    }

    /// `Product.SubscriptionPeriod`: three months is `(3, .month)`.
    public struct Period: Hashable, Sendable {
        public enum Unit: Hashable, Sendable {
            case day, week, month, year
        }

        public var value: Int
        public var unit: Unit

        public init(_ value: Int, _ unit: Unit) {
            self.value = value
            self.unit = unit
        }
    }

    /// A subscription's group, and its level there, 1 offering the most
    /// (`Product.SubscriptionInfo.subscriptionGroupID` and `groupLevel`).
    public struct Group: Hashable, Sendable {
        public var id: String
        public var level: Int

        public init(id: String, level: Int) {
            self.id = id
            self.level = level
        }
    }

    /// `Product.SubscriptionOffer`, for the introductory offer.
    public struct IntroOffer: Hashable, Sendable {
        public enum Payment: Hashable, Sendable {
            case freeTrial, payAsYouGo, payUpFront
        }

        public var payment: Payment
        /// One period of the offer; it lasts `periodCount` of them.
        public var period: Period
        public var periodCount: Int

        public init(payment: Payment, period: Period, periodCount: Int = 1) {
            self.payment = payment
            self.period = period
            self.periodCount = periodCount
        }
    }

    public var id: String
    /// `Product.displayName`: "Gói năm".
    public var displayName: String
    /// `Product.displayPrice`: "299.000 ₫", in the storefront's currency.
    public var displayPrice: String
    /// `Product.price`.
    public var price: Decimal
    public var kind: Kind

    /// The subscription group of a subscription; `nil` for anything else.
    public var group: Group? {
        if case let .autoRenewable(_, _, group) = kind { group } else { nil }
    }

    public init(id: String, displayName: String, displayPrice: String, price: Decimal, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.price = price
        self.kind = kind
    }
}

/// The plans a paywall offers, from what the App Store says about the
/// products, by the rules App Review holds a paywall to.
public enum PaywallCatalog {
    /// - Parameters:
    ///   - products: what the App Store returned (`Product.products(for:)`).
    ///   - ids: the products to offer, in the app's order. An id the App
    ///     Store did not return is left out, as is a product that is not a
    ///     subscription renewing every week, month or year, or a purchase
    ///     kept for good: `PaywallPlan` has no other term to show.
    ///   - introOfferEligible: the products whose introductory offer this
    ///     customer may still have (`isEligibleForIntroOffer`). Only a free
    ///     trial is shown, and only to them: a paywall must not promise a
    ///     trial the App Store will not give. Other offers, paid ones, are
    ///     not shown; the App Store's own sheet states them.
    ///   - customer: what the customer has: each plan says where it stands
    ///     against it (`PaywallPlan.standing`). Someone who bought the plan
    ///     kept for good is offered no subscription, only shown theirs.
    ///   - formatted: an amount in the product's own currency, for
    ///     "≈ 24.917 ₫/tháng" (`Product.priceFormatStyle`).
    /// - Returns: the plans, each titled with the product's name. A plan
    ///   cheaper per month than the dearest one says "Tiết kiệm 36%";
    ///   weekly and yearly plans say what they come to per month.
    public static func plans(
        from products: [StoreProduct],
        in ids: [String],
        introOfferEligible: Set<String>,
        customer: StoreCustomer = StoreCustomer(),
        formatted: (StoreProduct, Decimal) -> String
    ) -> [PaywallPlan] {
        let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var offered: [(product: StoreProduct, plan: PaywallPlan)] = []
        for id in ids where seen.insert(id).inserted {
            guard let product = byID[id], let plan = plan(for: product, eligible: introOfferEligible.contains(id)) else { continue }
            offered.append((product, plan))
        }
        let recurring = offered.map(\.plan).filter { $0.term != .lifetime }
        let dearest = recurring.max { (PlanMath.monthlyEquivalent(of: $0) ?? 0) < (PlanMath.monthlyEquivalent(of: $1) ?? 0) }
        // Only their subscriptions in the groups on offer bear on these plans.
        let groups = Set(offered.compactMap { $0.product.group?.id })
        let subscriptions = customer.subscriptions.filter { groups.contains($0.groupID) }
        // Bought by them, not shared by the family: sharing can stop.
        let bought = customer.owned.subtracting(customer.sharedByFamily)
        let ownedForGood = offered.contains { $0.plan.term == .lifetime && bought.contains($0.plan.id) }
        let plans = offered.map { product, plan in
            var plan = plan
            if let dearest, dearest.id != plan.id, let saving = PlanMath.savingsPercent(of: plan, comparedTo: dearest) {
                plan.badge = "Tiết kiệm \(saving)%"
            }
            if plan.term == .weekly || plan.term == .yearly, let perMonth = PlanMath.monthlyEquivalent(of: plan) {
                plan.detail = "≈ \(formatted(product, perMonth))/tháng"
            }
            plan.standing = standing(
                of: product, among: byID, subscriptions: subscriptions, owned: customer.owned,
                sharedByFamily: customer.sharedByFamily, ownedForGood: ownedForGood
            )
            return plan
        }
        guard ownedForGood else { return plans }
        // Nothing more to sell, another plan kept for good included: only
        // what they own, and their subscription, to say it still renews.
        return plans.filter { plan in
            switch plan.standing {
            case .owned?, .current?, .scheduled?: true
            default: false
            }
        }
    }

    /// Where `product` stands against the customer's `subscriptions` and
    /// what they `owned`, some of it `sharedByFamily`.
    static func standing(
        of product: StoreProduct,
        among byID: [String: StoreProduct],
        subscriptions: [StoreSubscription],
        owned: Set<String>,
        sharedByFamily: Set<String>,
        ownedForGood: Bool
    ) -> PaywallPlan.Standing? {
        switch product.kind {
        case .nonConsumable:
            if sharedByFamily.contains(product.id) { return .sharedByFamily }
            // Only a subscription they pay for keeps costing them.
            let renewing = subscriptions.first { $0.renewsAs != nil && !$0.isFamilyShared }.map { title(of: $0.productID, among: byID) }
            if owned.contains(product.id) { return .owned(renewing: renewing) }
            return renewing.map { .alongside(subscription: $0) }
        case let .autoRenewable(period, _, group):
            guard let theirs = subscriptions.first(where: { $0.groupID == group.id }) else { return nil }
            if theirs.isFamilyShared {
                // Buying one of their own is a purchase like anyone's.
                return theirs.productID == product.id ? .sharedByFamily : nil
            }
            if theirs.productID == product.id {
                let renewal: PaywallPlan.Renewal = if let issue = theirs.billingIssue {
                    // The renewal that failed was as the plan they chose, if another.
                    .billingIssue(issue, renewingAs: theirs.renewsAs.flatMap { $0 == product.id ? nil : nextPlan($0, among: byID) })
                } else {
                    switch theirs.renewsAs {
                    case nil: .ends(on: theirs.periodEnds)
                    case .some(product.id): .renews(on: theirs.periodEnds)
                    case let next?: .switches(to: title(of: next, among: byID), on: theirs.periodEnds)
                    }
                }
                return .current(renewal, ownedForGood: ownedForGood)
            }
            // While the App Store cannot charge for theirs, the period it
            // ended is over: no date to start on, nothing left to refund.
            if theirs.renewsAs == product.id {
                return .scheduled(from: theirs.billingIssue == nil ? theirs.periodEnds : nil)
            }
            let replacing = title(of: theirs.productID, among: byID)
            guard theirs.billingIssue == nil,
                  case let .autoRenewable(theirPeriod, _, theirGroup)? = byID[theirs.productID]?.kind
            else {
                return .change(replacing: replacing)
            }
            if group.level < theirGroup.level {
                return .upgrade(replacing: replacing)
            }
            if group.level == theirGroup.level, sameLength(period, theirPeriod) {
                return .crossgrade(replacing: replacing)
            }
            return .nextPeriod(replacing: replacing, from: theirs.periodEnds)
        case .other:
            return nil
        }
    }

    /// What the App Store charges for when a subscription renews as `id`,
    /// another plan of its group: words for it when it was not loaded.
    private static func nextPlan(_ id: String, among byID: [String: StoreProduct]) -> PaywallPlan.NextPlan {
        guard let product = byID[id] else { return PaywallPlan.NextPlan(title: "gói đã chọn cho kỳ sau") }
        var period: StoreProduct.Period?
        if case let .autoRenewable(renewing, _, _) = product.kind {
            period = renewing
        }
        return PaywallPlan.NextPlan(title: product.displayName, displayPrice: product.displayPrice, period: period)
    }

    /// A product's name, or words for it when it was not loaded.
    private static func title(of id: String, among byID: [String: StoreProduct]) -> String {
        byID[id]?.displayName ?? "gói đăng ký hiện tại"
    }

    /// Whether two periods last as long: a year is twelve months, a week
    /// seven days.
    static func sameLength(_ one: StoreProduct.Period, _ other: StoreProduct.Period) -> Bool {
        if one == other { return true }
        guard let term = term(of: one) else { return false }
        return term == self.term(of: other)
    }

    /// The plan `product` makes, if it is one a paywall can show.
    static func plan(for product: StoreProduct, eligible: Bool) -> PaywallPlan? {
        let term: PaywallPlan.Term
        var trial: PaywallPlan.FreeTrial?
        switch product.kind {
        case .nonConsumable:
            term = .lifetime
        case let .autoRenewable(period, introOffer, _):
            guard let renewing = self.term(of: period) else { return nil }
            term = renewing
            if eligible, let introOffer {
                trial = freeTrial(introOffer)
            }
        case .other:
            return nil
        }
        return PaywallPlan(
            id: product.id, term: term, title: product.displayName,
            displayPrice: product.displayPrice, price: product.price, freeTrial: trial
        )
    }

    /// Weekly, monthly or yearly; `nil` for any other period.
    static func term(of period: StoreProduct.Period) -> PaywallPlan.Term? {
        switch (period.value, period.unit) {
        case (1, .week), (7, .day): .weekly
        case (1, .month): .monthly
        case (1, .year), (12, .month): .yearly
        default: nil
        }
    }

    /// The free trial `offer` gives: its period times its count. `nil` for a
    /// paid offer, or an empty one.
    static func freeTrial(_ offer: StoreProduct.IntroOffer) -> PaywallPlan.FreeTrial? {
        guard offer.payment == .freeTrial, offer.period.value > 0, offer.periodCount > 0 else { return nil }
        let count = offer.period.value * offer.periodCount
        switch offer.period.unit {
        case .day: return .days(count)
        case .week: return .days(count * 7)
        case .month: return .months(count)
        case .year: return .years(count)
        }
    }
}
