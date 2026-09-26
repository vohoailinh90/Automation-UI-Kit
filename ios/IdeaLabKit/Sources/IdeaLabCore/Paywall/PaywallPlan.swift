import Foundation

/// One purchasable option as a paywall shows it.
///
/// Fill it from StoreKit — `Product.id`, `Product.displayName`,
/// `Product.displayPrice`, `Product.price` — never from hard-coded numbers:
/// the App Store prices each storefront in its own currency, and Apple requires
/// the amount the user is actually billed to be the most prominent price on the
/// screen (App Store Review Guideline 3.1.2 and the subscription sign-up rules).
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

    public var id: String
    public var term: Term
    /// "Gói năm", "Mua một lần" — `Product.displayName`.
    public var title: String
    /// Exactly what the user is billed, as StoreKit formats it: `Product.displayPrice`.
    public var displayPrice: String
    /// `Product.price`, only used to compare plans.
    public var price: Decimal
    /// Length of a free introductory offer, if the product has one.
    public var freeTrialDays: Int?
    /// Small highlight on the card: "Tiết kiệm 36%" (see `PlanMath.savingsPercent`), "Phổ biến nhất".
    public var badge: String?
    /// Secondary line under the title, e.g. "≈ 24.917 ₫/tháng" from
    /// `PlanMath.monthlyEquivalent`. Kept smaller than `displayPrice` on purpose.
    public var detail: String?

    public init(
        id: String, term: Term, title: String, displayPrice: String, price: Decimal,
        freeTrialDays: Int? = nil, badge: String? = nil, detail: String? = nil
    ) {
        self.id = id
        self.term = term
        self.title = title
        self.displayPrice = displayPrice
        self.price = price
        self.freeTrialDays = freeTrialDays
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
