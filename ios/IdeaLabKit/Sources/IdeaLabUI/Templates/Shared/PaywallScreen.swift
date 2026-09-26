#if os(iOS)
import IdeaLabCore
import SwiftUI

/// A paywall that passes App Review and does not trick anyone.
///
/// Built to Apple's subscription rules (Guideline 3.1.2 and the "Auto-renewable
/// subscriptions" sign-up requirements): the billed price is the biggest
/// price on screen, the renewal terms sit right above the button, Restore
/// Purchases, Terms and Privacy are always visible, and the close button is
/// never hidden or delayed. Photo cleaners in particular are notorious for
/// weekly plans hidden behind a trial; this layout makes a lifetime or yearly
/// plan the honest default.
///
/// Prices come from StoreKit via `PaywallPlan`; the purchase itself is yours
/// (StoreKit 2, RevenueCat...). For a zero-code alternative, StoreKit's own
/// `SubscriptionStoreView` (iOS 17+) is also App Review-safe.
public struct PaywallScreen: View {
    public struct Benefit: Identifiable, Hashable, Sendable {
        public var systemImage: String
        public var title: String
        public var detail: String
        public var id: String { title }

        public init(systemImage: String, title: String, detail: String) {
            self.systemImage = systemImage
            self.title = title
            self.detail = detail
        }
    }

    private let systemImage: String
    private let title: String
    private let subtitle: String
    private let benefits: [Benefit]
    private let plans: [PaywallPlan]
    private let preselectedPlanID: PaywallPlan.ID?
    private let termsURL: URL
    private let privacyURL: URL
    private let onPurchase: @MainActor (PaywallPlan) async -> Void
    private let onRestore: @MainActor () async -> Void
    private let onClose: () -> Void

    /// The plan the user tapped, if any.
    @State private var selectedID: PaywallPlan.ID?
    @State private var isWorking = false
    @Environment(\.labTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        systemImage: String,
        title: String,
        subtitle: String,
        benefits: [Benefit],
        plans: [PaywallPlan],
        preselectedPlanID: PaywallPlan.ID? = nil,
        termsURL: URL,
        privacyURL: URL,
        onPurchase: @escaping @MainActor (PaywallPlan) async -> Void,
        onRestore: @escaping @MainActor () async -> Void,
        onClose: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.benefits = benefits
        self.plans = plans
        self.preselectedPlanID = preselectedPlanID
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.onPurchase = onPurchase
        self.onRestore = onRestore
        self.onClose = onClose
    }

    /// The tapped plan while it is still on offer, else the preselected one,
    /// else the first. Worked out from the current `plans` every time:
    /// StoreKit products usually arrive after the screen appears, and a
    /// choice fixed at creation would stay empty (or stale) for good.
    private var selected: PaywallPlan? {
        plans.first { $0.id == selectedID }
            ?? plans.first { $0.id == preselectedPlanID }
            ?? plans.first
    }

    /// At accessibility sizes the full terms and the links would fill the
    /// pinned bar and hide the plans, so they move into the scrolling
    /// content. The billed price and what happens after the trial never move:
    /// a short price line stays pinned right above the button at every size.
    private var pinsTerms: Bool { !typeSize.isAccessibilitySize }

    public var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.lg) {
                hero
                benefitList
                planList
                if !pinsTerms {
                    VStack(spacing: LabSpacing.sm) {
                        terms
                        links
                    }
                }
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.bottom, LabSpacing.md)
        }
        .background(alignment: .top) {
            PaywallBackdrop()
                .frame(height: 300)
                .ignoresSafeArea(edges: .top)
        }
        .background(theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseBar
                .labBottomBar()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(theme.label)
                    .frame(width: 44, height: 44)
                    .labGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Đóng"))
            .padding(LabSpacing.sm)
        }
    }

    private var hero: some View {
        VStack(spacing: LabSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(theme.onFill)
                .frame(width: 96, height: 96)
                .background(theme.fill(.accent), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            Text(verbatim: subtitle)
                .font(.body)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 56)
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: LabSpacing.md) {
            ForEach(benefits) { benefit in
                HStack(alignment: .top, spacing: LabSpacing.sm) {
                    Image(systemName: benefit.systemImage)
                        .font(.headline)
                        .foregroundStyle(theme.accentText)
                        .frame(width: 40, height: 40)
                        .background(theme.tonalFill(.accent), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: benefit.title)
                            .font(.headline)
                            .foregroundStyle(theme.label)
                        Text(verbatim: benefit.detail)
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .labCard()
    }

    private var planList: some View {
        VStack(spacing: LabSpacing.sm) {
            ForEach(plans) { plan in
                PlanCard(plan: plan, isSelected: plan.id == selected?.id) {
                    selectedID = plan.id
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    @ViewBuilder
    private var terms: some View {
        if let selected {
            Text(verbatim: PaywallCopy.terms(for: selected))
                .font(.footnote)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LabSpacing.xxs) {
                restoreButton
                Text(verbatim: "·").accessibilityHidden(true)
                Link(destination: termsURL) { Text(verbatim: "Điều khoản") }
                Text(verbatim: "·").accessibilityHidden(true)
                Link(destination: privacyURL) { Text(verbatim: "Quyền riêng tư") }
            }
            VStack(spacing: LabSpacing.xxs) {
                restoreButton
                Link(destination: termsURL) { Text(verbatim: "Điều khoản") }
                    .frame(minHeight: 44)
                Link(destination: privacyURL) { Text(verbatim: "Quyền riêng tư") }
                    .frame(minHeight: 44)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(theme.secondaryLabel)
        .tint(theme.accentText)
        .frame(minHeight: 44)
    }

    private var restoreButton: some View {
        Button {
            guard !isWorking else { return }
            // Set before the task starts: a second tap in between must not
            // start a second restore.
            isWorking = true
            Task {
                await onRestore()
                isWorking = false
            }
        } label: {
            Text(verbatim: "Khôi phục mua hàng")
        }
        .disabled(isWorking)
        .frame(minHeight: 44)
    }

    private var purchaseBar: some View {
        VStack(spacing: LabSpacing.xs) {
            if pinsTerms {
                terms
            } else if let selected {
                Text(verbatim: PaywallCopy.priceLine(for: selected))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard let selected, !isWorking else { return }
                // Set before the task starts: a second tap in between must not
                // open a second purchase.
                isWorking = true
                Task {
                    await onPurchase(selected)
                    isWorking = false
                }
            } label: {
                ZStack {
                    Text(verbatim: selected.map(PaywallCopy.callToAction(for:)) ?? "Chọn một gói")
                        .opacity(isWorking ? 0 : 1)
                    if isWorking {
                        ProgressView().tint(theme.onFill)
                    }
                }
            }
            .buttonStyle(.labFilled)
            .disabled(selected == nil || isWorking)

            if pinsTerms {
                links
            }
        }
        .padding(.horizontal, LabSpacing.md)
        .padding(.top, LabSpacing.sm)
        .padding(.bottom, pinsTerms ? 0 : LabSpacing.xs)
        .background(theme.canvas)
    }
}

/// Wording for the paywall, in one place so it can be localised and reviewed.
public enum PaywallCopy {
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
    public static func priceLine(for plan: PaywallPlan) -> String {
        let price = plan.displayPrice + perTerm(plan.term)
        switch (plan.term, plan.freeTrialDays) {
        case (.lifetime, _):
            return "Trả một lần \(plan.displayPrice)"
        case (_, .some(let days)) where days > 0:
            return "Miễn phí \(days) ngày, sau đó \(price)"
        default:
            return "\(price), tự động gia hạn"
        }
    }

    /// The renewal terms Apple requires next to the purchase button.
    public static func terms(for plan: PaywallPlan) -> String {
        let price = plan.displayPrice + perTerm(plan.term)
        switch (plan.term, plan.freeTrialDays) {
        case (.lifetime, _):
            return "Thanh toán một lần \(plan.displayPrice), dùng mãi mãi. Không tự động gia hạn."
        case (_, .some(let days)) where days > 0:
            return "Miễn phí \(days) ngày, sau đó \(price). Tự động gia hạn, huỷ bất cứ lúc nào trong Cài đặt."
        default:
            return "\(price), tự động gia hạn. Huỷ bất cứ lúc nào trong Cài đặt."
        }
    }

    /// The button says what happens and what it costs.
    public static func callToAction(for plan: PaywallPlan) -> String {
        switch (plan.term, plan.freeTrialDays) {
        case (.lifetime, _):
            return "Mua một lần · \(plan.displayPrice)"
        case (_, .some(let days)) where days > 0:
            return "Dùng thử miễn phí \(days) ngày"
        default:
            return "Đăng ký · \(plan.displayPrice)\(perTerm(plan.term))"
        }
    }
}

private struct PlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.labTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LabRadius.lg, style: .continuous)
        Button {
            onSelect()
        } label: {
            HStack(spacing: LabSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? theme.accentText : theme.secondaryLabel)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // The badge gets its own line: squeezed next to the title
                    // it wrapped into a three-line pill.
                    if let badge = plan.badge {
                        Text(verbatim: badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.onFill)
                            .padding(.horizontal, LabSpacing.xs)
                            .padding(.vertical, 3)
                            .background(theme.fill(.positive), in: Capsule())
                            .fixedSize()
                            .padding(.bottom, 2)
                    }
                    Text(verbatim: plan.title)
                        .font(.headline)
                        .foregroundStyle(theme.label)
                    if let detail = plan.detail {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
                Spacer(minLength: LabSpacing.xs)
                Text(verbatim: plan.displayPrice + PaywallCopy.perTerm(plan.term))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.trailing)
            }
            .padding(LabSpacing.md)
            .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight + LabSpacing.lg)
            .background(isSelected ? theme.tonalFill(.accent) : theme.surface, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? theme.accentText : theme.separator, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Soft brand-coloured glow behind the paywall header: a mesh gradient on
/// iOS 18+, a plain gradient before. Full-strength colour only sits behind
/// the icon; from the title down it is the pale tonal fill fading into the
/// canvas, so the title and subtitle keep their tested contrast.
private struct PaywallBackdrop: View {
    @Environment(\.labTheme) private var theme

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.45], [0.65, 0.4], [1, 0.45],
                        [0, 1], [0.5, 1], [1, 1],
                    ],
                    colors: [
                        theme.fill(.accent), theme.fill(.accent).opacity(0.7), theme.tonalFill(.positive),
                        theme.tonalFill(.accent), theme.tonalFill(.accent), theme.tonalFill(.accent),
                        theme.canvas, theme.canvas, theme.canvas,
                    ]
                )
            } else {
                LinearGradient(
                    stops: [
                        .init(color: theme.fill(.accent).opacity(0.7), location: 0),
                        .init(color: theme.tonalFill(.accent), location: 0.45),
                        .init(color: theme.canvas, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
