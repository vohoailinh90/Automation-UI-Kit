import Foundation
import IdeaLabCore
import Testing

private func plan(_ term: PaywallPlan.Term, _ price: Decimal) -> PaywallPlan {
    PaywallPlan(id: "\(term)", term: term, title: "", displayPrice: "", price: price)
}

@Suite("Paywall plan maths")
struct PlanMathTests {
    @Test("Yearly 299k against 39k/month saves 36%, rounded down")
    func yearlyVersusMonthly() throws {
        // 299.000 / 12 = 24.916,67 per month; 1 − 24.916,67 / 39.000 = 36,1%.
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 299_000), comparedTo: plan(.monthly, 39_000)) == 36)
        let monthly = try #require(PlanMath.monthlyEquivalent(of: plan(.yearly, 299_000)))
        #expect(abs(NSDecimalNumber(decimal: monthly).doubleValue - 24_916.666) < 0.01)
    }

    @Test("Exact savings stay exact: 240/yr against 25/mo is 20%, not 19%")
    func exactPercentage() {
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 240), comparedTo: plan(.monthly, 25)) == 20)
    }

    @Test("Weekly plans are compared per month using 52 weeks a year")
    func weekly() throws {
        let perMonth = try #require(PlanMath.monthlyEquivalent(of: plan(.weekly, 12_000)))
        #expect(abs(NSDecimalNumber(decimal: perMonth).doubleValue - 52_000) < 0.01)
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 299_000), comparedTo: plan(.weekly, 29_000)) == 80)
    }

    @Test("No badge when it would be meaningless")
    func noSavings() {
        #expect(PlanMath.monthlyEquivalent(of: plan(.lifetime, 199_000)) == nil)
        #expect(PlanMath.savingsPercent(of: plan(.lifetime, 199_000), comparedTo: plan(.monthly, 39_000)) == nil)
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 600_000), comparedTo: plan(.monthly, 39_000)) == nil)
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 468_000), comparedTo: plan(.monthly, 39_000)) == nil)
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 0), comparedTo: plan(.monthly, 39_000)) == nil)
        #expect(PlanMath.savingsPercent(of: plan(.yearly, 299_000), comparedTo: plan(.monthly, 0)) == nil)
    }
}
