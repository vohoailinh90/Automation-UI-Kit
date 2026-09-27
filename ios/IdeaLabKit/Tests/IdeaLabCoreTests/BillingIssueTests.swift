import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// When the paid period ended, and the App Store could not charge for the next.
private let periodEnded = vietnam.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 9, minute: 41))!
/// When the grace period ends: "11/10/2026".
private let graceEnds = vietnam.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9, minute: 41))!

private let order = ["pro.yearly", "pro.monthly", "pro.lifetime"]
private let monthlyPrice = VND.string(39_000) + "/tháng"
/// The monthly plan, as the plan a yearly subscription was to renew as.
private let monthlyNext = PaywallPlan.NextPlan(title: "Gói tháng", displayPrice: VND.string(39_000), term: .monthly)

/// A subscription of the group "pro" whose renewal the App Store could not charge for.
private func failing(
    _ productID: String, _ issue: StoreSubscription.BillingIssue, renewsAs: String? = nil, group: String = "pro", familyShared: Bool = false
) -> StoreSubscription {
    StoreSubscription(
        groupID: group, productID: productID, renewsAs: renewsAs ?? productID, periodEnds: periodEnded,
        isFamilyShared: familyShared, billingIssue: issue
    )
}

/// A customer with `subscriptions`, which give access in their grace period,
/// not on hold, and what they bought.
private func customer(_ subscriptions: [StoreSubscription], owned: Set<String> = [], sharedByFamily: Set<String> = []) -> StoreCustomer {
    let giving = subscriptions.filter { $0.billingIssue != .retrying }.map(\.productID)
    return StoreCustomer(owned: owned.union(giving), sharedByFamily: sharedByFamily, subscriptions: subscriptions)
}

private func plans(for customer: StoreCustomer) -> [PaywallPlan] {
    PaywallCatalog.plans(from: proProducts, in: order, introOfferEligible: [], customer: customer, formatted: vnd)
}

private func standing(_ id: String, in plans: [PaywallPlan]) -> PaywallPlan.Standing? {
    plans.first { $0.id == id }?.standing
}

@Suite("Billing issues: a renewal the App Store could not charge for")
struct BillingIssueTests {
    @Test("In the grace period: theirs says so, and the others promise no date and no refund")
    func gracePeriod() {
        let offered = plans(for: customer([failing("pro.monthly", .gracePeriod(until: graceEnds))]))
        #expect(offered.map(\.id) == order)
        #expect(standing("pro.monthly", in: offered) == .current(.billingIssue(.gracePeriod(until: graceEnds)), ownedForGood: false))
        // Its period is over: an upgrade would refund nothing of it.
        #expect(standing("pro.yearly", in: offered) == .change(replacing: "Gói tháng"))
        // The App Store keeps trying to charge for it.
        #expect(standing("pro.lifetime", in: offered) == .alongside(subscription: "Gói tháng"))
        #expect(PaywallCopy.hasSubscription(among: offered))
    }

    @Test("On hold: theirs says so; a downgrade chosen before starts when the App Store can charge")
    func retrying() {
        let monthly = plans(for: customer([failing("pro.monthly", .retrying)]))
        #expect(standing("pro.monthly", in: monthly) == .current(.billingIssue(.retrying), ownedForGood: false))
        #expect(standing("pro.yearly", in: monthly) == .change(replacing: "Gói tháng"))
        let yearly = plans(for: customer([failing("pro.yearly", .retrying, renewsAs: "pro.monthly")]))
        #expect(standing("pro.yearly", in: yearly) == .current(.billingIssue(.retrying, renewingAs: monthlyNext), ownedForGood: false))
        #expect(standing("pro.monthly", in: yearly) == .scheduled(from: nil))
    }

    @Test("A renewal as the plan they chose failed: that plan and its price, not theirs, are what the App Store charges")
    func chosenPlanFails() {
        let grace = plans(for: customer([failing("pro.yearly", .gracePeriod(until: graceEnds), renewsAs: "pro.monthly")]))[0]
        #expect(grace.standing == .current(.billingIssue(.gracePeriod(until: graceEnds), renewingAs: monthlyNext), ownedForGood: false))
        #expect(PaywallCopy.priceLine(for: grace, calendar: vietnam) == "Chưa gia hạn được \(monthlyPrice); vẫn dùng đến 11/10/2026")
        // The card's price is what is charged, and its line says why.
        #expect(PaywallCopy.cardPrice(for: grace) == monthlyPrice)
        #expect(PaywallCopy.detail(for: grace, calendar: vietnam) == "Gia hạn thành Gói tháng; vẫn dùng đến 11/10/2026")
        #expect(PaywallCopy.terms(for: grace, calendar: vietnam)
            == "App Store chưa thu được tiền gia hạn Gói năm thành Gói tháng (\(monthlyPrice)). Bạn vẫn dùng được đến hết ngày 11/10/2026: "
            + "cập nhật phương thức thanh toán trước ngày đó để không bị gián đoạn.")
        let onHold = plans(for: customer([failing("pro.yearly", .retrying, renewsAs: "pro.monthly")]))[0]
        #expect(PaywallCopy.priceLine(for: onHold, calendar: vietnam) == "Tạm dừng: chưa thanh toán được \(monthlyPrice)")
        #expect(PaywallCopy.cardPrice(for: onHold) == monthlyPrice)
        #expect(PaywallCopy.detail(for: onHold, calendar: vietnam) == "Gia hạn thành Gói tháng; chưa thanh toán được")
        // Chosen but not loaded: named, and no price made up.
        let unknown = plans(for: customer([failing("pro.yearly", .gracePeriod(until: graceEnds), renewsAs: "pro.quarterly")]))[0]
        #expect(unknown.standing
            == .current(.billingIssue(.gracePeriod(until: graceEnds), renewingAs: .init(title: "gói đã chọn cho kỳ sau")), ownedForGood: false))
        #expect(PaywallCopy.priceLine(for: unknown, calendar: vietnam) == "Chưa gia hạn được; vẫn dùng đến 11/10/2026")
        #expect(PaywallCopy.cardPrice(for: unknown) == nil)
        #expect(PaywallCopy.terms(for: unknown, calendar: vietnam)
            == "App Store chưa thu được tiền gia hạn Gói năm thành gói đã chọn cho kỳ sau. Bạn vẫn dùng được đến hết ngày 11/10/2026: "
            + "cập nhật phương thức thanh toán trước ngày đó để không bị gián đoạn.")
    }

    @Test("Bought for good as well: theirs stays, to say it is no longer needed")
    func ownedForGood() {
        let offered = plans(for: customer([failing("pro.monthly", .retrying)], owned: ["pro.lifetime"]))
        #expect(offered.map(\.id) == ["pro.monthly", "pro.lifetime"])
        #expect(offered[0].standing == .current(.billingIssue(.retrying), ownedForGood: true))
        #expect(offered[1].standing == .owned(renewing: "Gói tháng"))
    }

    @Test("Shared by the family: the family member pays, so nothing is said to them")
    func familyShared() {
        let shared = customer([failing("pro.yearly", .gracePeriod(until: graceEnds), familyShared: true)])
        let offered = plans(for: shared)
        #expect(standing("pro.yearly", in: offered) == .sharedByFamily)
        #expect(!offered.contains(where: PaywallCopy.hasBillingIssue))
        #expect(StoreCopy.billingNotice(for: shared, plans: offered, calendar: vietnam) == nil)
    }

    @Test("Their plan in the grace period: until when it works, and the button updates the payment method")
    func graceCopy() {
        let plan = plans(for: customer([failing("pro.monthly", .gracePeriod(until: graceEnds))]))[1]
        #expect(PaywallCopy.priceLine(for: plan, calendar: vietnam) == "Chưa gia hạn được \(monthlyPrice); vẫn dùng đến 11/10/2026")
        #expect(PaywallCopy.terms(for: plan, calendar: vietnam)
            == "App Store chưa thu được tiền gia hạn Gói tháng (\(monthlyPrice)). Bạn vẫn dùng được đến hết ngày 11/10/2026: "
            + "cập nhật phương thức thanh toán trước ngày đó để không bị gián đoạn.")
        #expect(PaywallCopy.callToAction(for: plan, calendar: vietnam) == "Cập nhật thanh toán")
        #expect(PaywallCopy.action(for: plan) == .updatePayment)
        #expect(PaywallCopy.standingBadge(for: plan, calendar: vietnam) == "Chưa gia hạn được")
        #expect(PaywallCopy.detail(for: plan, calendar: vietnam) == "Vẫn dùng đến 11/10/2026")
        #expect(PaywallCopy.hasBillingIssue(plan))
        // No date from the App Store: no date made up.
        let undated = plans(for: customer([failing("pro.monthly", .gracePeriod(until: nil))]))[1]
        #expect(PaywallCopy.priceLine(for: undated, calendar: vietnam) == "Chưa gia hạn được \(monthlyPrice); App Store đang thử lại")
        #expect(PaywallCopy.terms(for: undated, calendar: vietnam)
            == "App Store chưa thu được tiền gia hạn Gói tháng (\(monthlyPrice)) và đang thử lại. "
            + "Cập nhật phương thức thanh toán để không bị gián đoạn.")
        #expect(PaywallCopy.detail(for: undated, calendar: vietnam) == "App Store đang thử lại")
    }

    @Test("Their plan on hold: paused until paid for, or cancelled")
    func retryingCopy() {
        let plan = plans(for: customer([failing("pro.monthly", .retrying)]))[1]
        #expect(PaywallCopy.priceLine(for: plan, calendar: vietnam) == "Tạm dừng: chưa thanh toán được \(monthlyPrice)")
        #expect(PaywallCopy.terms(for: plan, calendar: vietnam)
            == "App Store chưa thu được tiền gia hạn Gói tháng (\(monthlyPrice)), nên gói đang tạm dừng. "
            + "Cập nhật phương thức thanh toán: App Store sẽ thử lại, và gói dùng tiếp ngay khi thu được. "
            + "Không dùng nữa thì huỷ trong Quản lý gói đăng ký.")
        #expect(PaywallCopy.callToAction(for: plan, calendar: vietnam) == "Cập nhật thanh toán")
        #expect(PaywallCopy.action(for: plan) == .updatePayment)
        #expect(PaywallCopy.standingBadge(for: plan, calendar: vietnam) == "Tạm dừng")
        #expect(PaywallCopy.detail(for: plan, calendar: vietnam) == "Chưa thanh toán được")
    }

    @Test("Bought for good as well: cancel it rather than pay for it")
    func ownedForGoodCopy() {
        let plan = plans(for: customer([failing("pro.monthly", .gracePeriod(until: graceEnds))], owned: ["pro.lifetime"]))[0]
        #expect(PaywallCopy.terms(for: plan, calendar: vietnam)
            == "App Store chưa thu được tiền gia hạn Gói tháng (\(monthlyPrice)). Bạn đã mua gói dùng mãi mãi nên không cần gói này: "
            + "huỷ nó trong Quản lý gói đăng ký để App Store thôi thu tiền.")
        #expect(PaywallCopy.callToAction(for: plan, calendar: vietnam) == "Quản lý gói đăng ký")
        #expect(PaywallCopy.action(for: plan) == .manageSubscriptions)
        #expect(PaywallCopy.hasBillingIssue(plan))
    }

    @Test("The card's price: the plan's own, also while theirs fails to renew as itself")
    func cardPrice() {
        #expect(PaywallCopy.cardPrice(for: plans(for: StoreCustomer())[1]) == monthlyPrice)
        let failing = plans(for: customer([failing("pro.monthly", .retrying)]))[1]
        #expect(PaywallCopy.cardPrice(for: failing) == monthlyPrice)
        #expect(PaywallCopy.cardPrice(for: plans(for: StoreCustomer())[2]) == VND.string(599_000))
    }

    @Test("Renewing as it should: no billing issue")
    func noIssue() {
        let renewing = StoreSubscription(groupID: "pro", productID: "pro.monthly", renewsAs: "pro.monthly", periodEnds: graceEnds)
        let offered = plans(for: customer([renewing]))
        #expect(!offered.contains(where: PaywallCopy.hasBillingIssue))
        #expect(PaywallCopy.action(for: offered[1]) == .manageSubscriptions)
        #expect(StoreCopy.billingNotice(for: customer([renewing]), plans: offered, calendar: vietnam) == nil)
        #expect(StoreCopy.billingNotice(for: StoreCustomer(), plans: plans(for: StoreCustomer()), calendar: vietnam) == nil)
    }

    @Test("The notice outside the paywall, in the grace period and on hold")
    func notice() {
        let grace = customer([failing("pro.monthly", .gracePeriod(until: graceEnds))])
        #expect(StoreCopy.billingNotice(for: grace, plans: plans(for: grace), calendar: vietnam) == BillingNotice(
            productID: "pro.monthly", issue: .gracePeriod(until: graceEnds), title: "Chưa gia hạn được Gói tháng",
            message: "App Store chưa thu được tiền. Bạn vẫn dùng được đến hết ngày 11/10/2026: "
                + "cập nhật phương thức thanh toán trước ngày đó để không bị gián đoạn.",
            action: .updatePayment, actionTitle: "Cập nhật thanh toán"
        ))
        let undated = customer([failing("pro.monthly", .gracePeriod(until: nil))])
        #expect(StoreCopy.billingNotice(for: undated, plans: plans(for: undated), calendar: vietnam)?.message
            == "App Store chưa thu được tiền và đang thử lại. Cập nhật phương thức thanh toán để không bị gián đoạn.")
        let onHold = customer([failing("pro.monthly", .retrying)])
        #expect(StoreCopy.billingNotice(for: onHold, plans: plans(for: onHold), calendar: vietnam) == BillingNotice(
            productID: "pro.monthly", issue: .retrying, title: "Gói tháng đang tạm dừng",
            message: "App Store chưa thu được tiền gia hạn. Cập nhật phương thức thanh toán: App Store sẽ thử lại, "
                + "và gói dùng tiếp ngay khi thu được.",
            action: .updatePayment, actionTitle: "Cập nhật thanh toán"
        ))
    }

    @Test("The notice: on hold first, then the grace that ends first; named even when not on offer")
    func noticeOrder() {
        let later = vietnam.date(byAdding: .day, value: 10, to: graceEnds)!
        let both = customer([
            failing("photos.monthly", .gracePeriod(until: graceEnds), group: "photos"),
            failing("pro.monthly", .retrying),
        ])
        #expect(StoreCopy.billingNotice(for: both, plans: plans(for: both), calendar: vietnam)?.productID == "pro.monthly")
        let graces = customer([
            failing("pro.monthly", .gracePeriod(until: later)),
            failing("photos.monthly", .gracePeriod(until: graceEnds), group: "photos"),
        ])
        let first = StoreCopy.billingNotice(for: graces, plans: plans(for: graces), calendar: vietnam)
        #expect(first?.productID == "photos.monthly")
        // Not among the paywall's plans: named all the same.
        #expect(first?.title == "Chưa gia hạn được gói đăng ký")
        let legacy = customer([failing("pro.legacy", .retrying)])
        #expect(StoreCopy.billingNotice(for: legacy, plans: plans(for: legacy), calendar: vietnam)?.title == "Gói đăng ký đang tạm dừng")
    }

    @Test("The notice to someone who bought for good: cancel; bought through the family: pay")
    func noticeOwnedForGood() {
        let owner = customer([failing("pro.monthly", .retrying)], owned: ["pro.lifetime"])
        let notice = StoreCopy.billingNotice(for: owner, plans: plans(for: owner), calendar: vietnam)
        #expect(notice?.action == .manageSubscriptions)
        #expect(notice?.actionTitle == "Quản lý gói đăng ký")
        #expect(notice?.message == "App Store chưa thu được tiền gia hạn Gói tháng. Bạn đã mua gói dùng mãi mãi nên không cần gói này: "
            + "huỷ nó trong Quản lý gói đăng ký để App Store thôi thu tiền.")
        // Shared by the family, which can stop sharing it: theirs is still needed.
        let shared = customer([failing("pro.monthly", .retrying)], owned: ["pro.lifetime"], sharedByFamily: ["pro.lifetime"])
        #expect(StoreCopy.billingNotice(for: shared, plans: plans(for: shared), calendar: vietnam)?.action == .updatePayment)
    }

    @Test("Apple's page for the payment methods")
    func billingLink() {
        #expect(StoreLinks.billing.absoluteString == "https://apps.apple.com/account/billing")
    }
}
