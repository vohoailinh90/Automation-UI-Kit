import Foundation
@testable import IdeaLabCore
import Testing

private let order = ["pro.yearly", "pro.monthly", "pro.lifetime"]
private let monthlyPrice = VND.string(39_000) + "/tháng"

/// Three months at 19.000 ₫ a month.
private let threeMonths = StoreProduct.Offer(
    id: "back.3months", payment: .payAsYouGo, displayPrice: VND.string(19_000), period: .init(1, .month), periodCount: 3
)
/// A first month for nothing.
private let freeMonth = StoreProduct.Offer(id: "back.free", payment: .freeTrial, displayPrice: VND.string(0), period: .init(1, .month))
/// Six months paid at once.
private let halfYear = StoreProduct.Offer(
    id: "back.halfyear", payment: .payUpFront, displayPrice: VND.string(99_000), period: .init(6, .month)
)

/// The Pro products, the monthly plan with win-back offers.
private func products(monthly offers: [StoreProduct.Offer] = [threeMonths, freeMonth]) -> [StoreProduct] {
    proProducts.map { product in
        var product = product
        if product.id == "pro.monthly" {
            product.winBackOffers = offers
        }
        return product
    }
}

private func plans(for customer: StoreCustomer, from products: [StoreProduct] = products()) -> [PaywallPlan] {
    PaywallCatalog.plans(from: products, in: order, introOfferEligible: [], customer: customer, formatted: vnd)
}

private func plan(_ id: String, in plans: [PaywallPlan]) -> PaywallPlan? {
    plans.first { $0.id == id }
}

/// Someone whose Pro subscription is over, and whom the App Store offers `ids`.
private func lapsed(_ ids: [String], group: String = "pro") -> StoreCustomer {
    StoreCustomer(winBackOffers: [group: ids])
}

@Suite("Win-back offers: a subscription that is over, and the App Store's offer to come back")
struct WinBackTests {
    @Test("The best offer the App Store lists that is the plan's own; none on the others")
    func bestOfTheirs() {
        let offered = plans(for: lapsed(["back.free", "back.3months"]))
        #expect(plan("pro.monthly", in: offered)?.winBackOffer == freeMonth)
        #expect(plan("pro.yearly", in: offered)?.winBackOffer == nil)
        #expect(plan("pro.lifetime", in: offered)?.winBackOffer == nil)
        // The App Store's order, not the product's.
        #expect(plan("pro.monthly", in: plans(for: lapsed(["back.3months", "back.free"])))?.winBackOffer == threeMonths)
        // An offer of another plan, or one no longer set: skipped for the next.
        #expect(plan("pro.monthly", in: plans(for: lapsed(["back.gone", "back.3months"])))?.winBackOffer == threeMonths)
        #expect(plan("pro.monthly", in: plans(for: lapsed(["back.gone"])))?.winBackOffer == nil)
    }

    @Test("Only for a group whose subscription is over: not theirs now, shared, in grace or on hold")
    func onlyOnceOver() {
        let renewing = StoreSubscription(groupID: "pro", productID: "pro.yearly", renewsAs: "pro.yearly", periodEnds: nil)
        var shared = renewing
        shared.isFamilyShared = true
        var grace = renewing
        grace.billingIssue = .gracePeriod(until: nil)
        var onHold = renewing
        onHold.billingIssue = .retrying
        for subscription in [renewing, shared, grace, onHold] {
            let customer = StoreCustomer(subscriptions: [subscription], winBackOffers: ["pro": ["back.3months"]])
            #expect(plans(for: customer).allSatisfy { $0.winBackOffer == nil })
        }
        // Another group's offers, or a subscription of another group, change nothing here.
        #expect(plans(for: lapsed(["back.3months"], group: "photos")).allSatisfy { $0.winBackOffer == nil })
        let photos = StoreSubscription(groupID: "photos", productID: "photos.monthly", renewsAs: "photos.monthly", periodEnds: nil)
        let elsewhere = StoreCustomer(subscriptions: [photos], winBackOffers: ["pro": ["back.3months"]])
        #expect(plan("pro.monthly", in: plans(for: elsewhere))?.winBackOffer == threeMonths)
        // Bought for good: no subscription is offered at all.
        let owner = StoreCustomer(owned: ["pro.lifetime"], winBackOffers: ["pro": ["back.3months"]])
        #expect(plans(for: owner).allSatisfy { $0.winBackOffer == nil })
    }

    @Test("What makes a status's offers theirs: their own subscription, expired and not renewing")
    func fromStatus() {
        let ids = ["back.3months"]
        #expect(StoreCustomer.winBackOfferIDs(state: .expired, willAutoRenew: false, isFamilyShared: false, eligible: ids) == ids)
        #expect(StoreCustomer.winBackOfferIDs(state: .expired, willAutoRenew: true, isFamilyShared: false, eligible: ids).isEmpty)
        #expect(StoreCustomer.winBackOfferIDs(state: .expired, willAutoRenew: false, isFamilyShared: true, eligible: ids).isEmpty)
        for state in [StoreSubscription.State.subscribed, .inGracePeriod, .inBillingRetryPeriod, .revoked] {
            #expect(StoreCustomer.winBackOfferIDs(state: state, willAutoRenew: false, isFamilyShared: false, eligible: ids).isEmpty)
        }
    }

    @Test("Paid month by month: the card, the line by the button, the button and the terms")
    func payAsYouGo() {
        let monthly = plan("pro.monthly", in: plans(for: lapsed(["back.3months"])))!
        #expect(PaywallCopy.offerBadge(for: monthly) == "Ưu đãi quay lại")
        #expect(PaywallCopy.detail(for: monthly) == "\(VND.string(19_000))/tháng trong 3 tháng đầu")
        #expect(PaywallCopy.cardPrice(for: monthly) == monthlyPrice)
        #expect(PaywallCopy.priceLine(for: monthly) == "\(VND.string(19_000))/tháng trong 3 tháng đầu, sau đó \(monthlyPrice)")
        #expect(PaywallCopy.callToAction(for: monthly) == "Đăng ký lại · \(VND.string(19_000))/tháng")
        #expect(PaywallCopy.terms(for: monthly)
            == "Ưu đãi quay lại: \(VND.string(19_000))/tháng trong 3 tháng đầu, sau đó \(monthlyPrice), tự động gia hạn. "
            + "Huỷ bất cứ lúc nào trong Cài đặt.")
        #expect(PaywallCopy.action(for: monthly) == .purchase)
        // The yearly plan, with no offer, reads as before.
        let yearly = plan("pro.yearly", in: plans(for: lapsed(["back.3months"])))!
        #expect(PaywallCopy.offerBadge(for: yearly) == nil)
        #expect(PaywallCopy.callToAction(for: yearly) == "Đăng ký · \(VND.string(299_000))/năm")
    }

    @Test("Free for a while, or paid up front")
    func freeOrUpFront() {
        let free = plan("pro.monthly", in: plans(for: lapsed(["back.free"])))!
        #expect(PaywallCopy.detail(for: free) == "Miễn phí 1 tháng đầu")
        #expect(PaywallCopy.priceLine(for: free) == "Miễn phí 1 tháng đầu, sau đó \(monthlyPrice)")
        #expect(PaywallCopy.callToAction(for: free) == "Đăng ký lại · miễn phí 1 tháng")
        #expect(PaywallCopy.terms(for: free).hasPrefix("Ưu đãi quay lại: miễn phí 1 tháng đầu, sau đó \(monthlyPrice), "))
        let upFront = plan("pro.monthly", in: plans(for: lapsed(["back.halfyear"]), from: products(monthly: [halfYear])))!
        #expect(PaywallCopy.priceLine(for: upFront) == "\(VND.string(99_000)) cho 6 tháng đầu, sau đó \(monthlyPrice)")
        #expect(PaywallCopy.callToAction(for: upFront) == "Đăng ký lại · \(VND.string(99_000))")
    }

    @Test("How long an offer lasts, in its own unit")
    func durations() {
        #expect(PaywallCopy.duration(.init(1, .month), times: 3) == "3 tháng")
        #expect(PaywallCopy.duration(.init(1, .week), times: 4) == "4 tuần")
        #expect(PaywallCopy.duration(.init(3, .month), times: 2) == "6 tháng")
        #expect(PaywallCopy.duration(.init(14, .day), times: 1) == "14 ngày")
        #expect(PaywallCopy.duration(.init(1, .year), times: 1) == "1 năm")
        let quarterly = StoreProduct.Offer(
            id: "q", payment: .payAsYouGo, displayPrice: VND.string(49_000), period: .init(3, .month), periodCount: 2
        )
        #expect(PaywallCopy.offerSummary(quarterly) == "\(VND.string(49_000))/3 tháng trong 6 tháng đầu")
    }
}
