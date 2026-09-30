import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// A moment on Vietnam's clock.
private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10, minute: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Purchase help: the payments listed, where each stands for a refund, and the words")
struct PurchaseHelpTests {
    @Test("The customer's own payments, newest first; a family member's, or a free one, is not listed")
    func listed() {
        let bought = StorePurchase(id: 1, productID: "pro.monthly", date: day(2026, 8, 1), price: 39_000)
        let renewed = StorePurchase(id: 2, productID: "pro.monthly", date: day(2026, 9, 1), price: 39_000, isRenewal: true)
        let shared = StorePurchase(id: 3, productID: "pro.yearly", date: day(2026, 9, 10), price: 299_000, isFamilyShared: true)
        let trial = StorePurchase(id: 4, productID: "pro.yearly", date: day(2026, 7, 25), price: 0)
        // StoreKit gave no price: listed, it may have cost something.
        let unpriced = StorePurchase(id: 5, productID: "pro.lifetime", date: day(2026, 9, 15))
        // The same moment: the later transaction first.
        let sameMoment = StorePurchase(id: 6, productID: "pro.yearly", date: day(2026, 9, 15), price: 299_000)
        let listed = PurchaseHistory.listed([bought, renewed, shared, trial, unpriced, sameMoment])
        #expect(listed.map(\.id) == [6, 5, 2, 1])
    }

    @Test("Refunded once the App Store says so, request or not; a request kept says it is under way")
    func standing() {
        let refundedOn = day(2026, 9, 20)
        let refunded = StorePurchase(id: 1, productID: "pro.yearly", date: day(2026, 9, 12), price: 299_000, revocationDate: refundedOn)
        let paid = StorePurchase(id: 2, productID: "pro.monthly", date: day(2026, 9, 1), price: 39_000)
        #expect(PurchaseHistory.standing(of: refunded, requested: [1]) == .refunded(refundedOn))
        #expect(PurchaseHistory.standing(of: refunded, requested: []) == .refunded(refundedOn))
        #expect(PurchaseHistory.standing(of: paid, requested: [2]) == .requested)
        #expect(PurchaseHistory.standing(of: paid, requested: [1]) == .open)
    }

    @Test("A request sent, or one the App Store already had, is kept across launches; closed or failed keeps none")
    func requests() throws {
        let suite = "PurchaseHelpTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let requests = StoreRefundRequests(defaults: defaults)
        #expect(requests.requested.isEmpty)
        #expect(requests.record(.cancelled, for: 7).isEmpty)
        #expect(requests.record(.failed("Không có mạng"), for: 7).isEmpty)
        #expect(requests.record(.requested, for: 7) == [7])
        // The next launch reads it back.
        #expect(StoreRefundRequests(defaults: defaults).requested == [7])
        #expect(StoreRefundRequests(defaults: defaults).record(.alreadyRequested, for: 8) == [7, 8])
        #expect(requests.record(.requested, for: 7) == [7, 8])
        #expect(requests.requested == [7, 8])
    }

    @Test("The payment as a statement shows it, on Vietnam's clock; its name from the App Store, else the plan")
    func purchaseWords() {
        // Half past midnight in Vietnam is still the day before in UTC.
        let bought = StorePurchase(
            id: 1, productID: "pro.yearly", date: day(2026, 9, 13, hour: 0, minute: 30), price: 299_000, displayPrice: "299.000 ₫"
        )
        #expect(StoreCopy.purchaseLine(bought, calendar: vietnam) == "Mua ngày 13/09/2026 · 299.000 ₫")
        let renewed = StorePurchase(
            id: 2, productID: "pro.monthly", date: day(2026, 10, 12), price: 39_000, displayPrice: "39.000 ₫", isRenewal: true
        )
        #expect(StoreCopy.purchaseLine(renewed, calendar: vietnam) == "Gia hạn ngày 12/10/2026 · 39.000 ₫")
        let unpriced = StorePurchase(id: 3, productID: "pro.lifetime", date: day(2026, 9, 12))
        #expect(StoreCopy.purchaseLine(unpriced, calendar: vietnam) == "Mua ngày 12/09/2026")

        let plans = [PaywallPlan(id: "pro.yearly", term: .yearly, title: "Gói năm", displayPrice: "299.000 ₫", price: 299_000)]
        var named = bought
        named.title = "Gói năm (App Store)"
        #expect(StoreCopy.purchaseTitle(named, plans: plans) == "Gói năm (App Store)")
        #expect(StoreCopy.purchaseTitle(bought, plans: plans) == "Gói năm")
        #expect(StoreCopy.purchaseTitle(unpriced, plans: plans) == "Gói đã mua")
    }

    @Test("Where the button was: a request under way, or the refund's date; after the sheet, never a guess at Apple's answer")
    func refundWords() {
        #expect(StoreCopy.refundLine(.open, calendar: vietnam) == nil)
        #expect(StoreCopy.refundLine(.requested, calendar: vietnam) == "Đã gửi yêu cầu hoàn tiền")
        #expect(StoreCopy.refundLine(.refunded(day(2026, 9, 21, hour: 0, minute: 15)), calendar: vietnam) == "Đã hoàn tiền ngày 21/09/2026")

        #expect(StoreCopy.refundMessage(for: .requested) == StoreMessage("Đã gửi yêu cầu hoàn tiền.", tone: .success))
        #expect(StoreCopy.refundMessage(for: .cancelled) == nil)
        #expect(StoreCopy.refundMessage(for: .alreadyRequested) == StoreMessage("Giao dịch này đã có yêu cầu hoàn tiền.", tone: .notice))
        #expect(
            StoreCopy.refundMessage(for: .failed("Không có mạng"))
                == StoreMessage("Chưa gửi được yêu cầu hoàn tiền: Không có mạng", tone: .failure)
        )
    }
}
