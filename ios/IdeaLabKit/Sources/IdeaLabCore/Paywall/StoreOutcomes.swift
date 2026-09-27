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

    public init(productID: String, revocationDate: Date? = nil, isUpgraded: Bool = false) {
        self.productID = productID
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
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
}

/// How a purchase ended (`Product.PurchaseResult`, or a StoreKit error).
public enum PurchaseOutcome: Hashable, Sendable {
    /// Bought, and signed by the App Store: the product is unlocked.
    case purchased(productID: String)
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
    /// - Parameter plans: the paywall's plans, to name what was bought.
    public static func purchaseMessage(for outcome: PurchaseOutcome, plans: [PaywallPlan]) -> StoreMessage? {
        switch outcome {
        case let .purchased(productID):
            let title = plans.first { $0.id == productID }?.title
            return StoreMessage(title.map { "Đã mua \($0). Cảm ơn bạn!" } ?? "Đã mua. Cảm ơn bạn!", tone: .success)
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
}
