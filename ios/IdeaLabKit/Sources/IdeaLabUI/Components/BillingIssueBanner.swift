#if os(iOS)
import IdeaLabCore
// For the App Store's own page of the customer's subscriptions.
import StoreKit
import SwiftUI

/// Tells the customer that the App Store could not charge for the renewal
/// of their subscription, and what to do, on an amber card like a caution
/// sign with the one button that fixes it: "Cập nhật thanh toán" opens
/// Apple's page for the payment methods of their account
/// (`StoreLinks.billing`); for someone who bought the plan kept for good,
/// "Quản lý gói đăng ký" opens the App Store's page for their
/// subscriptions, to cancel it.
///
/// Show it where the customer looks for their plan, in Settings
/// (`SettingsScreen(billingNotice:)`) or on the home screen, from
/// `StoreCopy.billingNotice(for:plans:)`. The App Store shows a sheet of its
/// own about it at launch (StoreKit's `Message`, reason `billingIssue`);
/// this card stays until the issue is fixed.
public struct BillingIssueBanner: View {
    private let notice: BillingNotice
    @State private var managesSubscriptions = false
    @Environment(\.labTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(notice: BillingNotice) {
        self.notice = notice
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous)
        // At accessibility sizes the icon goes above the words, which then
        // have the whole card's width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LabSpacing.sm))
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            layout {
                Image(systemName: "creditcard.fill")
                    .font(.headline)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                    Text(verbatim: notice.title)
                        .font(.headline)
                    Text(verbatim: notice.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(theme.onWarningFill)
            .accessibilityElement(children: .combine)
            // Dark on amber, like the caregiver's late-dose card: the brand's
            // colour on amber would clash.
            Button {
                act()
            } label: {
                Text(verbatim: notice.actionTitle)
                    .font(.headline)
                    .foregroundStyle(theme.warningFill)
                    .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
                    .background(theme.onWarningFill, in: shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
        }
        .padding(LabSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warningFill, in: RoundedRectangle(cornerRadius: LabRadius.lg, style: .continuous))
        .manageSubscriptionsSheet(isPresented: $managesSubscriptions)
    }

    private func act() {
        switch notice.action {
        case .manageSubscriptions:
            managesSubscriptions = true
        case .updatePayment, .purchase, .nothing:
            openURL(StoreLinks.billing)
        }
    }
}
#endif
