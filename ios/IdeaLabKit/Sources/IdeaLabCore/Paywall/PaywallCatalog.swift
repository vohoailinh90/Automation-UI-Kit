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
        /// introductory offer.
        case autoRenewable(period: Period, introOffer: IntroOffer?)
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
    ///   - formatted: an amount in the product's own currency, for
    ///     "≈ 24.917 ₫/tháng" (`Product.priceFormatStyle`).
    /// - Returns: the plans, each titled with the product's name. A plan
    ///   cheaper per month than the dearest one says "Tiết kiệm 36%";
    ///   weekly and yearly plans say what they come to per month.
    public static func plans(
        from products: [StoreProduct],
        in ids: [String],
        introOfferEligible: Set<String>,
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
        return offered.map { product, plan in
            var plan = plan
            if let dearest, dearest.id != plan.id, let saving = PlanMath.savingsPercent(of: plan, comparedTo: dearest) {
                plan.badge = "Tiết kiệm \(saving)%"
            }
            if plan.term == .weekly || plan.term == .yearly, let perMonth = PlanMath.monthlyEquivalent(of: plan) {
                plan.detail = "≈ \(formatted(product, perMonth))/tháng"
            }
            return plan
        }
    }

    /// The plan `product` makes, if it is one a paywall can show.
    static func plan(for product: StoreProduct, eligible: Bool) -> PaywallPlan? {
        let term: PaywallPlan.Term
        var trial: PaywallPlan.FreeTrial?
        switch product.kind {
        case .nonConsumable:
            term = .lifetime
        case let .autoRenewable(period, introOffer):
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
