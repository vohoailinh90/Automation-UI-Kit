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
        case .settings: "Cài đặt"
        }
    }

    var navigationTitle: String {
        switch self {
        case .ledgerHome: "Sổ thu chi"
        case .ledgerReport: "Báo cáo"
        case .medsToday: "Thuốc của Mẹ"
        case .medsAssistive: "Uống thuốc"
        case .medsCaregiver, .medsAdd, .medsEdit, .medsAlerts: "Mẹ"
        case .cleanerHome, .cleanerLibrary, .cleanerMeasuredHome: "Dọn ảnh"
        case .cleanerSwipe: "Ảnh chụp màn hình"
        case .cleanerReview: "Xem lại"
        case .cleanerSimilar, .cleanerMeasured: "Ảnh gần giống"
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
        case .settings: "gearshape"
        }
    }

    /// Whether the screen tells the screenshots itself that it is ready
    /// (`DemoLaunch.markReady`), later than when it appears: a screen that
    /// opens a sheet over another is up once the sheet is, so the sheet
    /// tells them, not the screen under it; the photo screens are up once
    /// their photos are sorted.
    var saysWhenReady: Bool {
        switch self {
        case .ledgerEntry, .medsAdd, .medsEdit, .medsAlerts, .cleanerLibrary, .cleanerMeasured, .cleanerMeasuredHome: true
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
            LedgerReportScreen(entries: store.entries, now: store.now, calendar: store.calendar) { _, _ in }
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
            .onAppear { DemoLaunch.markReady() }
        }
        .labToast($store.toast) { _ in store.undoLastSave() }
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
