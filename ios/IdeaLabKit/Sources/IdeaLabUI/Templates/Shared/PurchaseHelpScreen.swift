#if os(iOS)
import IdeaLabCore
// For the App Store's sheets: refund requests, and the customer's subscriptions.
import StoreKit
import SwiftUI

/// Help with purchases, as Apple asks of an app that sells them (HIG,
/// "Providing help"): the customer's payments, newest first, each with
/// "Yêu cầu hoàn tiền", which opens the App Store's refund sheet
/// (`refundRequestSheet`). They come first, so no help stands between the
/// customer and the button. Then what may solve the problem instead:
/// restoring a purchase that did not come through, the App Store's page for
/// their subscriptions, answers to common questions, the developer. The
/// screen never guesses whether Apple will refund: the App Store decides,
/// and Apple's own page, linked under the payments, says how it goes.
///
/// Each payment says when it was, what it cost, and whether it was a
/// renewal (`StoreCopy.purchaseLine`), to find the one with the problem as
/// a bank statement shows it. One refunded, or with a request under way,
/// says so in place of the button (`PurchaseHistory.standing`). The three
/// newest show at first; older ones one tap away.
///
/// Pass the store's payments (`LabStore.purchases`, `nil` while it reads
/// them) and its requests (`LabStore.refundRequests`); `onRefund` hears how
/// each sheet ended, for the store to keep a request
/// (`LabStore.refundRequestEnded`) and the app to say how it went
/// (`StoreCopy.refundMessage`).
public struct PurchaseHelpScreen: View {
    /// A question customers ask, and its answer.
    public struct Question: Identifiable, Hashable, Sendable {
        public var question: String
        public var answer: String

        public var id: String { question }

        public init(_ question: String, answer: String) {
            self.question = question
            self.answer = answer
        }

        /// What customers of a subscription ask most: none about refunds,
        /// which Apple answers.
        public static let standard: [Question] = [
            Question(
                "Đã trả tiền mà app chưa mở gói?",
                answer: "Bấm Khôi phục mua hàng ở trên, trên máy đăng nhập đúng tài khoản Apple đã mua. "
                    + "Giao dịch còn chờ duyệt (cha mẹ duyệt, hay ngân hàng xác nhận) tự mở gói khi xong."
            ),
            Question(
                "Làm sao để huỷ gói đăng ký?",
                answer: "Bấm Quản lý gói đăng ký, chọn gói rồi chọn Huỷ đăng ký. Bạn vẫn dùng gói tới hết kỳ đã trả."
            ),
            Question(
                "Vì sao tôi bị trừ tiền lần nữa?",
                answer: "Gói đăng ký tự gia hạn mỗi kỳ cho tới khi được huỷ. Mỗi lần gia hạn là một giao dịch ở trên, kèm ngày trừ tiền."
            ),
            Question(
                "Đổi máy có mất gói không?",
                answer: "Không. Gói đi theo tài khoản Apple: đăng nhập cùng tài khoản trên máy mới, "
                    + "rồi bấm Khôi phục mua hàng nếu gói chưa mở."
            ),
        ]
    }

    private let purchases: [StorePurchase]?
    private let refundRequests: Set<UInt64>
    private let plans: [PaywallPlan]
    private let questions: [Question]
    private let managesSubscriptions: Bool
    private let onRestore: () -> Void
    private let onContact: () -> Void
    private let onRefund: @MainActor (StorePurchase, RefundOutcome) -> Void
    @State private var refunding: StorePurchase?
    @State private var showsRefundSheet = false
    @State private var showsOlder = false
    @State private var showsSubscriptions = false
    @Environment(\.labTheme) private var theme
    @Environment(\.calendar) private var calendar

    /// The payments shown before "Xem thêm": the newest, among which the one
    /// with a problem usually is, without pushing the rest of the help far
    /// down for someone who has paid for years.
    private static let shownFirst = 3

    /// - Parameters:
    ///   - purchases: the customer's payments, newest first
    ///     (`PurchaseHistory.listed`); `nil` while they are read.
    ///   - refundRequests: the payments with a refund request
    ///     (`StoreRefundRequests`).
    ///   - plans: the paywall's plans, to name a payment whose product the
    ///     App Store did not name.
    ///   - questions: the answers the app gives, `Question.standard` by
    ///     default; none leaves the section out.
    ///   - managesSubscriptions: shows "Quản lý gói đăng ký", for an app that
    ///     sells subscriptions.
    ///   - onRefund: the App Store's refund sheet for a payment closed.
    public init(
        purchases: [StorePurchase]?,
        refundRequests: Set<UInt64>,
        plans: [PaywallPlan] = [],
        questions: [Question] = Question.standard,
        managesSubscriptions: Bool = true,
        onRestore: @escaping () -> Void,
        onContact: @escaping () -> Void,
        onRefund: @escaping @MainActor (StorePurchase, RefundOutcome) -> Void
    ) {
        self.purchases = purchases
        self.refundRequests = refundRequests
        self.plans = plans
        self.questions = questions
        self.managesSubscriptions = managesSubscriptions
        self.onRestore = onRestore
        self.onContact = onContact
        self.onRefund = onRefund
    }

    public var body: some View {
        Form {
            Section {
                payments
                Link(destination: StoreLinks.refunds) {
                    HelpRowLabel(title: "Cách Apple xử lý yêu cầu hoàn tiền", icon: "info.circle.fill", trailing: "arrow.up.right")
                }
            } header: {
                Text(verbatim: "Giao dịch gần đây")
            } footer: {
                Text(verbatim: "Giao dịch của tài khoản Apple khác, hay do người trong gia đình mua rồi chia sẻ, không có ở đây.")
            }

            Section {
                Button(action: onRestore) {
                    HelpRowLabel(title: "Khôi phục mua hàng", icon: "arrow.clockwise", trailing: "chevron.right")
                }
                if managesSubscriptions {
                    Button {
                        showsSubscriptions = true
                    } label: {
                        HelpRowLabel(title: "Quản lý gói đăng ký", icon: "list.bullet.rectangle.fill", trailing: "chevron.right")
                    }
                }
            } header: {
                Text(verbatim: "Chưa thấy gói đã mua?")
            } footer: {
                // Apple: whatever else the help offers, a refund can still be asked for.
                Text(verbatim: "Đã mua trên máy khác, hay vừa cài lại app: khôi phục để mở lại gói. Vẫn có thể yêu cầu hoàn tiền ở trên.")
            }

            if !questions.isEmpty {
                Section {
                    ForEach(questions) { question in
                        DisclosureGroup {
                            Text(verbatim: question.answer)
                                .foregroundStyle(theme.secondaryLabel)
                        } label: {
                            Text(verbatim: question.question)
                                .foregroundStyle(theme.label)
                        }
                        .frame(minHeight: 44)
                    }
                } header: {
                    Text(verbatim: "Câu hỏi thường gặp")
                }
            }

            Section {
                Button(action: onContact) {
                    HelpRowLabel(title: "Liên hệ hỗ trợ", icon: "bubble.left.and.bubble.right.fill", trailing: "chevron.right")
                }
            } header: {
                Text(verbatim: "Vẫn cần giúp?")
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.canvas.ignoresSafeArea())
        .refundRequestSheet(for: refunding?.id ?? 0, isPresented: $showsRefundSheet) { result in
            guard let purchase = refunding else { return }
            refunding = nil
            onRefund(purchase, RefundOutcome(result))
        }
        .manageSubscriptionsSheet(isPresented: $showsSubscriptions)
    }

    @ViewBuilder private var payments: some View {
        if let purchases {
            if purchases.isEmpty {
                Text(verbatim: "Tài khoản Apple này chưa trả tiền cho gói nào của app.")
                    .foregroundStyle(theme.secondaryLabel)
                    .frame(minHeight: 44)
            } else {
                ForEach(showsOlder ? purchases : Array(purchases.prefix(Self.shownFirst))) { purchase in
                    PurchaseRow(
                        title: StoreCopy.purchaseTitle(purchase, plans: plans),
                        line: StoreCopy.purchaseLine(purchase, calendar: calendar),
                        isRenewal: purchase.isRenewal,
                        standing: PurchaseHistory.standing(of: purchase, requested: refundRequests)
                    ) {
                        refunding = purchase
                        showsRefundSheet = true
                    }
                }
                if !showsOlder, purchases.count > Self.shownFirst {
                    Button {
                        showsOlder = true
                    } label: {
                        Text(verbatim: "Xem thêm \(purchases.count - Self.shownFirst) giao dịch cũ hơn")
                            .foregroundStyle(theme.text(.accent))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
        } else {
            HStack(spacing: LabSpacing.sm) {
                ProgressView()
                Text(verbatim: "Đang đọc giao dịch…")
                    .foregroundStyle(theme.secondaryLabel)
            }
            .frame(minHeight: 44)
        }
    }
}

/// One payment: what, when, how much, and "Yêu cầu hoàn tiền", or where
/// its refund stands. The words wrap in full at every size, beside the icon
/// rather than under it or cut short: the date and the amount are what finds
/// the payment. (A `Label` inside the row's stack did neither at the
/// accessibility sizes.)
private struct PurchaseRow: View {
    let title: String
    let line: String
    let isRenewal: Bool
    let standing: RefundStanding
    let onRefund: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            HStack(alignment: .top, spacing: LabSpacing.sm) {
                SettingsIcon(isRenewal ? "arrow.triangle.2.circlepath" : "bag.fill")
                VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                    Text(verbatim: title)
                        .foregroundStyle(theme.label)
                    Text(verbatim: line)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryLabel)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let status = StoreCopy.refundLine(standing, calendar: calendar) {
                HStack(alignment: .firstTextBaseline, spacing: LabSpacing.xs) {
                    Image(systemName: standing == .requested ? "clock.fill" : "checkmark.circle.fill")
                        .accessibilityHidden(true)
                    Text(verbatim: status)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(standing == .requested ? theme.secondaryLabel : theme.text(.positive))
            } else {
                Button(action: onRefund) {
                    Text(verbatim: "Yêu cầu hoàn tiền")
                }
                .buttonStyle(.labTonal)
                // Each row's button says which payment, for VoiceOver's list of buttons.
                .accessibilityLabel(Text(verbatim: "Yêu cầu hoàn tiền: \(title), \(line)"))
            }
        }
        .padding(.vertical, LabSpacing.xs)
    }
}

/// A row that opens something: icon, title, and a trailing hint, a chevron
/// inside the app, an arrow for a page outside it, as in `SettingsScreen`.
private struct HelpRowLabel: View {
    let title: String
    let icon: String
    let trailing: String
    @Environment(\.labTheme) private var theme

    var body: some View {
        HStack {
            Label {
                Text(verbatim: title)
            } icon: {
                SettingsIcon(icon)
            }
            .foregroundStyle(theme.label)
            Spacer()
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryLabel)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private extension RefundOutcome {
    /// How StoreKit says its refund sheet ended. An error newer than the
    /// kit (iOS 27's `ineligible`, say) fails with StoreKit's own words.
    init(_ result: Result<StoreKit.Transaction.RefundRequestStatus, StoreKit.Transaction.RefundRequestError>) {
        switch result {
        case let .success(status):
            switch status {
            case .success: self = .requested
            case .userCancelled: self = .cancelled
            @unknown default: self = .cancelled
            }
        case let .failure(error):
            self = error == .duplicateRequest ? .alreadyRequested : .failed(error.localizedDescription)
        }
    }
}
#endif
