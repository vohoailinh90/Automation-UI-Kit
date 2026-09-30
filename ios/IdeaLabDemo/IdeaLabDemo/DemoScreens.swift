import IdeaLabCore
import IdeaLabStore
import IdeaLabUI
import StoreKit
import SwiftUI

/// Every screen the demo can open directly. The raw values are the ids that
/// `ios/scripts/render-previews.sh` passes as `-screen`; keep the two in sync.
enum DemoScreen: String, CaseIterable, Identifiable {
    case tokens
    case components
    case ledgerHome = "ledger-home"
    case ledgerEntry = "ledger-entry"
    case ledgerReport = "ledger-report"
    case ledgerExportPDF = "ledger-export-pdf"
    case ledgerExportSpreadsheet = "ledger-export-xlsx"
    case medsToday = "meds-today"
    case medsAssistive = "meds-assistive"
    case medsCaregiver = "meds-caregiver"
    case medsAdd = "meds-add"
    case medsEdit = "meds-edit"
    case medsAlerts = "meds-alerts"
    case cleanerHome = "cleaner-home"
    case cleanerSwipe = "cleaner-swipe"
    case cleanerReview = "cleaner-review"
    case cleanerSimilar = "cleaner-similar"
    case cleanerDone = "cleaner-done"
    case cleanerPaywall = "cleaner-paywall"
    case cleanerLibrary = "cleaner-library"
    case cleanerMeasured = "cleaner-measured"
    case cleanerMeasuredHome = "cleaner-measured-home"
    case onboarding
    case permission
    case paywall
    case paywallSubscriber = "paywall-subscriber"
    case paywallBillingIssue = "paywall-billing-issue"
    case paywallBillingLegacy = "paywall-billing-legacy"
    case paywallWinBack = "paywall-win-back"
    case settings
    case settingsBillingIssue = "settings-billing-issue"
    case purchaseHelp = "purchase-help"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: "Màu & chữ"
        case .components: "Thành phần"
        case .ledgerHome: "Trang chủ sổ"
        case .ledgerEntry: "Nhập nhanh 10 giây"
        case .ledgerReport: "Báo cáo tháng/quý"
        case .ledgerExportPDF: "Xuất sổ: bản PDF (A4)"
        case .ledgerExportSpreadsheet: "Xuất sổ: bảng Excel"
        case .medsToday: "Cha mẹ: ĐÃ UỐNG"
        case .medsAssistive: "Cha mẹ: Assistive Access"
        case .medsCaregiver: "Con: theo dõi"
        case .medsAdd: "Con: thêm thuốc"
        case .medsEdit: "Con: sửa thuốc"
        case .medsAlerts: "Con: báo khi quên thuốc"
        case .cleanerHome: "Trang chủ dọn ảnh"
        case .cleanerSwipe: "Vuốt giữ/xoá"
        case .cleanerReview: "Xem lại trước khi xoá"
        case .cleanerSimilar: "Ảnh gần giống: giữ tấm nét nhất"
        case .cleanerDone: "Xong"
        case .cleanerPaywall: "Paywall mua một lần"
        case .cleanerLibrary: "Ảnh thật trên máy: PhotoKit + Vision"
        case .cleanerMeasured: "Đo thật trên ảnh mẫu: Vision"
        case .cleanerMeasuredHome: "Nhận ra trên ảnh mẫu: mã QR, giấy tờ"
        case .onboarding: "Giới thiệu"
        case .permission: "Xin quyền"
        case .paywall: "Paywall"
        case .paywallSubscriber: "Paywall: đang dùng gói tháng"
        case .paywallBillingIssue: "Paywall: chưa gia hạn được"
        case .paywallBillingLegacy: "Paywall: gói cũ tạm dừng"
        case .paywallWinBack: "Paywall: mời quay lại"
        case .settings: "Cài đặt"
        case .settingsBillingIssue: "Cài đặt: gói tạm dừng"
        case .purchaseHelp: "Trợ giúp mua hàng, hoàn tiền"
        }
    }

    var navigationTitle: String {
        switch self {
        case .ledgerHome: "Sổ thu chi"
        case .ledgerReport: "Báo cáo"
        case .ledgerExportPDF: "Bản PDF"
        case .ledgerExportSpreadsheet: "Bảng Excel"
        case .medsToday: "Thuốc của Mẹ"
        case .medsAssistive: "Uống thuốc"
        case .medsCaregiver, .medsAdd, .medsEdit, .medsAlerts: "Mẹ"
        case .cleanerHome, .cleanerLibrary, .cleanerMeasuredHome: "Dọn ảnh"
        case .cleanerSwipe: "Ảnh chụp màn hình"
        case .cleanerReview: "Xem lại"
        case .cleanerSimilar, .cleanerMeasured: "Ảnh gần giống"
        case .settings, .settingsBillingIssue: "Cài đặt"
        case .purchaseHelp: "Trợ giúp mua hàng"
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .tokens: "paintpalette"
        case .components: "square.grid.2x2"
        case .ledgerHome: "book.closed"
        case .ledgerEntry: "plus.forwardslash.minus"
        case .ledgerReport: "chart.bar.xaxis"
        case .ledgerExportPDF: "doc.richtext"
        case .ledgerExportSpreadsheet: "tablecells"
        case .medsToday: "pills"
        case .medsAssistive: "hand.tap"
        case .medsCaregiver: "person.2"
        case .medsAdd: "plus.circle"
        case .medsEdit: "pencil.circle"
        case .medsAlerts: "bell.and.waves.left.and.right"
        case .cleanerHome: "sparkles"
        case .cleanerSwipe: "hand.draw"
        case .cleanerReview: "square.grid.3x3"
        case .cleanerSimilar: "square.on.square"
        case .cleanerDone: "checkmark.seal"
        case .cleanerPaywall: "cart"
        case .cleanerLibrary: "photo.stack"
        case .cleanerMeasured: "wand.and.rays"
        case .cleanerMeasuredHome: "qrcode.viewfinder"
        case .onboarding: "hand.wave"
        case .permission: "bell.badge"
        case .paywall: "star"
        case .paywallSubscriber: "arrow.up.circle"
        case .paywallBillingIssue: "creditcard"
        case .paywallBillingLegacy: "creditcard.trianglebadge.exclamationmark"
        case .paywallWinBack: "arrow.uturn.backward.circle"
        case .settings: "gearshape"
        case .settingsBillingIssue: "exclamationmark.triangle"
        case .purchaseHelp: "cart.badge.questionmark"
        }
    }

    /// Whether the screen tells the screenshots itself that it is ready
    /// (`DemoLaunch.markReady`), later than when it appears: a screen that
    /// opens a sheet over another is up once the sheet is, so the sheet
    /// tells them, not the screen under it; the photo screens are up once
    /// their photos are sorted, and the exports once written and shown.
    var saysWhenReady: Bool {
        switch self {
        case .ledgerEntry, .ledgerExportPDF, .ledgerExportSpreadsheet, .medsAdd, .medsEdit, .medsAlerts,
             .cleanerLibrary, .cleanerMeasured, .cleanerMeasuredHome: true
        default: false
        }
    }

    @MainActor @ViewBuilder
    func destination(store: DemoLedgerStore, meds: DemoMedsStore, cleaner: DemoCleanerStore, largeText: Binding<Bool>) -> some View {
        switch self {
        case .tokens:
            TokensScreen()
        case .components:
            ComponentsScreen()
        case .ledgerHome:
            LedgerHomeDemo(store: store)
        case .ledgerEntry:
            // Shown over the home screen, the way the app presents it.
            LedgerHomeDemo(store: store, presenting: .income)
        case .ledgerReport:
            LedgerReportDemo(store: store)
        case .ledgerExportPDF:
            // What the report's PDF button shares: this month, in A4.
            LedgerPDFDemo(store: store)
        case .ledgerExportSpreadsheet:
            // What the Excel button shares, as Files and Mail preview it.
            LedgerSpreadsheetDemo(store: store)
        case .medsToday:
            // Always in the meds theme: teal, senior density.
            MedsTodayDemo(store: meds)
                .labTheme(.meds)
        case .medsAssistive:
            // What the app's AssistiveAccess scene shows (iOS 26), here in
            // the gallery: the look without the mode's own frame.
            MedsAssistiveDemo(store: meds)
                .labTheme(.meds)
        case .medsCaregiver:
            MedsCaregiverDemo(store: meds)
                .labTheme(.meds)
        case .medsAdd:
            // Over the family's screen: the grown-up child sets the medicines up.
            MedsCaregiverDemo(store: meds, sheet: .add(MedsCaregiverDemo.sampleDraft))
                .labTheme(.meds)
        case .medsEdit:
            // The doctor doubled the blood pressure pill: from tomorrow.
            MedsCaregiverDemo(store: meds, sheet: MedsCaregiverDemo.sampleEdit)
                .labTheme(.meds)
        case .medsAlerts:
            // From the card that says this phone would not speak up yet.
            MedsCaregiverDemo(store: meds, sheet: .alerts)
                .labTheme(.meds)
        case .cleanerHome:
            // Always in the cleaner theme: violet, regular density.
            CleanerHomeScreen(
                storage: cleaner.storage,
                summaries: cleaner.summaries,
                allowance: cleaner.allowance,
                onOpen: { _ in },
                onUpgrade: {}
            )
            .labTheme(.cleaner)
        case .cleanerSwipe:
            CleanerSwipeDemo(store: cleaner)
                .labTheme(.cleaner)
        case .cleanerReview:
            CleanerReviewDemo(store: cleaner)
                .labTheme(.cleaner)
        case .cleanerSimilar:
            CleanerSimilarDemo(store: cleaner)
                .labTheme(.cleaner)
        case .cleanerDone:
            CleanupDoneScreen(deletedCount: cleaner.deletedCount, bytesFreed: cleaner.bytesFreed, onOpenPhotos: {}, onContinue: {})
                .labTheme(.cleaner)
        case .cleanerPaywall:
            // The idea's promise: buy once, no weekly plan behind a trial.
            PaywallScreen(
                systemImage: "sparkles",
                title: "Dọn ảnh — bản đầy đủ",
                subtitle: "Mua một lần, dùng mãi mãi. Không gói tuần, không tự gia hạn.",
                benefits: DemoContent.cleanerBenefits,
                plans: DemoContent.cleanerPlans,
                preselectedPlanID: "cleaner.lifetime",
                termsURL: DemoContent.termsURL,
                privacyURL: DemoContent.privacyURL,
                onPurchase: { _ in },
                onRestore: {},
                onClose: {}
            )
            .toolbar(.hidden, for: .navigationBar)
            .labTheme(.cleaner)
        case .cleanerLibrary:
            // The phone's own photos, after asking for them.
            CleanerLibraryDemo()
                .labTheme(.cleaner)
        case .cleanerMeasured:
            // Sample photos in memory, measured and grouped for real.
            CleanerMeasuredDemo()
                .labTheme(.cleaner)
        case .cleanerMeasuredHome:
            // The same samples: what Vision recognised in them, on the home screen.
            CleanerMeasuredHomeDemo(storage: cleaner.storage)
                .labTheme(.cleaner)
        case .onboarding:
            OnboardingScreen(pages: DemoContent.onboarding) {}
                .toolbar(.hidden, for: .navigationBar)
        case .permission:
            // Voice needs no permission here (the keyboard's own dictation
            // key fills the note field); a daily reminder is what the ledger asks for.
            PermissionPrimerScreen(
                systemImage: "bell.badge.fill",
                title: "Nhắc ghi sổ cuối ngày",
                message: "Một thông báo lúc 20:00 nếu hôm nay bạn chưa ghi khoản nào.",
                reasons: DemoContent.notificationReasons,
                allowTitle: "Bật nhắc nhở",
                onAllow: {},
                onLater: {}
            )
            .toolbar(.hidden, for: .navigationBar)
        case .paywall:
            PaywallDemo(onClose: {})
                .toolbar(.hidden, for: .navigationBar)
        case .paywallSubscriber:
            // Someone on the monthly plan, from sample data: theirs says when
            // it renews, the yearly plan starts at once, and buying for good
            // says the monthly plan keeps renewing.
            PaywallScreen(
                systemImage: DemoContent.proSymbol,
                title: DemoContent.proTitle,
                subtitle: DemoContent.proSubtitle,
                benefits: DemoContent.paywallBenefits,
                plans: DemoContent.subscriberPlans,
                preselectedPlanID: "pro.yearly",
                termsURL: DemoContent.termsURL,
                privacyURL: DemoContent.privacyURL,
                onPurchase: { _ in },
                onRestore: {},
                onClose: {}
            )
            .toolbar(.hidden, for: .navigationBar)
        case .paywallBillingIssue:
            // The monthly plan's renewal failed, from sample data: in its
            // grace period, chosen first although yearly is preselected,
            // and its button opens Apple's page for the payment methods.
            PaywallScreen(
                systemImage: DemoContent.proSymbol,
                title: DemoContent.proTitle,
                subtitle: DemoContent.proSubtitle,
                benefits: DemoContent.paywallBenefits,
                plans: DemoContent.gracePeriodPlans,
                preselectedPlanID: "pro.yearly",
                termsURL: DemoContent.termsURL,
                privacyURL: DemoContent.privacyURL,
                onPurchase: { _ in },
                onRestore: {},
                onClose: {}
            )
            .toolbar(.hidden, for: .navigationBar)
        case .paywallBillingLegacy:
            // A plan no longer on offer, on hold, from sample data: no card
            // tells it, so the banner above the benefits does, with the
            // button to Apple's page for the payment methods.
            PaywallScreen(
                systemImage: DemoContent.proSymbol,
                title: DemoContent.proTitle,
                subtitle: DemoContent.proSubtitle,
                benefits: DemoContent.paywallBenefits,
                plans: DemoContent.legacyOnHoldPlans,
                preselectedPlanID: "pro.yearly",
                billingNotice: DemoContent.legacyOnHoldNotice,
                termsURL: DemoContent.termsURL,
                privacyURL: DemoContent.privacyURL,
                onPurchase: { _ in },
                onRestore: {},
                onClose: {}
            )
            .toolbar(.hidden, for: .navigationBar)
        case .paywallWinBack:
            // A subscription that is over, from sample data: the App Store
            // offers three months at a lower price to come back, which the
            // monthly plan carries, chosen first although yearly is
            // preselected.
            PaywallScreen(
                systemImage: DemoContent.proSymbol,
                title: DemoContent.proTitle,
                subtitle: DemoContent.proSubtitle,
                benefits: DemoContent.paywallBenefits,
                plans: DemoContent.winBackPlans,
                preselectedPlanID: "pro.yearly",
                termsURL: DemoContent.termsURL,
                privacyURL: DemoContent.privacyURL,
                onPurchase: { _ in },
                onRestore: {},
                onClose: {}
            )
            .toolbar(.hidden, for: .navigationBar)
        case .settings:
            SettingsDemo(largeText: largeText)
        case .settingsBillingIssue:
            // Past the grace period, from sample data: Pro on hold.
            SettingsDemo(largeText: largeText, sample: DemoContent.onHoldNotice)
        case .purchaseHelp:
            PurchaseHelpDemo()
        }
    }
}

/// The Pro paywall on `LabStore`: the App Store's plans (run from Xcode
/// with a StoreKit configuration file, see the README), and while there are
/// none, the paywall says it is loading them or offers to try again. Only
/// the screenshots, which have no App Store, show the sample plans. Buying
/// or restoring says how it went in a toast, and an offer code redeemed
/// (from "Nhập mã ưu đãi", or elsewhere while it is open) is welcomed.
struct PaywallDemo: View {
    let onClose: () -> Void
    @Environment(LabStore.self) private var store
    @Environment(\.purchase) private var purchase
    @Environment(\.calendar) private var calendar
    @State private var toast: LabToastMessage?

    private var isScreenshot: Bool { DemoLaunch.screen != nil }

    private var plans: [PaywallPlan] {
        isScreenshot ? DemoContent.plans : store.plans.map(DemoContent.described)
    }

    var body: some View {
        PaywallScreen(
            systemImage: DemoContent.proSymbol,
            title: DemoContent.proTitle,
            subtitle: DemoContent.proSubtitle,
            benefits: DemoContent.paywallBenefits,
            plans: plans,
            preselectedPlanID: "pro.yearly",
            billingNotice: StoreCopy.billingNotice(for: store.customer, plans: plans, calendar: calendar),
            isLoadingPlans: store.loadState == .idle || store.loadState == .loading,
            onReloadPlans: {
                Task { await store.loadProducts() }
            },
            termsURL: DemoContent.termsURL,
            privacyURL: DemoContent.privacyURL,
            onPurchase: { plan in
                let outcome = await store.purchase(plan, with: purchase)
                toast = StoreCopy.purchaseMessage(for: outcome, plans: plans, calendar: calendar).map { LabToastMessage($0) }
            },
            onRestore: {
                let outcome = await store.restore()
                toast = StoreCopy.restoreMessage(for: outcome, plans: plans).map { LabToastMessage($0) }
            },
            onRedeemOfferCode: { error in
                if let error {
                    toast = LabToastMessage(StoreCopy.offerCodeFailure(error.localizedDescription))
                }
            },
            onClose: onClose
        )
        .labToast($toast)
        .welcomesRedemptions(from: store, plans: plans, toast: $toast)
        .task {
            if !isScreenshot {
                await store.loadProducts()
            }
        }
    }
}

/// Settings with an account, so the deletion row shows. The demo has no
/// account to delete, and says so instead of pretending. Pro, and a renewal
/// the App Store could not charge for, come from `LabStore`, which loads the
/// products for it; "Nâng cấp" opens the paywall, "Khôi phục" asks the App
/// Store, "Nhập mã ưu đãi" opens its sheet for offer codes, and "Trợ giúp
/// mua hàng" the help with purchases. A sample notice, with Pro on hold,
/// stands in for the App Store's when given.
struct SettingsDemo: View {
    @Binding var largeText: Bool
    var sample: BillingNotice?
    @Environment(LabStore.self) private var store
    @Environment(\.calendar) private var calendar
    @State private var showsNoAccount = false
    @State private var showsPaywall = false
    @State private var showsPurchaseHelp = false
    @State private var toast: LabToastMessage?

    private var isScreenshot: Bool { DemoLaunch.screen != nil }

    var body: some View {
        SettingsScreen(
            isPro: sample == nil && store.owns(anyOf: DemoContent.proProductIDs),
            billingNotice: sample ?? StoreCopy.billingNotice(for: store.customer, plans: store.plans, calendar: calendar),
            largeText: $largeText,
            privacyURL: DemoContent.privacyURL,
            termsURL: DemoContent.termsURL,
            appVersion: "0.1.0 (1)",
            onUpgrade: { showsPaywall = true },
            onRestore: {
                Task {
                    let outcome = await store.restore()
                    toast = StoreCopy.restoreMessage(for: outcome, plans: store.plans).map { LabToastMessage($0) }
                }
            },
            onRedeemOfferCode: { error in
                if let error {
                    toast = LabToastMessage(StoreCopy.offerCodeFailure(error.localizedDescription))
                }
            },
            onPurchaseHelp: { showsPurchaseHelp = true },
            onExport: {},
            onContact: {},
            onDeleteAccount: { showsNoAccount = true }
        )
        .labToast($toast)
        // The paywall, when open over this screen, welcomes them itself.
        .welcomesRedemptions(from: store, plans: store.plans, isActive: !showsPaywall, toast: $toast)
        .task {
            // The subscriptions, and so the notice, need the products.
            if sample == nil, !isScreenshot {
                await store.loadProducts()
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallDemo { showsPaywall = false }
        }
        .navigationDestination(isPresented: $showsPurchaseHelp) {
            PurchaseHelpDemo()
                .navigationTitle(DemoScreen.purchaseHelp.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
        .alert(Text(verbatim: "Bản demo không có tài khoản"), isPresented: $showsNoAccount) {
            Button(role: .cancel) {} label: { Text(verbatim: "OK") }
        } message: {
            Text(verbatim: "Trong app thật, đây là lúc xoá tài khoản và dữ liệu đồng bộ, rồi đăng xuất.")
        }
    }
}

/// Help with purchases on `LabStore`: the customer's payments as StoreKit
/// records them (run from Xcode with the StoreKit configuration file, whose
/// test environment grants a refund request at once), and in the
/// screenshots, which have no App Store, a sample customer's. "Yêu cầu hoàn
/// tiền" opens the App Store's sheet; how it ended is kept, and said in a
/// toast, as are restores.
struct PurchaseHelpDemo: View {
    @Environment(LabStore.self) private var store
    @State private var toast: LabToastMessage?

    private var isScreenshot: Bool { DemoLaunch.screen != nil }

    var body: some View {
        PurchaseHelpScreen(
            purchases: isScreenshot ? DemoContent.purchases : store.purchases,
            refundRequests: isScreenshot ? DemoContent.refundRequests : store.refundRequests,
            plans: store.plans,
            onRestore: {
                Task {
                    let outcome = await store.restore()
                    toast = StoreCopy.restoreMessage(for: outcome, plans: store.plans).map { LabToastMessage($0) }
                }
            },
            onContact: {},
            onRefund: { purchase, outcome in
                store.refundRequestEnded(outcome, for: purchase)
                toast = StoreCopy.refundMessage(for: outcome).map { LabToastMessage($0) }
            }
        )
        .labToast($toast)
        .task {
            if !isScreenshot {
                await store.loadPurchases()
            }
        }
    }
}

extension View {
    /// Welcomes the customer to an offer code they redeemed
    /// (`LabStore.redemption`) with a toast, while `isActive`: when it comes,
    /// and when this screen comes back to the front with one still waiting.
    /// The store then no longer keeps it (`welcomed(_:)`).
    func welcomesRedemptions(
        from store: LabStore, plans: [PaywallPlan], isActive: Bool = true, toast: Binding<LabToastMessage?>
    ) -> some View {
        modifier(WelcomesRedemptions(store: store, plans: plans, isActive: isActive, toast: toast))
    }
}

private struct WelcomesRedemptions: ViewModifier {
    let store: LabStore
    let plans: [PaywallPlan]
    let isActive: Bool
    @Binding var toast: LabToastMessage?

    func body(content: Content) -> some View {
        content
            .onAppear { welcome() }
            .onChange(of: store.redemption) { welcome() }
            .onChange(of: isActive) { welcome() }
    }

    private func welcome() {
        guard isActive, let redemption = store.redemption else { return }
        toast = LabToastMessage(StoreCopy.redeemMessage(for: redemption, plans: plans))
        store.welcomed(redemption)
    }
}

/// Home wired to the demo store: the sheet, the toast and undo all work. An
/// entry asked for from outside the app (a control, Siri, a shortcut) opens
/// its sheet here, never over a half-written one (`QuickEntryRouter`).
struct LedgerHomeDemo: View {
    @Bindable var store: DemoLedgerStore
    @State private var presenting: LedgerEntry.Kind?
    private let quickEntry = QuickEntryRouter.shared

    init(store: DemoLedgerStore, presenting: LedgerEntry.Kind? = nil) {
        self.store = store
        _presenting = State(initialValue: presenting)
    }

    var body: some View {
        LedgerHomeScreen(
            entries: store.entries,
            now: store.now,
            calendar: store.calendar,
            readsBack: $store.readsBack,
            onAdd: { kind in presenting = kind }
        )
        .sheet(item: $presenting, onDismiss: takeRequest) { kind in
            QuickEntryScreen(
                kind: kind,
                date: store.now,
                calendar: store.calendar,
                onSave: { entry in
                    store.add(entry)
                    presenting = nil
                },
                onCancel: { presenting = nil }
            )
            // Ten seconds to write down a sale: the App Store's sheets wait.
            .holdsStoreMessages()
            .onAppear { DemoLaunch.markReady() }
        }
        .labToast($store.toast) { _ in store.undoLastSave() }
        .onAppear(perform: takeRequest)
        .onChange(of: quickEntry.pending) { takeRequest() }
    }

    /// Opens the sheet an entry asked for from outside the app, if any: now
    /// with no sheet open, else once the open one closes (`onDismiss`).
    private func takeRequest() {
        if let kind = quickEntry.take(showing: presenting) {
            presenting = kind
        }
    }
}

/// What the family's screen has open over it.
enum MedsSheet: Identifiable {
    /// "Thêm thuốc", filled in with this draft.
    case add(MedicationDraft)
    /// "Sửa thuốc" for this medicine (its `seriesID`), from this draft
    /// rather than the medicine as it is, if one is given.
    case edit(UUID, draft: MedicationDraft?)
    /// Why this phone should speak up when a dose goes late, before iOS asks.
    case alerts

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(seriesID, _): "edit \(seriesID)"
        case .alerts: "alerts"
        }
    }
}

/// The family's screen wired to the demo store: "+" adds a medicine, and each
/// one under "Thuốc của Mẹ" opens "Sửa thuốc".
struct MedsCaregiverDemo: View {
    @Bindable var store: DemoMedsStore
    /// The sheet open over the screen; `nil` while closed.
    @State private var sheet: MedsSheet?

    init(store: DemoMedsStore, sheet: MedsSheet? = nil) {
        self.store = store
        _sheet = State(initialValue: sheet)
    }

    /// Half filled in, so the screenshot shows a two-coloured capsule, two
    /// times and a course of days.
    static let sampleDraft = MedicationDraft(
        name: "Thuốc dạ dày",
        instructions: "Trước ăn",
        style: PillStyle(shape: .capsule, color: .orange, secondColor: .cream),
        times: [TimeOfDay(hour: 6, minute: 30), TimeOfDay(hour: 18)],
        course: .days(14)
    )

    /// The blood pressure pill at 2 viên: the screenshot shows the change
    /// waiting for tomorrow.
    static var sampleEdit: MedsSheet {
        var draft = MedicationDraft(editing: MedicationSamples.bloodPressure)
        draft.dose = "2 viên"
        return .edit(MedicationSamples.bloodPressure.seriesID, draft: draft)
    }

    var body: some View {
        TimelineView(.periodic(from: store.started, by: 60)) { context in
            CaregiverScreen(
                personName: "Mẹ",
                medications: store.medications,
                log: store.log,
                now: store.now(at: context.date),
                calendar: store.calendar,
                updatedAt: store.updatedAt,
                remindedAt: store.remindedAt,
                onCall: {},
                onRemind: { dose in store.remind(dose) },
                onAdd: { sheet = .add(MedicationDraft()) },
                onEdit: { medication in sheet = .edit(medication.seriesID, draft: nil) },
                alerts: store.alerts,
                // The demo is only ever "not asked yet"; an app opens
                // Settings for the other states (`DoseNotifications.openSettings()`).
                onAlerts: { sheet = .alerts }
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheet = .add(MedicationDraft())
                } label: {
                    Label("Thêm thuốc", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheet) { open in
            Group {
                switch open {
                case let .add(draft):
                    AddMedicationScreen(
                        draft: draft,
                        now: { store.now() },
                        calendar: store.calendar,
                        onSave: { medication in
                            store.add(medication)
                            sheet = nil
                        },
                        onCancel: { sheet = nil }
                    )
                case let .edit(seriesID, draft):
                    AddMedicationScreen(
                        editing: seriesID,
                        in: store.medications,
                        draft: draft,
                        now: { store.now() },
                        calendar: store.calendar,
                        onSave: { medications in
                            store.update(medications, changing: seriesID)
                            sheet = nil
                        },
                        onCancel: { sheet = nil }
                    )
                case .alerts:
                    PermissionPrimerScreen(
                        systemImage: "bell.badge.fill",
                        title: "Biết ngay khi Mẹ quên thuốc",
                        message: "Khi một liều trễ \(VietnameseDuration.string(DoseSchedule.grace)) mà Mẹ chưa xác nhận, máy bạn báo ngay để bạn kịp gọi Mẹ.",
                        reasons: DemoContent.medsAlertReasons,
                        allowTitle: "Bật thông báo",
                        onAllow: {
                            // An app asks iOS here: `await DoseNotifications.requestAccess()`.
                            store.alerts = .on
                            sheet = nil
                        },
                        onLater: { sheet = nil }
                    ) {
                        if let example = store.exampleAlert {
                            DoseAlertBanner(example)
                        }
                    }
                }
            }
            .labTheme(.meds)
            .defaultScrollAnchor(DemoLaunch.scrollAnchor)
            .onAppear { DemoLaunch.markReady() }
        }
        .labToast($store.toast)
    }
}

/// The parent's Assistive Access screen wired to the demo store: "ĐÃ UỐNG"
/// records the dose, with no toast to answer — the screen says it itself.
struct MedsAssistiveDemo: View {
    @Bindable var store: DemoMedsStore

    var body: some View {
        TimelineView(.periodic(from: store.started, by: 60)) { context in
            MedsAssistiveScreen(
                medications: store.medications,
                log: store.log,
                now: store.now(at: context.date),
                calendar: store.calendar,
                onTaken: { dose in store.record(.taken, dose, toast: false) }
            )
        }
        // A parent answering a dose: the App Store's sheets wait.
        .holdsStoreMessages()
    }
}

/// The parent's screen wired to the demo store: "ĐÃ UỐNG" (or "Không uống
/// liều này") records the dose, confirms it with a toast, and "Hoàn tác" takes
/// it back.
struct MedsTodayDemo: View {
    @Bindable var store: DemoMedsStore

    var body: some View {
        TimelineView(.periodic(from: store.started, by: 60)) { context in
            MedsTodayScreen(
                medications: store.medications,
                log: store.log,
                now: store.now(at: context.date),
                calendar: store.calendar,
                onTaken: { dose in store.record(.taken, dose) },
                onSkipped: { dose in store.record(.skipped, dose) }
            )
        }
        // A parent answering a dose: the App Store's sheets wait.
        .holdsStoreMessages()
        .labToast($store.toast) { _ in store.undoLastRecord() }
    }
}

@Observable
@MainActor
final class DemoMedsStore {
    private(set) var medications = MedicationSamples.medications
    var log = MedicationSamples.log()
    var toast: LabToastMessage?
    private var lastRecorded: DoseID?

    let calendar = LedgerSamples.calendar
    /// When the demo started: its clock reads the sample's 09:41 then, and
    /// runs on from there, so doses turn due and late as they would. The
    /// screens tick a minute of it at a time.
    let started = Date.now
    /// When the log last changed, for the family's "Cập nhật" line: the
    /// sample is as of 09:41, and each answer here updates it.
    private(set) var updatedAt = LedgerSamples.referenceNow
    /// When each dose was last reminded, kept here so the family's ten-minute
    /// rule survives leaving and reopening their screen.
    private(set) var remindedAt: [DoseID: Date] = [:]
    /// What this phone lets the late-dose alerts do. The demo asks iOS
    /// nothing: "Bật thông báo" turns them on here.
    var alerts: DoseAlertAccess = .notAsked

    /// The family's first alert of a day, in the planner's own words.
    var exampleAlert: DoseAlert? {
        DoseAlerts.plan(
            for: .family(personName: "Mẹ"), medications: medications, log: DoseLog(),
            now: calendar.startOfDay(for: now()), calendar: calendar, limit: 1
        ).upcoming.first
    }

    func remind(_ dose: ScheduledDose) {
        remindedAt[dose.id] = now()
    }

    func add(_ medication: Medication) {
        medications.append(medication)
        toast = LabToastMessage(text: "Đã thêm \(medication.name)")
    }

    /// The list "Sửa thuốc" hands back: the medicine changed, or stopped.
    func update(_ medications: [Medication], changing seriesID: UUID) {
        // The new name after a rename; the one it had when stopping took the
        // medicine out of the list (one that had not started yet).
        let name = (MedicationChanges.latest(of: seriesID, in: medications)
            ?? MedicationChanges.latest(of: seriesID, in: self.medications))?.name ?? ""
        let stopped = !MedicationChanges.isInUse(seriesID, in: medications, at: now())
        self.medications = medications
        toast = LabToastMessage(text: stopped ? "Đã ngừng \(name)" : "Đã lưu \(name)")
    }

    func now(at date: Date = .now) -> Date {
        LedgerSamples.referenceNow.addingTimeInterval(max(date.timeIntervalSince(started), 0))
    }

    /// - Parameter toast: confirm it with a toast that offers "Hoàn tác".
    func record(_ outcome: DoseRecord.Outcome, _ dose: ScheduledDose, toast: Bool = true) {
        log.record(outcome, for: dose.id, at: now())
        updatedAt = now()
        lastRecorded = dose.id
        guard toast else { return }
        let text = outcome == .taken ? "Đã ghi nhận: \(dose.medication.name)" : "Đã ghi: bỏ qua \(dose.medication.name)"
        self.toast = LabToastMessage(text: text, actionTitle: "Hoàn tác")
    }

    func undoLastRecord() {
        guard let lastRecorded else { return }
        log.undo(lastRecorded, at: now())
        updatedAt = now()
        self.lastRecorded = nil
    }
}

enum DemoContent {
    static let termsURL = URL(string: "https://example.com/terms")!
    static let privacyURL = URL(string: "https://example.com/privacy")!

    static let onboarding: [OnboardingScreen.Page] = [
        .init(systemImage: "bolt.fill", title: "Ghi sổ trong 10 giây",
              message: "Bấm Thu hoặc Chi, gõ số tiền, bấm Lưu. Không cần học phần mềm kế toán."),
        .init(systemImage: "mic.fill", title: "Nói là ghi",
              message: "Đọc “bán 3 thùng nước 450 nghìn”, app tự hiểu số tiền và ghi chú."),
        .init(systemImage: "doc.text.fill", title: "Xuất sổ khi cần",
              message: "Tổng hợp theo ngày, tháng, quý. Xuất PDF hoặc Excel để kê khai."),
    ]

    static let notificationReasons: [PermissionPrimerScreen.Reason] = [
        .init(systemImage: "clock", text: "Mỗi ngày tối đa một lần; đổi giờ trong Cài đặt."),
        .init(systemImage: "checkmark.circle", text: "Hôm nào đã ghi sổ thì không nhắc."),
        .init(systemImage: "hand.raised.fill", text: "Không quảng cáo, không gửi gì khác."),
    ]

    static let medsAlertReasons: [PermissionPrimerScreen.Reason] = [
        .init(systemImage: "clock.badge.exclamationmark", text: "Chỉ báo liều trễ, không báo mỗi lần đến giờ."),
        .init(systemImage: "moon.fill", text: "Là thông báo “Nhạy cảm thời gian”: chế độ Tập trung nào cho phép loại này thì báo vẫn đến ngay."),
        .init(systemImage: "hand.raised.fill", text: "Không quảng cáo, không gửi gì khác."),
    ]

    static let photoReasons: [PermissionPrimerScreen.Reason] = [
        .init(systemImage: "square.on.square", text: "Tìm ảnh chụp màn hình, và ảnh chụp nhiều lần để giữ tấm nét nhất."),
        .init(systemImage: "lock.shield", text: "Phân loại ngay trên máy: ảnh không rời khỏi máy, không tải từ iCloud về."),
        .init(systemImage: "trash", text: "Chỉ xoá khi bạn bấm xoá, và iOS hỏi lại một lần nữa."),
    ]

    static let proSymbol = "book.closed.fill"
    static let proTitle = "Sổ thu chi Pro"
    static let proSubtitle = "Xuất sổ khi cần kê khai, sao lưu iCloud, dùng trên nhiều máy."

    static let paywallBenefits: [PaywallScreen.Benefit] = [
        .init(systemImage: "doc.richtext", title: "Xuất sổ PDF & Excel", detail: "Theo tháng, quý hoặc cả năm, đúng mẫu để kê khai."),
        .init(systemImage: "icloud", title: "Sao lưu iCloud", detail: "Đổi máy không mất sổ."),
        .init(systemImage: "iphone.and.arrow.forward", title: "Nhiều máy", detail: "Vợ ghi ở quầy, chồng xem trên điện thoại."),
    ]

    static let cleanerBenefits: [PaywallScreen.Benefit] = [
        .init(systemImage: "infinity", title: "Dọn không giới hạn", detail: "Hết 100 ảnh miễn phí vẫn dọn tiếp, mọi nhóm ảnh."),
        .init(systemImage: "lock.shield", title: "Ảnh không rời khỏi máy", detail: "Phân loại ngay trên iPhone, không tải ảnh lên đâu cả."),
        .init(systemImage: "creditcard", title: "Trả một lần", detail: "Không dùng thử rồi tự trừ tiền, không gói tuần."),
    ]

    static let cleanerPlans: [PaywallPlan] = [
        PaywallPlan(id: "cleaner.lifetime", term: .lifetime, title: "Mua một lần", displayPrice: "99.000 ₫", price: 99_000,
                    detail: "Dùng mãi mãi trên mọi iPhone của bạn"),
    ]

    /// The Pro subscription group, as in `Products.storekit`: the yearly
    /// plan offers the most (level 1), then the monthly one.
    static let proGroup = "21755001"

    /// The Pro products as the App Store describes them, for the
    /// screenshots, which have no App Store: the same plans come out of
    /// `PaywallCatalog` as from StoreKit.
    static let proProducts: [StoreProduct] = [
        StoreProduct(
            id: "pro.yearly", displayName: "Gói năm", displayPrice: "299.000 ₫", price: 299_000,
            kind: .autoRenewable(
                period: .init(1, .year), introOffer: StoreProduct.IntroOffer(payment: .freeTrial, period: .init(1, .week)),
                group: .init(id: proGroup, level: 1)
            )
        ),
        StoreProduct(
            id: "pro.monthly", displayName: "Gói tháng", displayPrice: "39.000 ₫", price: 39_000,
            kind: .autoRenewable(period: .init(1, .month), introOffer: nil, group: .init(id: proGroup, level: 2)),
            winBackOffers: [
                StoreProduct.Offer(
                    id: "pro.monthly.back", payment: .payAsYouGo, displayPrice: "19.000 ₫", period: .init(1, .month), periodCount: 3
                ),
            ]
        ),
        StoreProduct(id: "pro.lifetime", displayName: "Mua một lần", displayPrice: "599.000 ₫", price: 599_000, kind: .nonConsumable),
    ]

    static let proProductIDs = proProducts.map(\.id)

    /// The sample Pro plans, a new customer's: the yearly one with its free week.
    static var plans: [PaywallPlan] {
        plans(introOfferEligible: ["pro.yearly"], customer: StoreCustomer())
    }

    /// The sample Pro plans of a customer on the monthly plan, which renews
    /// in 18 days: no trial left in the group, the yearly plan an upgrade.
    static var subscriberPlans: [PaywallPlan] {
        let renewal = LedgerSamples.calendar.date(byAdding: .day, value: 18, to: LedgerSamples.referenceNow)
        let monthly = StoreSubscription(groupID: proGroup, productID: "pro.monthly", renewsAs: "pro.monthly", periodEnds: renewal)
        return plans(introOfferEligible: [], customer: StoreCustomer(owned: ["pro.monthly"], subscriptions: [monthly]))
    }

    /// The sample Pro plans of a customer on the monthly plan, whose renewal
    /// the App Store could not charge for four days ago: in a grace period of
    /// 16 days, which ends in 12.
    static var gracePeriodPlans: [PaywallPlan] {
        let failed = LedgerSamples.calendar.date(byAdding: .day, value: -4, to: LedgerSamples.referenceNow)
        let graceEnds = LedgerSamples.calendar.date(byAdding: .day, value: 12, to: LedgerSamples.referenceNow)
        let monthly = StoreSubscription(
            groupID: proGroup, productID: "pro.monthly", renewsAs: "pro.monthly", periodEnds: failed,
            billingIssue: .gracePeriod(until: graceEnds)
        )
        return plans(introOfferEligible: [], customer: StoreCustomer(owned: ["pro.monthly"], subscriptions: [monthly]))
    }

    /// The Settings notice of a customer whose monthly plan is on hold: the
    /// App Store could not charge for it, and its grace period, if any, is
    /// over. It gives no access meanwhile.
    static var onHoldNotice: BillingNotice? {
        let failed = LedgerSamples.calendar.date(byAdding: .day, value: -20, to: LedgerSamples.referenceNow)
        let monthly = StoreSubscription(
            groupID: proGroup, productID: "pro.monthly", renewsAs: "pro.monthly", periodEnds: failed, billingIssue: .retrying
        )
        let customer = StoreCustomer(subscriptions: [monthly])
        return StoreCopy.billingNotice(
            for: customer, plans: plans(introOfferEligible: [], customer: customer), calendar: LedgerSamples.calendar
        )
    }

    /// The sample Pro plans of a customer whose subscription is over, and
    /// whom the App Store offers to come back: three months of the monthly
    /// plan at 19.000 ₫.
    static var winBackPlans: [PaywallPlan] {
        plans(introOfferEligible: [], customer: StoreCustomer(winBackOffers: [proGroup: ["pro.monthly.back"]]))
    }

    /// A customer whose plan, no longer on offer, is on hold: the App
    /// Store could not charge for its renewal twenty days ago.
    private static var legacyOnHold: StoreCustomer {
        let failed = LedgerSamples.calendar.date(byAdding: .day, value: -20, to: LedgerSamples.referenceNow)
        let legacy = StoreSubscription(
            groupID: proGroup, productID: "pro.legacy", renewsAs: "pro.legacy", periodEnds: failed, billingIssue: .retrying
        )
        return StoreCustomer(subscriptions: [legacy])
    }

    /// The sample Pro plans of that customer: none is theirs, so each is
    /// a change of plan, and buying for good says theirs still renews.
    static var legacyOnHoldPlans: [PaywallPlan] {
        plans(introOfferEligible: [], customer: legacyOnHold)
    }

    /// That customer's notice, which the paywall shows above the benefits.
    static var legacyOnHoldNotice: BillingNotice? {
        StoreCopy.billingNotice(for: legacyOnHold, plans: legacyOnHoldPlans, calendar: LedgerSamples.calendar)
    }

    private static func plans(introOfferEligible: Set<String>, customer: StoreCustomer) -> [PaywallPlan] {
        PaywallCatalog.plans(from: proProducts, in: proProductIDs, introOfferEligible: introOfferEligible, customer: customer) { _, amount in
            VND.string(Int64(NSDecimalNumber(decimal: amount).doubleValue.rounded()))
        }
        .map(described)
    }

    /// A customer's payments for Pro, for the screenshots: the monthly plan
    /// since four months ago, renewed each month, one renewal refunded and
    /// a request under way for the last, then the yearly plan, bought two
    /// days ago. A family member's lifetime plan, shared with them, is not
    /// theirs to ask a refund for, and is not listed.
    static var purchases: [StorePurchase] {
        func daysAgo(_ days: Int) -> Date {
            LedgerSamples.calendar.date(byAdding: .day, value: -days, to: LedgerSamples.referenceNow)!
        }
        func monthly(_ id: UInt64, _ days: Int, renewal: Bool = true, refunded: Int? = nil) -> StorePurchase {
            StorePurchase(
                id: id, productID: "pro.monthly", title: "Gói tháng", date: daysAgo(days), price: 39_000, displayPrice: "39.000 ₫",
                isRenewal: renewal, revocationDate: refunded.map(daysAgo)
            )
        }
        return PurchaseHistory.listed([
            StorePurchase(id: 1006, productID: "pro.yearly", title: "Gói năm", date: daysAgo(2), price: 299_000, displayPrice: "299.000 ₫"),
            monthly(1005, 12),
            monthly(1004, 42, refunded: 40),
            monthly(1003, 72),
            monthly(1002, 102),
            monthly(1001, 132, renewal: false),
            StorePurchase(
                id: 1000, productID: "pro.lifetime", title: "Mua một lần", date: daysAgo(20), price: 599_000,
                displayPrice: "599.000 ₫", isFamilyShared: true
            ),
        ])
    }

    /// The sample customer asked for a refund of their last monthly renewal.
    static let refundRequests: Set<UInt64> = [1005]

    /// The line under the lifetime plan, which the App Store has no field for.
    static func described(_ plan: PaywallPlan) -> PaywallPlan {
        var plan = plan
        if plan.term == .lifetime {
            plan.detail = "Trả một lần, dùng mãi mãi"
        }
        return plan
    }
}
