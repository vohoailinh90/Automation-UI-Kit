import Foundation

/// Wording for the paywall (`PaywallScreen`), in one place so it can be
/// localised and reviewed: what each plan costs, what the button does, and,
/// for a customer who has a plan already, what changes and when.
///
/// Dates are the customer's (`calendar`'s clock), written "27/09/2027".
public enum PaywallCopy {
    /// What the paywall's button does for a plan.
    public enum Action: Hashable, Sendable {
        /// Buys it.
        case purchase
        /// Opens the App Store's page for the customer's subscriptions,
        /// where they change, cancel or renew what they have.
        case manageSubscriptions
        /// Opens Apple's page for the payment methods of their account
        /// (`StoreLinks.billing`), for a renewal the App Store could not
        /// charge for.
        case updatePayment
        /// Nothing: they own it for good.
        case nothing
    }

    /// "/tháng", "/năm"...; empty for lifetime.
    public static func perTerm(_ term: PaywallPlan.Term) -> String {
        switch term {
        case .weekly: "/tuần"
        case .monthly: "/tháng"
        case .yearly: "/năm"
        case .lifetime: ""
        }
    }

    /// The price that will be charged and when, in as few words as possible:
    /// what stays next to the button even at the largest text sizes.
    public static func priceLine(for plan: PaywallPlan, calendar: Calendar = .autoupdatingCurrent) -> String {
        let price = plan.displayPrice + perTerm(plan.term)
        switch plan.standing {
        case let .current(renewal, _)?:
            switch renewal {
            case let .renews(date):
                return date.map { "Đang dùng: \(price), gia hạn ngày \(day($0, calendar))" } ?? "Đang dùng: \(price), tự động gia hạn"
            case let .switches(next, date):
                return date.map { "Đang dùng đến \(day($0, calendar)), rồi chuyển sang \(next)" } ?? "Đang dùng, kỳ sau chuyển sang \(next)"
            case let .ends(date):
                return date.map { "Đang dùng đến \(day($0, calendar)), không gia hạn" } ?? "Đang dùng, không gia hạn"
            case let .billingIssue(.gracePeriod(until)):
                return until.map { "Chưa gia hạn được \(price); vẫn dùng đến \(day($0, calendar))" }
                    ?? "Chưa gia hạn được \(price); App Store đang thử lại"
            case .billingIssue(.retrying):
                return "Tạm dừng: chưa thanh toán được \(price)"
            }
        case let .owned(renewing)?:
            return renewing.map { "Đã mua; \($0) vẫn tự gia hạn" } ?? "Đã mua, dùng mãi mãi"
        case .sharedByFamily?:
            return "Được chia sẻ trong gia đình"
        case let .scheduled(date)?, let .nextPeriod(_, date)?:
            return "\(start(date, calendar)): \(price), tự động gia hạn"
        case .upgrade?, .crossgrade?:
            return "Đổi ngay: \(price), tự động gia hạn"
        case let .alongside(subscription)?:
            return "Trả một lần \(plan.displayPrice); \(subscription) vẫn tự gia hạn"
        case .change?, nil:
            break
        }
        switch (plan.term, plan.freeTrial) {
        case (.lifetime, _):
            return "Trả một lần \(plan.displayPrice)"
        case (_, .some(let trial)) where trial.count > 0:
            return "Miễn phí \(trial.text), sau đó \(price)"
        default:
            return "\(price), tự động gia hạn"
        }
    }

    /// The renewal terms Apple requires next to the purchase button, and
    /// for a customer who has a plan, what buying this one changes.
    public static func terms(for plan: PaywallPlan, calendar: Calendar = .autoupdatingCurrent) -> String {
        let price = plan.displayPrice + perTerm(plan.term)
        let cancel = "Huỷ bất cứ lúc nào trong Cài đặt."
        switch plan.standing {
        case let .current(renewal, ownedForGood)?:
            switch renewal {
            case let .renews(date):
                let when = date.map { "tự động gia hạn ngày \(day($0, calendar))" } ?? "tự động gia hạn"
                return "Bạn đang dùng \(plan.title): \(price), \(when). " + manage(ownedForGood: ownedForGood)
            case let .switches(next, date):
                let until = date.map { " đến hết ngày \(day($0, calendar))" } ?? " đến hết kỳ này"
                return "Bạn đang dùng \(plan.title)\(until), rồi gói gia hạn thành \(next). " + manage(ownedForGood: ownedForGood)
            case let .ends(date):
                let until = date.map { " đến hết ngày \(day($0, calendar))" } ?? " đến hết kỳ này"
                return "Bạn đang dùng \(plan.title)\(until). Gói không tự gia hạn; bật lại trong Quản lý gói đăng ký."
            case let .billingIssue(issue):
                let failed = "App Store chưa thu được tiền gia hạn \(plan.title) (\(price))"
                if ownedForGood {
                    return "\(failed). Bạn đã mua gói dùng mãi mãi nên không cần gói này: "
                        + "huỷ nó trong Quản lý gói đăng ký để App Store thôi thu tiền."
                }
                return "\(failed)\(billingIssueTerms(issue, calendar))"
            }
        case let .owned(renewing)?:
            return renewing.map { "Đã mua: dùng mãi mãi. Nhưng \($0) vẫn tự gia hạn: hãy huỷ trong Quản lý gói đăng ký để không bị trừ tiền nữa." }
                ?? "Đã mua: dùng mãi mãi, không phải trả thêm."
        case .sharedByFamily?:
            return "Bạn đang dùng \(plan.title) nhờ Chia sẻ trong gia đình: người trong gia đình đã mua gói quản lý và trả tiền cho nó."
        case let .scheduled(date)?:
            let from = date.map { "Từ ngày \(day($0, calendar))" } ?? "Từ kỳ sau"
            return "\(from), gói của bạn gia hạn thành \(plan.title): \(price). Đổi lại hoặc huỷ trong Quản lý gói đăng ký."
        case let .upgrade(replacing)?:
            return "Đổi từ \(replacing) sang \(plan.title) ngay bây giờ: \(price), tự động gia hạn; "
                + "App Store hoàn lại phần chưa dùng của \(replacing). \(cancel)"
        case let .crossgrade(replacing)?:
            return "Đổi từ \(replacing) sang \(plan.title) ngay bây giờ: \(price), tự động gia hạn. \(cancel)"
        case let .nextPeriod(replacing, date)?:
            let until = date.map { " đến hết ngày \(day($0, calendar))" } ?? " đến hết kỳ này"
            return "\(replacing) vẫn dùng\(until), rồi gia hạn thành \(plan.title): \(price), tự động gia hạn. \(cancel)"
        case let .change(replacing)?:
            return "Đổi từ \(replacing) sang \(plan.title): \(price), tự động gia hạn. \(cancel)"
        case let .alongside(subscription)?:
            return "Thanh toán một lần \(plan.displayPrice), dùng mãi mãi. Việc này không huỷ \(subscription): "
                + "hãy huỷ trong Quản lý gói đăng ký để không bị trừ tiền nữa."
        case nil:
            break
        }
        switch (plan.term, plan.freeTrial) {
        case (.lifetime, _):
            return "Thanh toán một lần \(plan.displayPrice), dùng mãi mãi. Không tự động gia hạn."
        case (_, .some(let trial)) where trial.count > 0:
            return "Miễn phí \(trial.text), sau đó \(price). Tự động gia hạn, huỷ bất cứ lúc nào trong Cài đặt."
        default:
            return "\(price), tự động gia hạn. \(cancel)"
        }
    }

    /// The button says what happens and what it costs.
    public static func callToAction(for plan: PaywallPlan, calendar: Calendar = .autoupdatingCurrent) -> String {
        let price = plan.displayPrice + perTerm(plan.term)
        switch action(for: plan) {
        case .updatePayment:
            return "Cập nhật thanh toán"
        case .manageSubscriptions:
            return "Quản lý gói đăng ký"
        case .purchase, .nothing:
            break
        }
        switch plan.standing {
        case .owned?:
            return "Đã mua"
        case .sharedByFamily?:
            return "Đã có qua gia đình"
        case .upgrade?:
            return "Nâng cấp · \(price)"
        case .crossgrade?, .change?:
            return "Đổi gói · \(price)"
        case let .nextPeriod(_, date)?:
            return "Chuyển \(start(date, calendar).lowercased()) · \(price)"
        case .current?, .scheduled?, .alongside?, nil:
            break
        }
        switch (plan.term, plan.freeTrial) {
        case (.lifetime, _):
            return "Mua một lần · \(plan.displayPrice)"
        case (_, .some(let trial)) where trial.count > 0:
            return "Dùng thử miễn phí \(trial.text)"
        default:
            return "Đăng ký · \(price)"
        }
    }

    /// What the button does for `plan`: a plan the customer has, or has
    /// chosen to renew as, is theirs to manage, not to buy again; theirs
    /// that the App Store could not charge for, to pay for, unless they
    /// bought the plan kept for good and only need to cancel it.
    public static func action(for plan: PaywallPlan) -> Action {
        switch plan.standing {
        case .current(.billingIssue, ownedForGood: false)?: .updatePayment
        case .current?, .scheduled?: .manageSubscriptions
        case .owned?, .sharedByFamily?: .nothing
        default: .purchase
        }
    }

    /// Whether the App Store could not charge for the renewal of `plan`,
    /// the customer's: the paywall then chooses it first, and marks it as
    /// needing their attention.
    public static func hasBillingIssue(_ plan: PaywallPlan) -> Bool {
        if case .current(.billingIssue, _)? = plan.standing { true } else { false }
    }

    /// The label on the card for where the plan stands: "Đang dùng",
    /// "Đã mua", "Từ 27/09/2027", "Tạm dừng". `nil` otherwise: the card
    /// shows the plan's own badge ("Tiết kiệm 36%"), if any.
    public static func standingBadge(for plan: PaywallPlan, calendar: Calendar = .autoupdatingCurrent) -> String? {
        switch plan.standing {
        case .current(.billingIssue(.gracePeriod), _)?: "Chưa gia hạn được"
        case .current(.billingIssue(.retrying), _)?: "Tạm dừng"
        case .current?: "Đang dùng"
        case .owned?: "Đã mua"
        case .sharedByFamily?: "Gia đình chia sẻ"
        case let .scheduled(date)?: start(date, calendar)
        default: nil
        }
    }

    /// The line under the card's title: when the customer's plan renews or
    /// ends, else the plan's own line ("≈ 24.917 ₫/tháng").
    public static func detail(for plan: PaywallPlan, calendar: Calendar = .autoupdatingCurrent) -> String? {
        if case .sharedByFamily? = plan.standing { return "Qua Chia sẻ trong gia đình" }
        guard case let .current(renewal, _)? = plan.standing else { return plan.detail }
        switch renewal {
        case let .renews(date):
            return date.map { "Gia hạn ngày \(day($0, calendar))" } ?? "Tự động gia hạn"
        case let .switches(next, date):
            return date.map { "Đến \(day($0, calendar)), rồi chuyển sang \(next)" } ?? "Kỳ sau chuyển sang \(next)"
        case let .ends(date):
            return date.map { "Hết hạn ngày \(day($0, calendar))" } ?? "Không gia hạn"
        case let .billingIssue(.gracePeriod(until)):
            return until.map { "Vẫn dùng đến \(day($0, calendar))" } ?? "App Store đang thử lại"
        case .billingIssue(.retrying):
            return "Chưa thanh toán được"
        }
    }

    /// Whether the customer pays for a subscription of these plans' groups:
    /// the paywall then links to managing it. Any plan that stands against
    /// it tells, not only theirs, which may not be on offer (an old plan,
    /// say), or not shown, to someone who bought the plan kept for good.
    public static func hasSubscription(among plans: [PaywallPlan]) -> Bool {
        plans.contains { plan in
            switch plan.standing {
            case .current?, .scheduled?, .upgrade?, .crossgrade?, .nextPeriod?, .change?, .alongside?: true
            case let .owned(renewing)?: renewing != nil
            case .sharedByFamily?, nil: false
            }
        }
    }

    /// After "App Store chưa thu được tiền gia hạn Gói tháng (39.000 ₫/tháng)":
    /// until when the plan still works, and what to do.
    private static func billingIssueTerms(_ issue: StoreSubscription.BillingIssue, _ calendar: Calendar) -> String {
        switch issue {
        case let .gracePeriod(until?):
            ". Bạn vẫn dùng được đến hết ngày \(day(until, calendar)): "
                + "cập nhật phương thức thanh toán trước ngày đó để không bị gián đoạn."
        case .gracePeriod(nil):
            " và đang thử lại. Cập nhật phương thức thanh toán để không bị gián đoạn."
        case .retrying:
            ", nên gói đang tạm dừng. Cập nhật phương thức thanh toán: App Store sẽ thử lại, "
                + "và gói dùng tiếp ngay khi thu được. Không dùng nữa thì huỷ trong Quản lý gói đăng ký."
        }
    }

    /// "Từ 27/09/2027", or "Từ kỳ sau" when the App Store gave no date.
    private static func start(_ date: Date?, _ calendar: Calendar) -> String {
        date.map { "Từ \(day($0, calendar))" } ?? "Từ kỳ sau"
    }

    private static func manage(ownedForGood: Bool) -> String {
        ownedForGood
            ? "Bạn đã mua gói dùng mãi mãi: huỷ gói này trong Quản lý gói đăng ký để không bị trừ tiền nữa."
            : "Đổi gói hoặc huỷ trong Quản lý gói đăng ký."
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        LedgerExport.day(date, calendar)
    }
}
