import Foundation
@testable import IdeaLabCore
import Testing

@Suite("Offer codes: the redemption a transaction tells, and the welcome")
struct OfferCodeTests {
    private let yearly = StoreTransaction(productID: "pro.yearly")

    @Test("A purchase with an offer code that gives the plan is a redemption; a renewal at the code's price is not")
    func redemption() {
        let redeemed = StoreRedemption(
            transactionID: 7, transaction: yearly, offer: .code, offerID: "SPRING", isRenewal: false, entitled: ["pro.yearly"]
        )
        #expect(redeemed == StoreRedemption(transactionID: 7, productID: "pro.yearly", offerID: "SPRING"))
        #expect(StoreRedemption(transactionID: 8, transaction: yearly, offer: .code, isRenewal: true, entitled: ["pro.yearly"]) == nil)
    }

    @Test("The same transaction sent again when access is taken back, refunded, revoked or moved up, is no redemption")
    func takenBack() {
        let refunded = StoreTransaction(productID: "pro.yearly", revocationDate: Date(timeIntervalSince1970: 1_800_000_000))
        let movedUp = StoreTransaction(productID: "pro.yearly", isUpgraded: true)
        for transaction in [refunded, movedUp] {
            #expect(StoreRedemption(transactionID: 7, transaction: transaction, offer: .code, isRenewal: false, entitled: ["pro.yearly"]) == nil)
        }
        // Access read after it came no longer has the plan.
        #expect(StoreRedemption(transactionID: 7, transaction: yearly, offer: .code, isRenewal: false, entitled: ["pro.lifetime"]) == nil)
    }

    @Test("A family member's shared plan was redeemed by someone else: no welcome for them")
    func familyShared() {
        let shared = StoreTransaction(productID: "pro.yearly", isFamilyShared: true)
        #expect(StoreRedemption(transactionID: 7, transaction: shared, offer: .code, isRenewal: false, entitled: ["pro.yearly"]) == nil)
    }

    @Test("Other offers, and none, redeem no code")
    func otherOffers() {
        for offer in [StoreOfferKind.introductory, .promotional, .winBack, .other] {
            #expect(StoreRedemption(transactionID: 7, transaction: yearly, offer: offer, isRenewal: false, entitled: ["pro.yearly"]) == nil)
        }
        #expect(StoreRedemption(transactionID: 7, transaction: yearly, offer: nil, isRenewal: false, entitled: ["pro.yearly"]) == nil)
    }

    @Test("A redemption waits across launches until welcomed; a newer one takes its place")
    func inbox() throws {
        let suite = "OfferCodeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = StoreRedemption(transactionID: 7, productID: "pro.yearly", offerID: "SPRING")
        let second = StoreRedemption(transactionID: 8, productID: "pro.monthly")
        #expect(StoreRedemptionInbox(defaults: defaults).waiting == nil)
        StoreRedemptionInbox(defaults: defaults).keep(first)
        // The next launch reads it back.
        #expect(StoreRedemptionInbox(defaults: defaults).waiting == first)
        let inbox = StoreRedemptionInbox(defaults: defaults)
        inbox.keep(second)
        // Welcoming the older one leaves the newer waiting.
        inbox.welcomed(first)
        #expect(inbox.waiting == second)
        inbox.welcomed(second)
        #expect(inbox.waiting == nil)
    }

    @Test("A waiting redemption whose product they no longer have is forgotten, never welcomed")
    func inboxForgets() throws {
        let suite = "OfferCodeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let inbox = StoreRedemptionInbox(defaults: defaults)
        let yearly = StoreRedemption(transactionID: 7, productID: "pro.yearly")
        #expect(inbox.waiting(entitled: ["pro.yearly"]) == nil)
        inbox.keep(yearly)
        #expect(inbox.waiting(entitled: ["pro.yearly", "pro.lifetime"]) == yearly)
        #expect(inbox.waiting == yearly)
        // Refunded: no longer theirs.
        #expect(inbox.waiting(entitled: ["pro.lifetime"]) == nil)
        #expect(inbox.waiting == nil)
    }

    @Test("The welcome names what the code unlocked, when it is one of the plans")
    func welcome() {
        let plans = PaywallCatalog.plans(from: proProducts, in: ["pro.yearly", "pro.monthly"], introOfferEligible: [], formatted: vnd)
        #expect(StoreCopy.redeemMessage(for: StoreRedemption(transactionID: 7, productID: "pro.yearly"), plans: plans)
            == StoreMessage("Đã áp dụng mã ưu đãi: Gói năm. Chào mừng bạn!", tone: .success))
        #expect(StoreCopy.redeemMessage(for: StoreRedemption(transactionID: 7, productID: "coins.100"), plans: plans)
            == StoreMessage("Đã áp dụng mã ưu đãi. Chào mừng bạn!", tone: .success))
        #expect(StoreCopy.offerCodeFailure("Không có mạng.") == StoreMessage("Chưa mở được trang nhập mã: Không có mạng.", tone: .failure))
    }
}
