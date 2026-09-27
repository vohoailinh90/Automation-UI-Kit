import Foundation

/// An offer code the customer redeemed: in the app's sheet for offer codes
/// (`offerCodeRedemption`), in the App Store, or through a link, perhaps
/// before they ever opened the app. The code unlocks its product like a
/// purchase, and its transaction reaches the app the same way
/// (`Transaction.updates`); Apple asks apps to welcome the customer to what
/// it unlocked right away.
public struct StoreRedemption: Hashable, Sendable {
    /// The transaction the code made (`Transaction.id`): each redemption is
    /// told once.
    public var transactionID: UInt64
    /// The product the code was for.
    public var productID: String
    /// The offer's reference name in App Store Connect (`Transaction.Offer.id`,
    /// iOS 17.2 and later).
    public var offerID: String?

    public init(transactionID: UInt64, productID: String, offerID: String? = nil) {
        self.transactionID = transactionID
        self.productID = productID
        self.offerID = offerID
    }
}

/// What kind of offer a transaction was bought with (`Transaction.OfferType`).
public enum StoreOfferKind: Hashable, Sendable {
    case introductory
    case promotional
    case code
    case winBack
    /// One StoreKit may add later.
    case other
}

extension StoreRedemption {
    /// The redemption a transaction tells, if any: a purchase the customer
    /// made themselves (`Transaction.reason` is `.purchase`, not one a
    /// family member shares) with an offer code, which still gives them its
    /// product: not refunded, revoked or moved up to another plan, and
    /// among what they may use once it came (`entitled`). The App Store
    /// sends the transaction again when it takes access away, with the same
    /// offer and reason, and that is no redemption. A renewal at the code's
    /// price is not one either: they were welcomed when they redeemed it,
    /// and a code for the next period of a subscription they have makes no
    /// transaction until that renewal.
    public init?(
        transactionID: UInt64, transaction: StoreTransaction, offer: StoreOfferKind?, offerID: String? = nil,
        isRenewal: Bool, entitled: Set<String>
    ) {
        guard offer == .code, !isRenewal, !transaction.isFamilyShared,
              transaction.revocationDate == nil, !transaction.isUpgraded,
              entitled.contains(transaction.productID)
        else { return nil }
        self.init(transactionID: transactionID, productID: transaction.productID, offerID: offerID)
    }
}

extension StoreCopy {
    /// The welcome once an offer code has unlocked its product, naming it
    /// when it is one of the paywall's plans.
    public static func redeemMessage(for redemption: StoreRedemption, plans: [PaywallPlan]) -> StoreMessage {
        let title = plans.first { $0.id == redemption.productID }?.title
        return StoreMessage(
            title.map { "Đã áp dụng mã ưu đãi: \($0). Chào mừng bạn!" } ?? "Đã áp dụng mã ưu đãi. Chào mừng bạn!",
            tone: .success
        )
    }

    /// The App Store's sheet for offer codes did not open; StoreKit's
    /// description. A code the customer closed the sheet on needs no word.
    public static func offerCodeFailure(_ reason: String) -> StoreMessage {
        StoreMessage("Chưa mở được trang nhập mã: \(reason)", tone: .failure)
    }
}
