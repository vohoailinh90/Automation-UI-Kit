import Foundation
@testable import IdeaLabCore
import Testing

private func subscription(
    _ id: String, _ price: Decimal, every period: StoreProduct.Period, trial: StoreProduct.IntroOffer? = nil, name: String? = nil
) -> StoreProduct {
    StoreProduct(
        id: id, displayName: name ?? id, displayPrice: VND.string(NSDecimalNumber(decimal: price).int64Value), price: price,
        kind: .autoRenewable(period: period, introOffer: trial)
    )
}

private func lifetime(_ id: String, _ price: Decimal, name: String? = nil) -> StoreProduct {
    StoreProduct(
        id: id, displayName: name ?? id, displayPrice: VND.string(NSDecimalNumber(decimal: price).int64Value), price: price,
        kind: .nonConsumable
    )
}

/// Đồng, rounded to whole đồng, as `Product.priceFormatStyle` writes them.
private func vnd(_ product: StoreProduct, _ amount: Decimal) -> String {
    var amount = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &amount, 0, .plain)
    return VND.string(NSDecimalNumber(decimal: rounded).int64Value)
}

private let weekTrial = StoreProduct.IntroOffer(payment: .freeTrial, period: .init(1, .week))

/// The demo's Pro plans: yearly with a week's trial, monthly, and for good.
private let proProducts = [
    lifetime("pro.lifetime", 599_000, name: "Mua một lần"),
    subscription("pro.monthly", 39_000, every: .init(1, .month), name: "Gói tháng"),
    subscription("pro.yearly", 299_000, every: .init(1, .year), trial: weekTrial, name: "Gói năm"),
]

@Suite("Paywall catalog: StoreKit products as a paywall's plans")
struct PaywallCatalogTests {
    @Test("Free trials: days, months or years, never a month counted as 30 days")
    func trials() {
        #expect(PaywallPlan.FreeTrial.days(7).text == "7 ngày")
        #expect(PaywallPlan.FreeTrial.months(1).text == "1 tháng")
        #expect(PaywallPlan.FreeTrial.years(1).text == "1 năm")
        #expect(PaywallPlan.FreeTrial.months(3).count == 3)
        let free = StoreProduct.IntroOffer.Payment.freeTrial
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(1, .week))) == .days(7))
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(2, .week))) == .days(14))
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(3, .day))) == .days(3))
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(1, .month))) == .months(1))
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(1, .month), periodCount: 2)) == .months(2))
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(1, .year))) == .years(1))
        // A paid offer is no free trial; nor is an empty one.
        #expect(PaywallCatalog.freeTrial(.init(payment: .payUpFront, period: .init(1, .month))) == nil)
        #expect(PaywallCatalog.freeTrial(.init(payment: .payAsYouGo, period: .init(1, .month), periodCount: 3)) == nil)
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(0, .week))) == nil)
        #expect(PaywallCatalog.freeTrial(.init(payment: free, period: .init(1, .week), periodCount: 0)) == nil)
    }

    @Test("Terms: a week (or seven days), a month, a year (or twelve months); nothing else", arguments: [
        (StoreProduct.Period(1, .week), PaywallPlan.Term?.some(.weekly)), (.init(7, .day), .weekly),
        (.init(1, .month), .monthly), (.init(1, .year), .yearly), (.init(12, .month), .yearly),
        (.init(1, .day), nil), (.init(2, .week), nil), (.init(3, .month), nil), (.init(6, .month), nil), (.init(2, .year), nil),
    ])
    func terms(period: StoreProduct.Period, expected: PaywallPlan.Term?) {
        #expect(PaywallCatalog.term(of: period) == expected)
    }

    @Test("The demo's plans: in the app's order, the yearly one with its trial, saving and price per month")
    func pro() {
        let plans = PaywallCatalog.plans(
            from: proProducts, in: ["pro.yearly", "pro.monthly", "pro.lifetime"], introOfferEligible: ["pro.yearly"], formatted: vnd
        )
        #expect(plans.map(\.id) == ["pro.yearly", "pro.monthly", "pro.lifetime"])
        #expect(plans.map(\.term) == [.yearly, .monthly, .lifetime])
        #expect(plans.map(\.title) == ["Gói năm", "Gói tháng", "Mua một lần"])
        #expect(plans.map(\.displayPrice) == [VND.string(299_000), VND.string(39_000), VND.string(599_000)])
        // 299.000 / 12 = 24.916,67 a month: 36% under 39.000, rounded down.
        #expect(plans[0].freeTrial == .days(7))
        #expect(plans[0].badge == "Tiết kiệm 36%")
        #expect(plans[0].detail == "≈ \(VND.string(24_917))/tháng")
        // The dearest per month has no saving to show, and says its price already.
        #expect(plans[1].badge == nil && plans[1].detail == nil && plans[1].freeTrial == nil)
        #expect(plans[2].badge == nil && plans[2].detail == nil && plans[2].freeTrial == nil)
    }

    @Test("No trial for a customer who is not eligible, whatever the product offers")
    func notEligible() {
        let plans = PaywallCatalog.plans(from: proProducts, in: ["pro.yearly"], introOfferEligible: [], formatted: vnd)
        #expect(plans.count == 1)
        #expect(plans[0].freeTrial == nil)
        // Eligible for a product without an offer: still no trial.
        let monthly = PaywallCatalog.plans(from: proProducts, in: ["pro.monthly"], introOfferEligible: ["pro.monthly"], formatted: vnd)
        #expect(monthly.first?.freeTrial == nil)
    }

    @Test("Left out: ids the App Store did not return, repeated ids, other kinds and other periods")
    func leftOut() {
        let products = proProducts + [
            StoreProduct(id: "coins", displayName: "Xu", displayPrice: "", price: 10_000, kind: .other),
            subscription("pro.quarterly", 99_000, every: .init(3, .month)),
        ]
        let plans = PaywallCatalog.plans(
            from: products, in: ["missing", "pro.monthly", "coins", "pro.quarterly", "pro.monthly", "pro.lifetime"],
            introOfferEligible: [], formatted: vnd
        )
        #expect(plans.map(\.id) == ["pro.monthly", "pro.lifetime"])
        #expect(PaywallCatalog.plans(from: [], in: ["pro.yearly"], introOfferEligible: [], formatted: vnd).isEmpty)
        #expect(PaywallCatalog.plans(from: proProducts, in: [], introOfferEligible: [], formatted: vnd).isEmpty)
    }

    @Test("A weekly plan is the dearest per month: the others save against it, and it says its price per month")
    func weekly() {
        let products = [
            subscription("weekly", 29_000, every: .init(1, .week)),
            subscription("yearly", 299_000, every: .init(1, .year)),
        ]
        var asked: [String] = []
        let plans = PaywallCatalog.plans(from: products, in: ["weekly", "yearly"], introOfferEligible: []) { product, amount in
            asked.append(product.id)
            return vnd(product, amount)
        }
        // 29.000 a week is 125.666,67 a month (52 weeks a year).
        #expect(plans[0].badge == nil)
        #expect(plans[0].detail == "≈ \(VND.string(125_667))/tháng")
        #expect(plans[1].badge == "Tiết kiệm 80%")
        #expect(plans[1].detail == "≈ \(VND.string(24_917))/tháng")
        #expect(asked == ["weekly", "yearly"])
    }

    @Test("Bought for good alone: one plan, nothing to compare")
    func lifetimeOnly() {
        let plans = PaywallCatalog.plans(
            from: [lifetime("cleaner.lifetime", 99_000)], in: ["cleaner.lifetime"], introOfferEligible: ["cleaner.lifetime"], formatted: vnd
        )
        #expect(plans.map(\.term) == [.lifetime])
        #expect(plans[0].badge == nil && plans[0].detail == nil && plans[0].freeTrial == nil)
    }

    @Test("Entitlements: refunded, revoked and moved-up transactions give nothing")
    func entitlements() {
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let transactions = [
            StoreTransaction(productID: "pro.lifetime"),
            StoreTransaction(productID: "pro.monthly", isUpgraded: true),
            StoreTransaction(productID: "pro.yearly"),
            StoreTransaction(productID: "cleaner.lifetime", revocationDate: when),
            StoreTransaction(productID: "pro.lifetime"),
        ]
        #expect(StoreEntitlements.productIDs(from: transactions) == ["pro.lifetime", "pro.yearly"])
        #expect(StoreEntitlements.productIDs(from: []).isEmpty)
    }

    @Test("Purchase messages: what was bought by name; nothing when cancelled")
    func purchaseMessages() {
        let plans = PaywallCatalog.plans(from: proProducts, in: ["pro.yearly", "pro.monthly"], introOfferEligible: [], formatted: vnd)
        #expect(StoreCopy.purchaseMessage(for: .purchased(productID: "pro.yearly"), plans: plans) == StoreMessage("Đã mua Gói năm. Cảm ơn bạn!", tone: .success))
        #expect(StoreCopy.purchaseMessage(for: .purchased(productID: "other"), plans: plans) == StoreMessage("Đã mua. Cảm ơn bạn!", tone: .success))
        #expect(StoreCopy.purchaseMessage(for: .pending, plans: plans)?.tone == .notice)
        #expect(StoreCopy.purchaseMessage(for: .cancelled, plans: plans) == nil)
        #expect(StoreCopy.purchaseMessage(for: .unverified, plans: plans)?.tone == .failure)
        #expect(StoreCopy.purchaseMessage(for: .unavailable, plans: plans)?.tone == .failure)
        #expect(StoreCopy.purchaseMessage(for: .failed("Mất kết nối."), plans: plans) == StoreMessage("Chưa mua được: Mất kết nối.", tone: .failure))
    }

    @Test("Restore messages: what came back, in the paywall's order")
    func restoreMessages() {
        let plans = PaywallCatalog.plans(from: proProducts, in: ["pro.yearly", "pro.monthly", "pro.lifetime"], introOfferEligible: [], formatted: vnd)
        #expect(StoreCopy.restoreMessage(for: .restored(["pro.lifetime", "pro.yearly"]), plans: plans)
            == StoreMessage("Đã khôi phục: Gói năm, Mua một lần.", tone: .success))
        #expect(StoreCopy.restoreMessage(for: .restored(["cleaner.lifetime"]), plans: plans) == StoreMessage("Đã khôi phục mua hàng.", tone: .success))
        #expect(StoreCopy.restoreMessage(for: .nothingToRestore, plans: plans)?.tone == .notice)
        #expect(StoreCopy.restoreMessage(for: .cancelled, plans: plans) == nil)
        #expect(StoreCopy.restoreMessage(for: .failed("Lỗi."), plans: plans) == StoreMessage("Chưa khôi phục được: Lỗi.", tone: .failure))
    }
}
