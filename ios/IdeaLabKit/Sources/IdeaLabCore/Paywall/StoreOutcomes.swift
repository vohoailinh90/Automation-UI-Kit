import Foundation

/// A transaction as the App Store reports it (`Transaction`), reduced to
/// what decides access.
public struct StoreTransaction: Hashable, Sendable {
    public var productID: String
    /// When the App Store refunded the purchase, or took it back from Family
    /// Sharing.
    public var revocationDate: Date?
    /// Whether the customer moved from this subscription to a higher one of
    /// its group, which is then what they have.
    public var isUpgraded: Bool
    /// Whether another family member bought it and shares it
    /// (`ownershipType` is `.familyShared`).
    public var isFamilyShared: Bool

    public init(productID: String, revocationDate: Date? = nil, isUpgraded: Bool = false, isFamilyShared: Bool = false) {
        self.productID = productID
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.isFamilyShared = isFamilyShared
    }
}

public enum StoreEntitlements {
    /// The products the customer may use, from the transactions of
    /// `Transaction.currentEntitlements`. That list already leaves out
    /// refunded purchases and expired subscriptions, and keeps a subscription
    /// in its billing grace period, as it should; a transaction with a
    /// revocation date, or of a subscription moved up to another, gives
    /// nothing here either.
    public static func productIDs(from transactions: some Sequence<StoreTransaction>) -> Set<String> {
        Set(transactions.filter { $0.revocationDate == nil && !$0.isUpgraded }.map(\.productID))
    }

    /// Among those, the products the customer has only through Family
    /// Sharing: another family member bought them, and may stop sharing
    /// them. One they bought as well is theirs.
    public static func familyShared(from transactions: some Sequence<StoreTransaction>) -> Set<String> {
        let giving = transactions.filter { $0.revocationDate == nil && !$0.isUpgraded }
        let bought = Set(giving.filter { !$0.isFamilyShared }.map(\.productID))
        return Set(giving.filter(\.isFamilyShared).map(\.productID)).subtracting(bought)
    }
}

/// A subscription the customer has, as the App Store reports it
/// (`Product.SubscriptionInfo.Status`, with its `RenewalInfo`).
public struct StoreSubscription: Hashable, Sendable {
    /// Its subscription group (`subscriptionGroupID`).
    public var groupID: String
    /// The plan they have now (`RenewalInfo.currentProductID`).
    public var productID: String
    /// The plan the next period is bought as (`autoRenewPreference`):
    /// another plan of the group once they chose one that starts then.
    /// `nil` when it does not renew (`willAutoRenew` is false).
    public var renewsAs: String?
    /// When the paid period ends, and it renews or stops
    /// (`RenewalInfo.renewalDate`, else the transaction's `expirationDate`).
    public var periodEnds: Date?
    /// Whether another family member bought it and shares it
    /// (`Transaction.ownershipType` is `.familyShared`): theirs to use, not
    /// to pay for, change or cancel.
    public var isFamilyShared: Bool
    /// A renewal the App Store could not charge for, if any: the App Store
    /// keeps trying, and the plan stays the customer's meanwhile.
    public var billingIssue: BillingIssue?

    /// The App Store could not charge for a renewal (an expired card, say):
    /// it tries again for up to 60 days, until the customer updates their
    /// payment method or cancels (`Product.SubscriptionInfo.RenewalState`).
    public enum BillingIssue: Hashable, Sendable {
        /// In the billing grace period, which the app turns on in App Store
        /// Connect: the plan still gives access, until the date
        /// (`RenewalInfo.gracePeriodExpirationDate`).
        case gracePeriod(until: Date?)
        /// Past any grace period (`inBillingRetryPeriod`): the plan gives no
        /// access until the App Store can charge for it.
        case retrying
    }

    public init(
        groupID: String, productID: String, renewsAs: String?, periodEnds: Date?,
        isFamilyShared: Bool = false, billingIssue: BillingIssue? = nil
    ) {
        self.groupID = groupID
        self.productID = productID
        self.renewsAs = renewsAs
        self.periodEnds = periodEnds
        self.isFamilyShared = isFamilyShared
        self.billingIssue = billingIssue
    }
}

extension StoreSubscription {
    /// How StoreKit says a subscription stands
    /// (`Product.SubscriptionInfo.RenewalState`).
    public enum State: Hashable, Sendable {
        case subscribed
        case inGracePeriod
        case inBillingRetryPeriod
        case expired
        case revoked
    }

    /// What a subscription status (`Product.SubscriptionInfo.Status`, with
    /// its `RenewalInfo` and transaction) says of the customer's
    /// subscription. `nil` when it is over, expired or revoked: nothing to
    /// show or charge for. One in billing retry gives no access, but is
    /// kept: the App Store still tries to charge for it.
    public init?(
        groupID: String, state: State, currentProductID: String, willAutoRenew: Bool, autoRenewPreference: String?,
        renewalDate: Date?, expirationDate: Date?, gracePeriodExpirationDate: Date?, isFamilyShared: Bool
    ) {
        let billingIssue: BillingIssue?
        switch state {
        case .subscribed: billingIssue = nil
        case .inGracePeriod: billingIssue = .gracePeriod(until: gracePeriodExpirationDate)
        case .inBillingRetryPeriod: billingIssue = .retrying
        case .expired, .revoked: return nil
        }
        self.init(
            groupID: groupID,
            productID: currentProductID,
            renewsAs: willAutoRenew ? autoRenewPreference ?? currentProductID : nil,
            periodEnds: renewalDate ?? expirationDate,
            isFamilyShared: isFamilyShared,
            billingIssue: billingIssue
        )
    }
}

/// What the customer has of what a paywall sells, for `PaywallCatalog` to
/// say where each plan stands.
public struct StoreCustomer: Hashable, Sendable {
    /// What they may use now (`LabStore.entitled`); a purchase kept for good
    /// among it is theirs, unless a family member shares it.
    public var owned: Set<String>
    /// Among `owned`, what they have only through Family Sharing
    /// (`LabStore.sharedByFamily`).
    public var sharedByFamily: Set<String>
    /// Their subscriptions, at most one per group (`LabStore.subscriptions`).
    public var subscriptions: [StoreSubscription]

    public init(owned: Set<String> = [], sharedByFamily: Set<String> = [], subscriptions: [StoreSubscription] = []) {
        self.owned = owned
        self.sharedByFamily = sharedByFamily
        self.subscriptions = subscriptions
    }
}

/// Apple's pages a paywall links to.
public enum StoreLinks {
    /// The payment methods of the customer's Apple Account, where they fix
    /// a payment the App Store could not take ("Reducing Involuntary
    /// Subscriber Churn"; iOS and macOS only).
    public static let billing = URL(string: "https://apps.apple.com/account/billing")!
}

/// What to tell a customer whose subscription the App Store could not
/// renew, outside the paywall: in Settings, say (`BillingIssueBanner`).
public struct BillingNotice: Hashable, Sendable {
    /// The subscription's product.
    public var productID: String
    public var issue: StoreSubscription.BillingIssue
    /// "Chưa gia hạn được Gói tháng", "Gói tháng đang tạm dừng".
    public var title: String
    /// What happened, until when the plan still works, and what to do.
    public var message: String
    /// Update the payment method (`updatePayment`), or, for someone who
    /// bought the plan kept for good, cancel the subscription
    /// (`manageSubscriptions`).
    public var action: PaywallCopy.Action
    /// "Cập nhật thanh toán", "Quản lý gói đăng ký".
    public var actionTitle: String

    public init(
        productID: String, issue: StoreSubscription.BillingIssue, title: String, message: String,
        action: PaywallCopy.Action, actionTitle: String
    ) {
        self.productID = productID
        self.issue = issue
        self.title = title
        self.message = message
        self.action = action
        self.actionTitle = actionTitle
    }
}

/// How a purchase ended (`Product.PurchaseResult`, or a StoreKit error).
public enum PurchaseOutcome: Hashable, Sendable {
    /// Bought, and signed by the App Store: the product is unlocked.
    case purchased(productID: String)
    /// Bought, to start when the customer's subscription period ends, on
    /// the date: a downgrade, or a plan as good for another period. Until
    /// then they keep the plan they have.
    case scheduled(productID: String, from: Date?)
    /// Waiting on someone else: a parent's approval (Ask to Buy), or the
    /// bank. The app unlocks when the App Store says so, even later
    /// (`Transaction.updates`).
    case pending
    /// The customer closed the App Store's sheet.
    case cancelled
    /// The App Store's signature did not check out: nothing is unlocked.
    case unverified
    /// The plan's product did not come from the App Store.
    case unavailable
    /// StoreKit failed; its description.
    case failed(String)
}

/// How "Khôi phục mua hàng" ended (`AppStore.sync()`).
public enum RestoreOutcome: Hashable, Sendable {
    /// The app's products the customer may use now.
    case restored(Set<String>)
    /// The App Store account has none of the app's products.
    case nothingToRestore
    /// The customer closed the App Store's sign-in sheet.
    case cancelled
    /// StoreKit failed; its description.
    case failed(String)
}

/// What to tell the customer after a purchase or a restore.
public struct StoreMessage: Hashable, Sendable {
    public enum Tone: Hashable, Sendable {
        /// It worked.
        case success
        /// Nothing went wrong, but nothing is unlocked yet.
        case notice
        /// It did not work.
        case failure
    }

    public var text: String
    public var tone: Tone

    public init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }
}

/// The words for `PurchaseOutcome` and `RestoreOutcome`, in one place.
public enum StoreCopy {
    /// `nil` when the customer cancelled: they know, and a message would
    /// only get in the way.
    ///
    /// - Parameters:
    ///   - plans: the paywall's plans, to name what was bought.
    ///   - calendar: the clock the date a plan starts on is written in.
    public static func purchaseMessage(
        for outcome: PurchaseOutcome, plans: [PaywallPlan], calendar: Calendar = .autoupdatingCurrent
    ) -> StoreMessage? {
        switch outcome {
        case let .purchased(productID):
            let title = plans.first { $0.id == productID }?.title
            return StoreMessage(title.map { "Đã mua \($0). Cảm ơn bạn!" } ?? "Đã mua. Cảm ơn bạn!", tone: .success)
        case let .scheduled(productID, from):
            let title = plans.first { $0.id == productID }?.title ?? "Gói mới"
            let start = from.map { "từ ngày \(LedgerExport.day($0, calendar))" } ?? "từ kỳ sau"
            return StoreMessage("\(title) sẽ bắt đầu \(start), khi gói hiện tại hết kỳ.", tone: .success)
        case .pending:
            return StoreMessage("Giao dịch đang chờ duyệt. Khi được duyệt, app tự mở khoá.", tone: .notice)
        case .cancelled:
            return nil
        case .unverified:
            return StoreMessage(
                "App Store chưa xác nhận giao dịch này, nên app chưa mở khoá. Nếu đã bị trừ tiền, hãy bấm Khôi phục mua hàng.",
                tone: .failure
            )
        case .unavailable:
            return StoreMessage("Chưa tải được gói này từ App Store. Kiểm tra kết nối mạng rồi thử lại.", tone: .failure)
        case let .failed(reason):
            return StoreMessage("Chưa mua được: \(reason)", tone: .failure)
        }
    }

    /// `nil` when the customer cancelled.
    ///
    /// - Parameter plans: the paywall's plans, to name what came back, in
    ///   their order.
    public static func restoreMessage(for outcome: RestoreOutcome, plans: [PaywallPlan]) -> StoreMessage? {
        switch outcome {
        case let .restored(productIDs):
            let titles = plans.filter { productIDs.contains($0.id) }.map(\.title)
            return StoreMessage(
                titles.isEmpty ? "Đã khôi phục mua hàng." : "Đã khôi phục: \(titles.joined(separator: ", ")).",
                tone: .success
            )
        case .nothingToRestore:
            return StoreMessage("Tài khoản App Store này chưa mua gói nào của app.", tone: .notice)
        case .cancelled:
            return nil
        case let .failed(reason):
            return StoreMessage("Chưa khôi phục được: \(reason)", tone: .failure)
        }
    }

    /// What to tell the customer about a subscription of theirs the App
    /// Store could not renew, if any; not one a family member shares, whom
    /// the App Store charges. One on hold, with no access, comes before one
    /// in its grace period, and of those the one whose grace ends first.
    /// When it was to renew as a plan they chose for the next period, the
    /// notice names that plan, which the App Store is trying to charge for.
    ///
    /// - Parameters:
    ///   - customer: what they have (`LabStore.customer`).
    ///   - plans: the paywall's plans, to name the subscription, and to
    ///     tell whether they bought the plan kept for good in its place:
    ///     they then only need to cancel it. Its own plan says so
    ///     (`ownedForGood`): a plan kept for good stands in only for the
    ///     subscriptions offered with it. One the paywall does not show,
    ///     of another group, is not known to be covered, so it is paid for.
    ///   - calendar: the clock the grace period's end is written in.
    public static func billingNotice(
        for customer: StoreCustomer, plans: [PaywallPlan], calendar: Calendar = .autoupdatingCurrent
    ) -> BillingNotice? {
        let failing = customer.subscriptions.filter { !$0.isFamilyShared && $0.billingIssue != nil }
        guard let subscription = failing.min(by: moreUrgent), let issue = subscription.billingIssue else { return nil }
        let theirs = plans.first { $0.id == subscription.productID }
        let name = theirs?.title ?? "gói đăng ký"
        // A plan they chose for the next period is what the App Store is
        // trying to charge for: the notice names it, and says it is a change.
        let next = chosenPlan(of: subscription, theirs: theirs, among: plans)
        let charged = next ?? name
        let change = next.map { " gia hạn \(name) thành \($0)" }
        let title = switch issue {
        case .gracePeriod: "Chưa gia hạn được \(charged)"
        case .retrying: "\(charged.prefix(1).uppercased() + charged.dropFirst()) đang tạm dừng"
        }
        if case .current(_, ownedForGood: true)? = theirs?.standing {
            return BillingNotice(
                productID: subscription.productID, issue: issue, title: title,
                message: "App Store chưa thu được tiền\(change ?? " gia hạn \(name)"). "
                    + "Bạn đã mua gói dùng mãi mãi nên không cần gói này: "
                    + "huỷ nó trong Quản lý gói đăng ký để App Store thôi thu tiền.",
                action: .manageSubscriptions, actionTitle: "Quản lý gói đăng ký"
            )
        }
        let message = switch issue {
        case let .gracePeriod(until?):
            "App Store chưa thu được tiền\(change ?? ""). "
                + "Bạn vẫn dùng được đến \(PaywallCopy.moment(until, calendar)): "
                + "cập nhật phương thức thanh toán trước lúc đó để không bị gián đoạn."
        case .gracePeriod(nil):
            "App Store chưa thu được tiền\(change ?? "") và đang thử lại. "
                + "Cập nhật phương thức thanh toán để không bị gián đoạn."
        case .retrying:
            "App Store chưa thu được tiền\(change ?? " gia hạn"). Cập nhật phương thức thanh toán: App Store sẽ thử lại, "
                + "và gói dùng tiếp ngay khi thu được."
        }
        return BillingNotice(
            productID: subscription.productID, issue: issue, title: title, message: message,
            action: .updatePayment, actionTitle: "Cập nhật thanh toán"
        )
    }

    /// The plan `subscription` renews as when the customer chose another for
    /// the next period, named as the paywall names it: from their plan's
    /// card, or else the plan's own; in words when neither has it. `nil`
    /// when it renews as itself.
    private static func chosenPlan(
        of subscription: StoreSubscription, theirs: PaywallPlan?, among plans: [PaywallPlan]
    ) -> String? {
        guard let id = subscription.renewsAs, id != subscription.productID else { return nil }
        if case let .current(.billingIssue(_, next?), _)? = theirs?.standing {
            return next.title
        }
        return plans.first { $0.id == id }?.title ?? "gói đã chọn cho kỳ sau"
    }

    /// Whether `one` needs the customer before `other`: on hold before in
    /// its grace period, and the grace that ends first before the others.
    private static func moreUrgent(_ one: StoreSubscription, than other: StoreSubscription) -> Bool {
        switch (one.billingIssue, other.billingIssue) {
        case (.retrying?, .gracePeriod?):
            true
        case let (.gracePeriod(mine)?, .gracePeriod(theirs)?):
            (mine ?? .distantFuture) < (theirs ?? .distantFuture)
        default:
            false
        }
    }
}
