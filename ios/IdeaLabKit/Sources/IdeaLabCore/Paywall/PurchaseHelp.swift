import Foundation

/// A payment the customer made for a product the app sells, as the purchase
/// help lists it (`PurchaseHelpScreen`): one transaction of
/// `Transaction.all`, a purchase or a renewal. The App Store's refund sheet
/// takes one of these.
public struct StorePurchase: Identifiable, Hashable, Sendable {
    /// The transaction's identifier, which the App Store's refund sheet takes.
    public var id: UInt64
    public var productID: String
    /// What the App Store calls the product (`Product.displayName`): "Gói
    /// năm". `nil` while the products are not loaded.
    public var title: String?
    /// When the customer paid (`purchaseDate`): the purchase, or the renewal.
    public var date: Date
    /// What they paid (`Transaction.price`): `nil` when StoreKit does not
    /// say, 0 for a free trial or a free offer.
    public var price: Decimal?
    /// The same, as the App Store writes prices: "299.000 ₫".
    public var displayPrice: String?
    /// A renewal of a subscription, not the purchase that started it.
    public var isRenewal: Bool
    /// A family member bought it and shares it (Family Sharing): only they
    /// can ask for a refund.
    public var isFamilyShared: Bool
    /// When the App Store refunded it, or took it back.
    public var revocationDate: Date?

    public init(
        id: UInt64, productID: String, title: String? = nil, date: Date, price: Decimal? = nil, displayPrice: String? = nil,
        isRenewal: Bool = false, isFamilyShared: Bool = false, revocationDate: Date? = nil
    ) {
        self.id = id
        self.productID = productID
        self.title = title
        self.date = date
        self.price = price
        self.displayPrice = displayPrice
        self.isRenewal = isRenewal
        self.isFamilyShared = isFamilyShared
        self.revocationDate = revocationDate
    }
}

/// Where a purchase stands for a refund, on the purchase help.
public enum RefundStanding: Hashable, Sendable {
    /// "Yêu cầu hoàn tiền" opens the App Store's refund sheet.
    case open
    /// The App Store has a request for it: sent from the app, or it said so
    /// when asked again. Pending, granted or declined, it takes no other.
    case requested
    /// Refunded, or taken back, on that date.
    case refunded(Date)
}

/// The purchases the purchase help lists, and where each stands.
public enum PurchaseHistory {
    /// The payments the help lists, newest first: the customer's own, as
    /// only whoever paid can ask for a refund, and only those that cost
    /// something (a free trial or a free offer charged nothing). A payment
    /// whose price StoreKit does not give is listed.
    public static func listed(_ purchases: some Sequence<StorePurchase>) -> [StorePurchase] {
        purchases
            .filter { !$0.isFamilyShared && $0.price != 0 }
            .sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    /// Where `purchase` stands, given the purchases with a refund request
    /// (`StoreRefundRequests`): refunded once the App Store says so, whether
    /// or not the app sent the request.
    public static func standing(of purchase: StorePurchase, requested: Set<UInt64>) -> RefundStanding {
        if let date = purchase.revocationDate {
            return .refunded(date)
        }
        return requested.contains(purchase.id) ? .requested : .open
    }
}

/// How the App Store's refund sheet ended (`refundRequestSheet`).
public enum RefundOutcome: Hashable, Sendable {
    /// The request went to the App Store, which decides.
    case requested
    /// The customer closed the sheet.
    case cancelled
    /// The App Store already had a request for this purchase: pending,
    /// granted or declined.
    case alreadyRequested
    /// Not sent: StoreKit's description.
    case failed(String)
}

/// The purchases with a refund request, kept across launches
/// (`UserDefaults`): the help then says a request is under way, rather than
/// offer one the App Store turns down as a duplicate. Once the App Store
/// refunds, the purchase says so itself (`revocationDate`).
public struct StoreRefundRequests {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "IdeaLabStore.refundRequests") {
        self.defaults = defaults
        self.key = key
    }

    /// The transactions with a request.
    public var requested: Set<UInt64> {
        guard let data = defaults.data(forKey: key), let ids = try? JSONDecoder().decode([UInt64].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    /// The refund sheet for `transactionID` ended with `outcome`: a request
    /// sent, or one the App Store already had, is kept. Returns the
    /// transactions with a request.
    @discardableResult
    public func record(_ outcome: RefundOutcome, for transactionID: UInt64) -> Set<UInt64> {
        var ids = requested
        guard outcome == .requested || outcome == .alreadyRequested, ids.insert(transactionID).inserted else { return ids }
        if let data = try? JSONEncoder().encode(ids.sorted()) {
            defaults.set(data, forKey: key)
        }
        return ids
    }
}

extension StoreLinks {
    /// Apple's page on refund requests, in Vietnamese, which the purchase
    /// help links to, as the HIG suggests: how to ask, and what happens
    /// next, in Apple's words (HT204084).
    public static let refunds = URL(string: "https://support.apple.com/vi-vn/HT204084")!
}

extension StoreCopy {
    /// What the purchase is: the App Store's name for its product, else
    /// the plan's.
    public static func purchaseTitle(_ purchase: StorePurchase, plans: [PaywallPlan] = []) -> String {
        purchase.title ?? plans.first { $0.id == purchase.productID }?.title ?? "Gói đã mua"
    }

    /// "Mua ngày 12/09/2026 · 299.000 ₫", "Gia hạn ngày 12/10/2026 ·
    /// 39.000 ₫": when, and what the customer paid, for them to find the
    /// payment they have a problem with, as a bank statement shows it.
    ///
    /// - Parameter calendar: the clock the date is written in.
    public static func purchaseLine(_ purchase: StorePurchase, calendar: Calendar = .autoupdatingCurrent) -> String {
        let when = "\(purchase.isRenewal ? "Gia hạn" : "Mua") ngày \(LedgerExport.day(purchase.date, calendar))"
        return purchase.displayPrice.map { "\(when) · \($0)" } ?? when
    }

    /// "Đã gửi yêu cầu hoàn tiền", "Đã hoàn tiền ngày 20/09/2026": said in
    /// place of the button. `nil` while the button is there.
    public static func refundLine(_ standing: RefundStanding, calendar: Calendar = .autoupdatingCurrent) -> String? {
        switch standing {
        case .open: nil
        case .requested: "Đã gửi yêu cầu hoàn tiền"
        case let .refunded(date): "Đã hoàn tiền ngày \(LedgerExport.day(date, calendar))"
        }
    }

    /// What to say once the App Store's refund sheet closes; `nil` when the
    /// customer closed it. Never whether Apple will refund: the App Store
    /// decides, and tells them.
    public static func refundMessage(for outcome: RefundOutcome) -> StoreMessage? {
        switch outcome {
        case .requested:
            StoreMessage("Đã gửi yêu cầu hoàn tiền.", tone: .success)
        case .cancelled:
            nil
        case .alreadyRequested:
            StoreMessage("Giao dịch này đã có yêu cầu hoàn tiền.", tone: .notice)
        case let .failed(reason):
            StoreMessage("Chưa gửi được yêu cầu hoàn tiền: \(reason)", tone: .failure)
        }
    }
}
