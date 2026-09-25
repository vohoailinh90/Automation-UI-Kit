import IdeaLabCore
import IdeaLabUI
import SwiftUI

/// Every screen the demo can open directly. The raw values are the ids that
/// `ios/scripts/render-previews.sh` passes as `-screen`; keep the two in sync.
enum DemoScreen: String, CaseIterable, Identifiable {
    case tokens
    case components
    case ledgerHome = "ledger-home"
    case ledgerEntry = "ledger-entry"
    case ledgerReport = "ledger-report"
    case medsToday = "meds-today"
    case medsCaregiver = "meds-caregiver"
    case onboarding
    case permission
    case paywall
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: "Màu & chữ"
        case .components: "Thành phần"
        case .ledgerHome: "Trang chủ sổ"
        case .ledgerEntry: "Nhập nhanh 10 giây"
        case .ledgerReport: "Báo cáo tháng/quý"
        case .medsToday: "Cha mẹ: ĐÃ UỐNG"
        case .medsCaregiver: "Con: theo dõi"
        case .onboarding: "Giới thiệu"
        case .permission: "Xin quyền"
        case .paywall: "Paywall"
        case .settings: "Cài đặt"
        }
    }

    var navigationTitle: String {
        switch self {
        case .ledgerHome: "Sổ thu chi"
        case .ledgerReport: "Báo cáo"
        case .medsToday: "Thuốc của Mẹ"
        case .medsCaregiver: "Mẹ"
        case .settings: "Cài đặt"
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
        case .medsToday: "pills"
        case .medsCaregiver: "person.2"
        case .onboarding: "hand.wave"
        case .permission: "bell.badge"
        case .paywall: "star"
        case .settings: "gearshape"
        }
    }

    @MainActor @ViewBuilder
    func destination(store: DemoLedgerStore, meds: DemoMedsStore, largeText: Binding<Bool>) -> some View {
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
            LedgerReportScreen(entries: store.entries, now: store.now, calendar: store.calendar) { _, _ in }
        case .medsToday:
            // Always in the meds theme: teal, senior density.
            MedsTodayDemo(store: meds)
                .labTheme(.meds)
        case .medsCaregiver:
            TimelineView(.periodic(from: meds.started, by: 60)) { context in
                CaregiverScreen(
                    personName: "Mẹ",
                    medications: meds.medications,
                    log: meds.log,
                    now: meds.now(at: context.date),
                    calendar: meds.calendar,
                    updatedAt: meds.updatedAt,
                    onCall: {},
                    onRemind: { _ in }
                )
            }
            .labTheme(.meds)
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
            PaywallScreen(
                systemImage: "book.closed.fill",
                title: "Sổ thu chi Pro",
                subtitle: "Xuất sổ khi cần kê khai, sao lưu iCloud, dùng trên nhiều máy.",
                benefits: DemoContent.paywallBenefits,
                plans: DemoContent.plans,
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
        }
    }
}

/// Settings with an account, so the deletion row shows. The demo has no
/// account to delete, and says so instead of pretending.
struct SettingsDemo: View {
    @Binding var largeText: Bool
    @State private var showsNoAccount = false

    var body: some View {
        SettingsScreen(
            isPro: false,
            largeText: $largeText,
            privacyURL: DemoContent.privacyURL,
            termsURL: DemoContent.termsURL,
            appVersion: "0.1.0 (1)",
            onUpgrade: {},
            onRestore: {},
            onExport: {},
            onContact: {},
            onDeleteAccount: { showsNoAccount = true }
        )
        .alert(Text(verbatim: "Bản demo không có tài khoản"), isPresented: $showsNoAccount) {
            Button(role: .cancel) {} label: { Text(verbatim: "OK") }
        } message: {
            Text(verbatim: "Trong app thật, đây là lúc xoá tài khoản và dữ liệu đồng bộ, rồi đăng xuất.")
        }
    }
}

/// Home wired to the demo store: the sheet, the toast and undo all work.
struct LedgerHomeDemo: View {
    @Bindable var store: DemoLedgerStore
    @State private var presenting: LedgerEntry.Kind?

    init(store: DemoLedgerStore, presenting: LedgerEntry.Kind? = nil) {
        self.store = store
        _presenting = State(initialValue: presenting)
    }

    var body: some View {
        LedgerHomeScreen(
            entries: store.entries,
            now: store.now,
            calendar: store.calendar,
            onAdd: { kind in presenting = kind }
        )
        .sheet(item: $presenting) { kind in
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
        }
        .labToast($store.toast) { _ in store.undoLastSave() }
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
        .labToast($store.toast) { _ in store.undoLastRecord() }
    }
}

@Observable
@MainActor
final class DemoMedsStore {
    let medications = MedicationSamples.medications
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

    func now(at date: Date = .now) -> Date {
        LedgerSamples.referenceNow.addingTimeInterval(max(date.timeIntervalSince(started), 0))
    }

    func record(_ outcome: DoseRecord.Outcome, _ dose: ScheduledDose) {
        log.record(outcome, for: dose.id, at: now())
        updatedAt = now()
        lastRecorded = dose.id
        let text = outcome == .taken ? "Đã ghi nhận: \(dose.medication.name)" : "Đã ghi: bỏ qua \(dose.medication.name)"
        toast = LabToastMessage(text: text, actionTitle: "Hoàn tác")
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

    static let paywallBenefits: [PaywallScreen.Benefit] = [
        .init(systemImage: "doc.richtext", title: "Xuất sổ PDF & Excel", detail: "Theo tháng, quý hoặc cả năm, đúng mẫu để kê khai."),
        .init(systemImage: "icloud", title: "Sao lưu iCloud", detail: "Đổi máy không mất sổ."),
        .init(systemImage: "iphone.and.arrow.forward", title: "Nhiều máy", detail: "Vợ ghi ở quầy, chồng xem trên điện thoại."),
    ]

    static var plans: [PaywallPlan] {
        let yearly = PaywallPlan(id: "pro.yearly", term: .yearly, title: "Gói năm", displayPrice: "299.000 ₫", price: 299_000, freeTrialDays: 7)
        let monthly = PaywallPlan(id: "pro.monthly", term: .monthly, title: "Gói tháng", displayPrice: "39.000 ₫", price: 39_000)
        let lifetime = PaywallPlan(id: "pro.lifetime", term: .lifetime, title: "Mua một lần", displayPrice: "599.000 ₫", price: 599_000,
                                   detail: "Trả một lần, dùng mãi mãi")
        var badgedYearly = yearly
        if let saving = PlanMath.savingsPercent(of: yearly, comparedTo: monthly) {
            badgedYearly.badge = "Tiết kiệm \(saving)%"
        }
        if let perMonth = PlanMath.monthlyEquivalent(of: yearly) {
            let rounded = Int64(NSDecimalNumber(decimal: perMonth).doubleValue.rounded())
            badgedYearly.detail = "≈ \(VND.string(rounded))/tháng"
        }
        return [badgedYearly, monthly, lifetime]
    }
}
