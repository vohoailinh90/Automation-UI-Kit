import Foundation

/// One purchasable option as a paywall shows it.
///
/// Fill it from StoreKit — `Product.id`, `Product.displayName`,
/// `Product.displayPrice`, `Product.price`, as `PaywallCatalog` does — never
/// from hard-coded numbers: the App Store prices each storefront in its own
/// currency, and Apple requires the amount the user is actually billed to be
/// the most prominent price on the screen (App Store Review Guideline 3.1.2
/// and the subscription sign-up rules).
public struct PaywallPlan: Identifiable, Hashable, Sendable {
    public enum Term: Hashable, Sendable {
        case weekly
        case monthly
        case yearly
        /// Non-consumable "Mua một lần": no renewal, no per-month maths.
        case lifetime

        /// Months covered by one payment, `nil` for lifetime.
        var months: Decimal? {
            switch self {
            case .weekly: Decimal(12) / Decimal(52)
            case .monthly: 1
            case .yearly: 12
            case .lifetime: nil
            }
        }
    }

    /// A free introductory offer, as long as the App Store says: days (a
    /// week is seven), or calendar months or years, which have no fixed
    /// number of days, so a month's trial is never promised as "30 ngày".
    public enum FreeTrial: Hashable, Sendable {
        case days(Int)
        case months(Int)
        case years(Int)

        /// How many days, months or years.
        public var count: Int {
            switch self {
            case let .days(count), let .months(count), let .years(count): count
            }
        }

        /// "7 ngày", "1 tháng", "1 năm": Vietnamese nouns take no plural.
        public var text: String {
            switch self {
            case let .days(count): "\(count) ngày"
            case let .months(count): "\(count) tháng"
            case let .years(count): "\(count) năm"
            }
        }
    }

    public var id: String
    public var term: Term
    /// "Gói năm", "Mua một lần" — `Product.displayName`.
    public var title: String
    /// Exactly what the user is billed, as StoreKit formats it: `Product.displayPrice`.
    public var displayPrice: String
    /// `Product.price`, only used to compare plans.
    public var price: Decimal
    /// The free introductory offer, if the product has one and the customer
    /// may still have it (`Product.SubscriptionInfo.isEligibleForIntroOffer`).
    public var freeTrial: FreeTrial?
    /// Small highlight on the card: "Tiết kiệm 36%" (see `PlanMath.savingsPercent`), "Phổ biến nhất".
    public var badge: String?
    /// Secondary line under the title, e.g. "≈ 24.917 ₫/tháng" from
    /// `PlanMath.monthlyEquivalent`. Kept smaller than `displayPrice` on purpose.
    public var detail: String?

    public init(
        id: String, term: Term, title: String, displayPrice: String, price: Decimal,
        freeTrial: FreeTrial? = nil, badge: String? = nil, detail: String? = nil
    ) {
        self.id = id
        self.term = term
        self.title = title
        self.displayPrice = displayPrice
        self.price = price
        self.freeTrial = freeTrial
        self.badge = badge
        self.detail = detail
    }
}

public enum PlanMath {
    /// What `plan` costs per month, for the small "≈ 24.917 ₫/tháng" line.
    /// `nil` for lifetime. Format the result with the product's own
    /// `priceFormatStyle` so it matches `displayPrice`.
    public static func monthlyEquivalent(of plan: PaywallPlan) -> Decimal? {
        guard let months = plan.term.months else { return nil }
        return plan.price / months
    }

    /// Whole-percent saving of `plan` over `baseline` for the same span of time,
    /// e.g. a yearly plan against twelve monthly payments. Rounded down, so the
    /// badge never promises more than the user saves. `nil` when either plan is
    /// lifetime, prices are not positive, or there is no saving.
    public static func savingsPercent(of plan: PaywallPlan, comparedTo baseline: PaywallPlan) -> Int? {
        guard let planMonthly = monthlyEquivalent(of: plan),
              let baselineMonthly = monthlyEquivalent(of: baseline),
              plan.price > 0, baseline.price > 0 else { return nil }

        var percent = (1 - planMonthly / baselineMonthly) * 100
        var floored = Decimal()
        NSDecimalRound(&floored, &percent, 0, .down)
        let whole = NSDecimalNumber(decimal: floored).intValue
        return whole > 0 ? whole : nil
    }
}
