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
    ///
    /// - Parameters:
    ///   - customer: what they have (`LabStore.customer`).
    ///   - plans: the paywall's plans, to name the subscription, and to
    ///     tell whether they bought the plan kept for good: they then only
    ///     need to cancel it.
    ///   - calendar: the clock the grace period's end is written in.
    public static func billingNotice(
        for customer: StoreCustomer, plans: [PaywallPlan], calendar: Calendar = .autoupdatingCurrent
    ) -> BillingNotice? {
        let failing = customer.subscriptions.filter { !$0.isFamilyShared && $0.billingIssue != nil }
        guard let subscription = failing.min(by: moreUrgent), let issue = subscription.billingIssue else { return nil }
        let name = plans.first { $0.id == subscription.productID }?.title ?? "gói đăng ký"
        let title = switch issue {
        case .gracePeriod: "Chưa gia hạn được \(name)"
        case .retrying: "\(name.prefix(1).uppercased() + name.dropFirst()) đang tạm dừng"
        }
        let bought = customer.owned.subtracting(customer.sharedByFamily)
        if plans.contains(where: { $0.term == .lifetime && bought.contains($0.id) }) {
            return BillingNotice(
                productID: subscription.productID, issue: issue, title: title,
                message: "App Store chưa thu được tiền gia hạn \(name). Bạn đã mua gói dùng mãi mãi nên không cần gói này: "
                    + "huỷ nó trong Quản lý gói đăng ký để App Store thôi thu tiền.",
                action: .manageSubscriptions, actionTitle: "Quản lý gói đăng ký"
            )
        }
        let message = switch issue {
        case let .gracePeriod(until?):
            "App Store chưa thu được tiền. Bạn vẫn dùng được đến hết ngày \(LedgerExport.day(until, calendar)): "
                + "cập nhật phương thức thanh toán trước ngày đó để không bị gián đoạn."
        case .gracePeriod(nil):
            "App Store chưa thu được tiền và đang thử lại. Cập nhật phương thức thanh toán để không bị gián đoạn."
        case .retrying:
            "App Store chưa thu được tiền gia hạn. Cập nhật phương thức thanh toán: App Store sẽ thử lại, "
                + "và gói dùng tiếp ngay khi thu được."
        }
        return BillingNotice(
            productID: subscription.productID, issue: issue, title: title, message: message,
            action: .updatePayment, actionTitle: "Cập nhật thanh toán"
        )
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
