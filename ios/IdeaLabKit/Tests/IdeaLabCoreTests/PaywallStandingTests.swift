import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// When the customer's paid period ends in these tests: "13/10/2026".
private let renewal = vietnam.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 41))!

private let order = ["pro.yearly", "pro.monthly", "pro.lifetime"]

/// A customer on `productID`, of the group "pro", renewing as `renewsAs`.
private func subscriber(
    _ productID: String, renewsAs: String?, group: String = "pro", owned: Set<String> = [], familyShared: Bool = false
) -> StoreCustomer {
    StoreCustomer(
        owned: owned.union([productID]),
        subscriptions: [StoreSubscription(
            groupID: group, productID: productID, renewsAs: renewsAs, periodEnds: renewal, isFamilyShared: familyShared
        )]
    )
}

private func plans(for customer: StoreCustomer, from products: [StoreProduct] = proProducts, in ids: [String] = order) -> [PaywallPlan] {
    PaywallCatalog.plans(from: products, in: ids, introOfferEligible: [], customer: customer, formatted: vnd)
}

private func standing(_ id: String, in plans: [PaywallPlan]) -> PaywallPlan.Standing? {
    plans.first { $0.id == id }?.standing
}

@Suite("Paywall standings: each plan against what the customer has")
struct PaywallStandingTests {
    @Test("A new customer: no plan stands anywhere, and all are offered")
    func newCustomer() {
        let offered = plans(for: StoreCustomer())
        #expect(offered.map(\.id) == order)
        #expect(offered.allSatisfy { $0.standing == nil })
    }

    @Test("On the monthly plan: theirs renews, the yearly one is an upgrade, and buying for good leaves monthly renewing")
    func monthly() {
        let offered = plans(for: subscriber("pro.monthly", renewsAs: "pro.monthly"))
        #expect(offered.map(\.id) == order)
        #expect(standing("pro.monthly", in: offered) == .current(.renews(on: renewal), ownedForGood: false))
        #expect(standing("pro.yearly", in: offered) == .upgrade(replacing: "Gói tháng"))
        #expect(standing("pro.lifetime", in: offered) == .alongside(subscription: "Gói tháng"))
        // The saving still shows on the plan they could move to.
        #expect(offered.first?.badge == "Tiết kiệm 36%")
    }

    @Test("On the yearly plan: the monthly one would start when the year ends")
    func yearly() {
        let offered = plans(for: subscriber("pro.yearly", renewsAs: "pro.yearly"))
        #expect(standing("pro.yearly", in: offered) == .current(.renews(on: renewal), ownedForGood: false))
        #expect(standing("pro.monthly", in: offered) == .nextPeriod(replacing: "Gói năm", from: renewal))
        #expect(standing("pro.lifetime", in: offered) == .alongside(subscription: "Gói năm"))
    }

    @Test("Monthly already chosen for the next period: the year switches to it, and it is scheduled")
    func scheduled() {
        let offered = plans(for: subscriber("pro.yearly", renewsAs: "pro.monthly"))
        #expect(standing("pro.yearly", in: offered) == .current(.switches(to: "Gói tháng", on: renewal), ownedForGood: false))
        #expect(standing("pro.monthly", in: offered) == .scheduled(from: renewal))
    }

    @Test("Renewal turned off: the plan ends, and buying for good needs no warning")
    func ends() {
        let offered = plans(for: subscriber("pro.monthly", renewsAs: nil))
        #expect(standing("pro.monthly", in: offered) == .current(.ends(on: renewal), ownedForGood: false))
        #expect(standing("pro.yearly", in: offered) == .upgrade(replacing: "Gói tháng"))
        #expect(standing("pro.lifetime", in: offered) == nil)
    }

    @Test("Bought for good: no subscription is offered any more")
    func ownedForGood() {
        let offered = plans(for: StoreCustomer(owned: ["pro.lifetime"]))
        #expect(offered.map(\.id) == ["pro.lifetime"])
        #expect(offered.first?.standing == .owned(renewing: nil))
    }

    @Test("Bought for good: another plan kept for good is not offered either")
    func ownedForGoodAmongOthers() {
        let products = proProducts + [lifetime("pro.family", 899_000, name: "Mua một lần cho cả nhà")]
        let offered = plans(for: StoreCustomer(owned: ["pro.lifetime"]), from: products, in: order + ["pro.family"])
        #expect(offered.map(\.id) == ["pro.lifetime"])
    }

    @Test("Shared by the family: that plan is theirs to use, and nothing else changes against it")
    func familyShared() {
        let offered = plans(for: subscriber("pro.yearly", renewsAs: "pro.yearly", familyShared: true))
        #expect(offered.map(\.id) == order)
        #expect(standing("pro.yearly", in: offered) == .sharedByFamily)
        // Buying their own is a purchase like anyone's, and they pay for no
        // subscription that would keep renewing.
        #expect(standing("pro.monthly", in: offered) == nil)
        #expect(standing("pro.lifetime", in: offered) == nil)
    }

    @Test("Kept for good through Family Sharing: shared, not bought, and the other plans stay on offer")
    func lifetimeSharedByFamily() {
        let offered = plans(for: StoreCustomer(owned: ["pro.lifetime"], sharedByFamily: ["pro.lifetime"]))
        #expect(offered.map(\.id) == order)
        #expect(standing("pro.lifetime", in: offered) == .sharedByFamily)
        #expect(standing("pro.yearly", in: offered) == nil)
        #expect(standing("pro.monthly", in: offered) == nil)
    }

    @Test("Entitlements through Family Sharing: only what they did not also buy")
    func familySharedEntitlements() {
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let transactions = [
            StoreTransaction(productID: "pro.lifetime", isFamilyShared: true),
            StoreTransaction(productID: "pro.yearly", isFamilyShared: true),
            StoreTransaction(productID: "pro.yearly"),
            StoreTransaction(productID: "cleaner.lifetime", revocationDate: when, isFamilyShared: true),
        ]
        #expect(StoreEntitlements.productIDs(from: transactions) == ["pro.lifetime", "pro.yearly"])
        #expect(StoreEntitlements.familyShared(from: transactions) == ["pro.lifetime"])
    }

    @Test("Their plan not on offer: the others still tell they pay for one, for the link to manage it")
    func subscriptionNotOnOffer() {
        // Not loaded: the others are changes of unknown timing.
        #expect(PaywallCopy.hasSubscription(among: plans(for: subscriber("pro.legacy", renewsAs: "pro.legacy"))))
        // Loaded but not offered here: the others are an upgrade and a later switch.
        let legacy = subscription("pro.quarterly", 99_000, every: .init(3, .month), name: "Gói quý", level: 2)
        let offered = plans(for: subscriber("pro.quarterly", renewsAs: "pro.quarterly"), from: proProducts + [legacy])
        #expect(!offered.contains { $0.id == "pro.quarterly" })
        #expect(standing("pro.yearly", in: offered) == .upgrade(replacing: "Gói quý"))
        #expect(PaywallCopy.hasSubscription(among: offered))
        // Bought for good, so offered no plan: theirs still renews, and the
        // plan kept for good says so.
        let owner = plans(for: subscriber("pro.legacy", renewsAs: "pro.legacy", owned: ["pro.lifetime"]))
        #expect(owner.map(\.id) == ["pro.lifetime"])
        #expect(owner.first?.standing == .owned(renewing: "gói đăng ký hiện tại"))
        #expect(PaywallCopy.hasSubscription(among: owner))
        // Nothing they pay for: no link.
        #expect(!PaywallCopy.hasSubscription(among: plans(for: subscriber("pro.yearly", renewsAs: "pro.yearly", familyShared: true))))
        #expect(!PaywallCopy.hasSubscription(among: plans(for: StoreCustomer(owned: ["pro.lifetime"]))))
    }

    @Test("Bought for good while monthly renews: monthly stays, to say it still costs them")
    func ownedForGoodWhileSubscribed() {
        let offered = plans(for: subscriber("pro.monthly", renewsAs: "pro.monthly", owned: ["pro.lifetime"]))
        #expect(offered.map(\.id) == ["pro.monthly", "pro.lifetime"])
        #expect(offered[0].standing == .current(.renews(on: renewal), ownedForGood: true))
        #expect(offered[1].standing == .owned(renewing: "Gói tháng"))
        // And the downgrade chosen before stays too.
        let chosen = plans(for: subscriber("pro.yearly", renewsAs: "pro.monthly", owned: ["pro.lifetime"]))
        #expect(chosen.map(\.id) == order)
    }

    @Test("As much as theirs: the same length starts at once, another length when their period ends")
    func crossgrades() {
        let products = [
            subscription("basic.monthly", 39_000, every: .init(1, .month), name: "Tháng A"),
            subscription("other.monthly", 45_000, every: .init(1, .month), name: "Tháng B"),
            subscription("other.twelve", 399_000, every: .init(12, .month), name: "Mười hai tháng"),
            subscription("basic.yearly", 299_000, every: .init(1, .year), name: "Năm A"),
        ]
        let ids = products.map(\.id)
        let monthly = plans(for: subscriber("basic.monthly", renewsAs: "basic.monthly"), from: products, in: ids)
        #expect(standing("other.monthly", in: monthly) == .crossgrade(replacing: "Tháng A"))
        #expect(standing("basic.yearly", in: monthly) == .nextPeriod(replacing: "Tháng A", from: renewal))
        // Twelve months last a year.
        let yearly = plans(for: subscriber("basic.yearly", renewsAs: "basic.yearly"), from: products, in: ids)
        #expect(standing("other.twelve", in: yearly) == .crossgrade(replacing: "Năm A"))
    }

    @Test("Their plan was not loaded: a change is offered without saying when it starts")
    func unknownPlan() {
        let offered = plans(for: subscriber("pro.legacy", renewsAs: "pro.legacy"))
        #expect(standing("pro.yearly", in: offered) == .change(replacing: "gói đăng ký hiện tại"))
        #expect(standing("pro.monthly", in: offered) == .change(replacing: "gói đăng ký hiện tại"))
        #expect(standing("pro.lifetime", in: offered) == .alongside(subscription: "gói đăng ký hiện tại"))
    }

    @Test("A subscription of another group touches none of these plans")
    func otherGroup() {
        let offered = plans(for: subscriber("photos.monthly", renewsAs: "photos.monthly", group: "photos"))
        #expect(offered.map(\.id) == order)
        #expect(offered.allSatisfy { $0.standing == nil })
    }

    @Test("Lengths: equal periods, a year and twelve months, a week and seven days")
    func lengths() {
        #expect(PaywallCatalog.sameLength(.init(1, .month), .init(1, .month)))
        #expect(PaywallCatalog.sameLength(.init(12, .month), .init(1, .year)))
        #expect(PaywallCatalog.sameLength(.init(7, .day), .init(1, .week)))
        #expect(PaywallCatalog.sameLength(.init(3, .month), .init(3, .month)))
        #expect(!PaywallCatalog.sameLength(.init(1, .month), .init(1, .year)))
        #expect(!PaywallCatalog.sameLength(.init(3, .month), .init(1, .month)))
    }
}

@Suite("Paywall copy: what each plan says, before and after the customer has one")
struct PaywallCopyTests {
    private let monthly = VND.string(39_000) + "/tháng"
    private let yearly = VND.string(299_000) + "/năm"
    private let once = VND.string(599_000)

    private func plan(_ id: String, _ standing: PaywallPlan.Standing?, trial: PaywallPlan.FreeTrial? = nil) -> PaywallPlan {
        switch id {
        case "pro.yearly":
            PaywallPlan(id: id, term: .yearly, title: "Gói năm", displayPrice: VND.string(299_000), price: 299_000,
                        freeTrial: trial, detail: "≈ 24.917 ₫/tháng", standing: standing)
        case "pro.monthly":
            PaywallPlan(id: id, term: .monthly, title: "Gói tháng", displayPrice: VND.string(39_000), price: 39_000, standing: standing)
        default:
            PaywallPlan(id: id, term: .lifetime, title: "Mua một lần", displayPrice: VND.string(599_000), price: 599_000,
                        detail: "Trả một lần, dùng mãi mãi", standing: standing)
        }
    }

    @Test("A new customer: the price, the trial, and the button, as before")
    func newCustomer() {
        let trial = plan("pro.yearly", nil, trial: .days(7))
        #expect(PaywallCopy.priceLine(for: trial, calendar: vietnam) == "Miễn phí 7 ngày, sau đó \(yearly)")
        #expect(PaywallCopy.callToAction(for: trial, calendar: vietnam) == "Dùng thử miễn phí 7 ngày")
        #expect(PaywallCopy.terms(for: trial, calendar: vietnam)
            == "Miễn phí 7 ngày, sau đó \(yearly). Tự động gia hạn, huỷ bất cứ lúc nào trong Cài đặt.")
        let month = plan("pro.monthly", nil)
        #expect(PaywallCopy.priceLine(for: month, calendar: vietnam) == "\(monthly), tự động gia hạn")
        #expect(PaywallCopy.callToAction(for: month, calendar: vietnam) == "Đăng ký · \(monthly)")
        #expect(PaywallCopy.terms(for: month, calendar: vietnam) == "\(monthly), tự động gia hạn. Huỷ bất cứ lúc nào trong Cài đặt.")
        let lifetime = plan("pro.lifetime", nil)
        #expect(PaywallCopy.priceLine(for: lifetime, calendar: vietnam) == "Trả một lần \(once)")
        #expect(PaywallCopy.callToAction(for: lifetime, calendar: vietnam) == "Mua một lần · \(once)")
        #expect(PaywallCopy.terms(for: lifetime, calendar: vietnam) == "Thanh toán một lần \(once), dùng mãi mãi. Không tự động gia hạn.")
        for plan in [trial, month, lifetime] {
            #expect(PaywallCopy.action(for: plan) == .purchase)
            #expect(PaywallCopy.standingBadge(for: plan, calendar: vietnam) == nil)
            #expect(PaywallCopy.detail(for: plan, calendar: vietnam) == plan.detail)
        }
    }

    @Test("Their plan, renewing: when, and the button manages it")
    func currentRenews() {
        let current = plan("pro.monthly", .current(.renews(on: renewal), ownedForGood: false))
        #expect(PaywallCopy.priceLine(for: current, calendar: vietnam) == "Đang dùng: \(monthly), gia hạn ngày 13/10/2026")
        #expect(PaywallCopy.terms(for: current, calendar: vietnam)
            == "Bạn đang dùng Gói tháng: \(monthly), tự động gia hạn ngày 13/10/2026. Đổi gói hoặc huỷ trong Quản lý gói đăng ký.")
        #expect(PaywallCopy.callToAction(for: current, calendar: vietnam) == "Quản lý gói đăng ký")
        #expect(PaywallCopy.action(for: current) == .manageSubscriptions)
        #expect(PaywallCopy.standingBadge(for: current, calendar: vietnam) == "Đang dùng")
        #expect(PaywallCopy.detail(for: current, calendar: vietnam) == "Gia hạn ngày 13/10/2026")
        // With no date from the App Store, no date is made up.
        let undated = plan("pro.monthly", .current(.renews(on: nil), ownedForGood: false))
        #expect(PaywallCopy.priceLine(for: undated, calendar: vietnam) == "Đang dùng: \(monthly), tự động gia hạn")
        #expect(PaywallCopy.detail(for: undated, calendar: vietnam) == "Tự động gia hạn")
        // Bought for good as well: this one only costs them now.
        let needless = plan("pro.monthly", .current(.renews(on: renewal), ownedForGood: true))
        #expect(PaywallCopy.terms(for: needless, calendar: vietnam)
            == "Bạn đang dùng Gói tháng: \(monthly), tự động gia hạn ngày 13/10/2026. "
            + "Bạn đã mua gói dùng mãi mãi: huỷ gói này trong Quản lý gói đăng ký để không bị trừ tiền nữa.")
    }

    @Test("Their plan, switching or ending")
    func currentSwitchesOrEnds() {
        let switching = plan("pro.yearly", .current(.switches(to: "Gói tháng", on: renewal), ownedForGood: false))
        #expect(PaywallCopy.priceLine(for: switching, calendar: vietnam) == "Đang dùng đến 13/10/2026, rồi chuyển sang Gói tháng")
        #expect(PaywallCopy.terms(for: switching, calendar: vietnam)
            == "Bạn đang dùng Gói năm đến hết ngày 13/10/2026, rồi gói gia hạn thành Gói tháng. Đổi gói hoặc huỷ trong Quản lý gói đăng ký.")
        #expect(PaywallCopy.detail(for: switching, calendar: vietnam) == "Đến 13/10/2026, rồi chuyển sang Gói tháng")
        let ending = plan("pro.monthly", .current(.ends(on: renewal), ownedForGood: false))
        #expect(PaywallCopy.priceLine(for: ending, calendar: vietnam) == "Đang dùng đến 13/10/2026, không gia hạn")
        #expect(PaywallCopy.terms(for: ending, calendar: vietnam)
            == "Bạn đang dùng Gói tháng đến hết ngày 13/10/2026. Gói không tự gia hạn; bật lại trong Quản lý gói đăng ký.")
        #expect(PaywallCopy.detail(for: ending, calendar: vietnam) == "Hết hạn ngày 13/10/2026")
        #expect(PaywallCopy.action(for: ending) == .manageSubscriptions)
    }

    @Test("Bought for good: nothing to do, but cancel a subscription that still renews")
    func owned() {
        let owned = plan("pro.lifetime", .owned(renewing: nil))
        #expect(PaywallCopy.priceLine(for: owned, calendar: vietnam) == "Đã mua, dùng mãi mãi")
        #expect(PaywallCopy.terms(for: owned, calendar: vietnam) == "Đã mua: dùng mãi mãi, không phải trả thêm.")
        #expect(PaywallCopy.callToAction(for: owned, calendar: vietnam) == "Đã mua")
        #expect(PaywallCopy.action(for: owned) == .nothing)
        #expect(PaywallCopy.standingBadge(for: owned, calendar: vietnam) == "Đã mua")
        #expect(PaywallCopy.detail(for: owned, calendar: vietnam) == "Trả một lần, dùng mãi mãi")
        let paying = plan("pro.lifetime", .owned(renewing: "Gói tháng"))
        #expect(PaywallCopy.priceLine(for: paying, calendar: vietnam) == "Đã mua; Gói tháng vẫn tự gia hạn")
        #expect(PaywallCopy.terms(for: paying, calendar: vietnam)
            == "Đã mua: dùng mãi mãi. Nhưng Gói tháng vẫn tự gia hạn: hãy huỷ trong Quản lý gói đăng ký để không bị trừ tiền nữa.")
        #expect(PaywallCopy.callToAction(for: paying, calendar: vietnam) == "Đã mua")
        #expect(PaywallCopy.action(for: paying) == .nothing)
    }

    @Test("An upgrade starts now, and says the rest of theirs is refunded")
    func upgrade() {
        let upgrade = plan("pro.yearly", .upgrade(replacing: "Gói tháng"))
        #expect(PaywallCopy.priceLine(for: upgrade, calendar: vietnam) == "Đổi ngay: \(yearly), tự động gia hạn")
        #expect(PaywallCopy.terms(for: upgrade, calendar: vietnam)
            == "Đổi từ Gói tháng sang Gói năm ngay bây giờ: \(yearly), tự động gia hạn; "
            + "App Store hoàn lại phần chưa dùng của Gói tháng. Huỷ bất cứ lúc nào trong Cài đặt.")
        #expect(PaywallCopy.callToAction(for: upgrade, calendar: vietnam) == "Nâng cấp · \(yearly)")
        #expect(PaywallCopy.action(for: upgrade) == .purchase)
        #expect(PaywallCopy.standingBadge(for: upgrade, calendar: vietnam) == nil)
    }

    @Test("A downgrade starts when their period ends, and says so on the button")
    func nextPeriod() {
        let later = plan("pro.monthly", .nextPeriod(replacing: "Gói năm", from: renewal))
        #expect(PaywallCopy.priceLine(for: later, calendar: vietnam) == "Từ 13/10/2026: \(monthly), tự động gia hạn")
        #expect(PaywallCopy.terms(for: later, calendar: vietnam)
            == "Gói năm vẫn dùng đến hết ngày 13/10/2026, rồi gia hạn thành Gói tháng: \(monthly), tự động gia hạn. "
            + "Huỷ bất cứ lúc nào trong Cài đặt.")
        #expect(PaywallCopy.callToAction(for: later, calendar: vietnam) == "Chuyển từ 13/10/2026 · \(monthly)")
        #expect(PaywallCopy.action(for: later) == .purchase)
        let undated = plan("pro.monthly", .nextPeriod(replacing: "Gói năm", from: nil))
        #expect(PaywallCopy.callToAction(for: undated, calendar: vietnam) == "Chuyển từ kỳ sau · \(monthly)")
        #expect(PaywallCopy.terms(for: undated, calendar: vietnam)
            == "Gói năm vẫn dùng đến hết kỳ này, rồi gia hạn thành Gói tháng: \(monthly), tự động gia hạn. Huỷ bất cứ lúc nào trong Cài đặt.")
    }

    @Test("Chosen already: from when, and the button manages it")
    func scheduled() {
        let chosen = plan("pro.monthly", .scheduled(from: renewal))
        #expect(PaywallCopy.priceLine(for: chosen, calendar: vietnam) == "Từ 13/10/2026: \(monthly), tự động gia hạn")
        #expect(PaywallCopy.terms(for: chosen, calendar: vietnam)
            == "Từ ngày 13/10/2026, gói của bạn gia hạn thành Gói tháng: \(monthly). Đổi lại hoặc huỷ trong Quản lý gói đăng ký.")
        #expect(PaywallCopy.callToAction(for: chosen, calendar: vietnam) == "Quản lý gói đăng ký")
        #expect(PaywallCopy.action(for: chosen) == .manageSubscriptions)
        #expect(PaywallCopy.standingBadge(for: chosen, calendar: vietnam) == "Từ 13/10/2026")
        #expect(PaywallCopy.standingBadge(for: plan("pro.monthly", .scheduled(from: nil)), calendar: vietnam) == "Từ kỳ sau")
    }

    @Test("Crossgrades and unknown changes: at once, or with no promise of when")
    func otherChanges() {
        let now = plan("pro.monthly", .crossgrade(replacing: "Tháng A"))
        #expect(PaywallCopy.priceLine(for: now, calendar: vietnam) == "Đổi ngay: \(monthly), tự động gia hạn")
        #expect(PaywallCopy.terms(for: now, calendar: vietnam)
            == "Đổi từ Tháng A sang Gói tháng ngay bây giờ: \(monthly), tự động gia hạn. Huỷ bất cứ lúc nào trong Cài đặt.")
        #expect(PaywallCopy.callToAction(for: now, calendar: vietnam) == "Đổi gói · \(monthly)")
        let unknown = plan("pro.yearly", .change(replacing: "gói đăng ký hiện tại"))
        #expect(PaywallCopy.priceLine(for: unknown, calendar: vietnam) == "\(yearly), tự động gia hạn")
        #expect(PaywallCopy.terms(for: unknown, calendar: vietnam)
            == "Đổi từ gói đăng ký hiện tại sang Gói năm: \(yearly), tự động gia hạn. Huỷ bất cứ lúc nào trong Cài đặt.")
        #expect(PaywallCopy.callToAction(for: unknown, calendar: vietnam) == "Đổi gói · \(yearly)")
    }

    @Test("Buying for good while subscribed says the subscription does not stop")
    func alongside() {
        let lifetime = plan("pro.lifetime", .alongside(subscription: "Gói tháng"))
        #expect(PaywallCopy.priceLine(for: lifetime, calendar: vietnam) == "Trả một lần \(once); Gói tháng vẫn tự gia hạn")
        #expect(PaywallCopy.terms(for: lifetime, calendar: vietnam)
            == "Thanh toán một lần \(once), dùng mãi mãi. Việc này không huỷ Gói tháng: "
            + "hãy huỷ trong Quản lý gói đăng ký để không bị trừ tiền nữa.")
        #expect(PaywallCopy.callToAction(for: lifetime, calendar: vietnam) == "Mua một lần · \(once)")
        #expect(PaywallCopy.action(for: lifetime) == .purchase)
    }

    @Test("Shared by the family: nothing to buy or manage")
    func sharedByFamily() {
        let shared = plan("pro.yearly", .sharedByFamily)
        #expect(PaywallCopy.priceLine(for: shared, calendar: vietnam) == "Được chia sẻ trong gia đình")
        #expect(PaywallCopy.terms(for: shared, calendar: vietnam)
            == "Bạn đang dùng Gói năm nhờ Chia sẻ trong gia đình: người trong gia đình đã mua gói quản lý và trả tiền cho nó.")
        #expect(PaywallCopy.callToAction(for: shared, calendar: vietnam) == "Đã có qua gia đình")
        #expect(PaywallCopy.action(for: shared) == .nothing)
        #expect(PaywallCopy.standingBadge(for: shared, calendar: vietnam) == "Gia đình chia sẻ")
        #expect(PaywallCopy.detail(for: shared, calendar: vietnam) == "Qua Chia sẻ trong gia đình")
        #expect(!PaywallCopy.hasSubscription(among: [shared]))
    }

    @Test("The paywall links to managing subscriptions only for a subscriber")
    func manageLink() {
        #expect(!PaywallCopy.hasSubscription(among: [plan("pro.yearly", nil), plan("pro.lifetime", nil)]))
        #expect(!PaywallCopy.hasSubscription(among: [plan("pro.lifetime", .owned(renewing: nil))]))
        #expect(PaywallCopy.hasSubscription(among: [plan("pro.lifetime", .owned(renewing: "Gói quý"))]))
        #expect(PaywallCopy.hasSubscription(among: [
            plan("pro.yearly", .upgrade(replacing: "Gói tháng")),
            plan("pro.monthly", .current(.ends(on: renewal), ownedForGood: false)),
        ]))
    }

    @Test("A downgrade bought says when it starts")
    func scheduledMessage() {
        let offered = [plan("pro.yearly", nil), plan("pro.monthly", nil)]
        #expect(StoreCopy.purchaseMessage(for: .scheduled(productID: "pro.monthly", from: renewal), plans: offered, calendar: vietnam)
            == StoreMessage("Gói tháng sẽ bắt đầu từ ngày 13/10/2026, khi gói hiện tại hết kỳ.", tone: .success))
        #expect(StoreCopy.purchaseMessage(for: .scheduled(productID: "pro.monthly", from: nil), plans: offered, calendar: vietnam)
            == StoreMessage("Gói tháng sẽ bắt đầu từ kỳ sau, khi gói hiện tại hết kỳ.", tone: .success))
    }
}
