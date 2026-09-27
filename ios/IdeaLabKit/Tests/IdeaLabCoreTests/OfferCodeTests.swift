@testable import IdeaLabCore
import Testing

@Suite("Offer codes: the redemption a transaction tells, and the welcome")
struct OfferCodeTests {
    @Test("A purchase with an offer code is a redemption; a renewal at the code's price is not")
    func redemption() {
        let redeemed = StoreRedemption(transactionID: 7, productID: "pro.yearly", offer: .code, offerID: "SPRING", isRenewal: false)
        #expect(redeemed == StoreRedemption(transactionID: 7, productID: "pro.yearly", offerID: "SPRING"))
        #expect(StoreRedemption(transactionID: 8, productID: "pro.yearly", offer: .code, isRenewal: true) == nil)
    }

    @Test("Other offers, and none, redeem no code")
    func otherOffers() {
        for offer in [StoreOfferKind.introductory, .promotional, .winBack, .other] {
            #expect(StoreRedemption(transactionID: 7, productID: "pro.monthly", offer: offer, isRenewal: false) == nil)
        }
        #expect(StoreRedemption(transactionID: 7, productID: "pro.monthly", offer: nil, isRenewal: false) == nil)
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
