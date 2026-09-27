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

    /// A plan against what the customer already has. Within a subscription
    /// group Apple ranks plans by level, 1 offering the most: buying a plan
    /// with more is an upgrade, which starts at once and refunds what is
    /// left of the old plan; with less, a downgrade, which starts when the
    /// paid period ends; with as much, a crossgrade, at once for the same
    /// period, else when the period ends.
    public enum Standing: Hashable, Sendable {
        /// The customer's subscription. `ownedForGood`: they also bought
        /// the plan kept for good, so this one only costs them now.
        case current(Renewal, ownedForGood: Bool)
        /// Bought for good. `renewing`: the title of a subscription they
        /// still pay for, which buying this did not stop.
        case owned(renewing: String?)
        /// Theirs through Family Sharing: another family member bought it
        /// and pays for it, so none of the rules of changing plans apply.
        case sharedByFamily
        /// Their subscription renews as this plan when its period ends, on
        /// the date: they chose it already. No date while the App Store
        /// cannot charge for their plan: it starts when it can.
        case scheduled(from: Date?)
        /// More than their plan (its title): starts at once, and the App
        /// Store refunds what is left of theirs.
        case upgrade(replacing: String)
        /// As much as their plan, for the same period: starts at once.
        case crossgrade(replacing: String)
        /// Less than their plan, or as much for another period: starts
        /// when their period ends, on the date.
        case nextPeriod(replacing: String, from: Date?)
        /// In their group, but when this one would start is not known:
        /// their plan was not among the products loaded, or the App Store
        /// could not charge for it, so its period is over and nothing of it
        /// is left to refund.
        case change(replacing: String)
        /// Kept for good, while their subscription (its title) renews:
        /// buying this does not stop that subscription.
        case alongside(subscription: String)
    }

    /// When the customer's subscription renews, and as what.
    public enum Renewal: Hashable, Sendable {
        /// As the same plan, on the date.
        case renews(on: Date?)
        /// As another plan (its title), on the date.
        case switches(to: String, on: Date?)
        /// It does not: it ends on the date.
        case ends(on: Date?)
        /// The App Store could not charge for it, and keeps trying: for the
        /// plan the customer chose for the next period (`renewingAs`), when
        /// they chose another, else for this one.
        case billingIssue(StoreSubscription.BillingIssue, renewingAs: NextPlan? = nil)
    }

    /// The plan a subscription renews as when the customer chose another,
    /// which is then what the App Store charges for.
    public struct NextPlan: Hashable, Sendable {
        /// "Gói tháng" (`Product.displayName`).
        public var title: String
        /// "39.000 ₫" (`Product.displayPrice`); `nil` when its product was
        /// not loaded.
        public var displayPrice: String?
        /// How often it is charged, as the App Store gives it, three months
        /// say; `nil` when not known. A price is only shown with it.
        public var period: StoreProduct.Period?

        public init(title: String, displayPrice: String? = nil, period: StoreProduct.Period? = nil) {
            self.title = title
            self.displayPrice = displayPrice
            self.period = period
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
    /// Where the plan stands against what the customer has
    /// (`PaywallCatalog`, from `StoreCustomer`): `nil` for a customer with
    /// none of the plans, and for a plan their purchases do not touch.
    public var standing: Standing?
    /// The subscription groups whose subscription this plan takes the
    /// place of (`PaywallCatalog`): a subscription's own group, where
    /// buying it changes their plan; for a plan kept for good, every group
    /// offered with it, whose subscriptions its owner needs no more, one
    /// no longer on offer included. The groups a paywall offers are those
    /// of its plans.
    public var standsInFor: Set<String>
    /// The win-back offer the customer may redeem on this plan, the best
    /// the App Store lists for them (`PaywallCatalog`); buying the plan
    /// applies it (`LabStore.purchase`).
    public var winBackOffer: StoreProduct.Offer?

    public init(
        id: String, term: Term, title: String, displayPrice: String, price: Decimal,
        freeTrial: FreeTrial? = nil, badge: String? = nil, detail: String? = nil, standing: Standing? = nil,
        standsInFor: Set<String> = [], winBackOffer: StoreProduct.Offer? = nil
    ) {
        self.id = id
        self.term = term
        self.title = title
        self.displayPrice = displayPrice
        self.price = price
        self.freeTrial = freeTrial
        self.badge = badge
        self.detail = detail
        self.standing = standing
        self.standsInFor = standsInFor
        self.winBackOffer = winBackOffer
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
