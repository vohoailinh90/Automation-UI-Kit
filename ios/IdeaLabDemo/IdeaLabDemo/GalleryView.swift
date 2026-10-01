import IdeaLabCore
import IdeaLabStore
import IdeaLabUI
import SwiftUI

/// The kit's table of contents: foundations, components, then whole screens.
///
/// An offer code redeemed outside the app (in the App Store, through a
/// link, even before the app was first opened) is welcomed here, while this
/// page is in front, or as soon as it comes back to the front; the paywall
/// and Settings welcome the codes redeemed there.
///
/// A control, Siri or a shortcut asking to write an entry down
/// (`OpenQuickEntryIntent`) brings the ledger's home to the front, which
/// then takes the request. A tap on the parent's widget brings their
/// screen (`MedsWidgetShared.url`).
struct GalleryView: View {
    let store: DemoLedgerStore
    let meds: DemoMedsStore
    let cleaner: DemoCleanerStore
    @Binding var themeName: String
    @Binding var largeText: Bool
    @Environment(\.labTheme) private var theme
    @Environment(LabStore.self) private var purchases
    /// Whether this page is in front, no screen pushed over it.
    @State private var isFront = true
    @State private var toast: LabToastMessage?
    /// The screens pushed over this page.
    @State private var path: [DemoScreen] = []
    private let quickEntry = QuickEntryRouter.shared

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Nền tảng") {
                    link(.tokens)
                    link(.components)
                }
                Section("Mẫu: Sổ thu chi 10 giây") {
                    link(.ledgerHome)
                    link(.ledgerEntry)
                    link(.ledgerReport)
                    link(.ledgerExportPDF)
                    link(.ledgerExportSpreadsheet)
                }
                Section("Mẫu: Nhắc thuốc cho cha mẹ") {
                    link(.medsToday)
                    link(.medsAssistive)
                    link(.medsCaregiver)
                    link(.medsAdd)
                    link(.medsEdit)
                    link(.medsAlerts)
                    link(.medsWidgets)
                    link(.medsCaregiverWidgets)
                }
                Section("Mẫu: Dọn ảnh, mua một lần") {
                    link(.cleanerHome)
                    link(.cleanerSwipe)
                    link(.cleanerReview)
                    link(.cleanerSimilar)
                    link(.cleanerVideos)
                    link(.cleanerVideosReview)
                    link(.cleanerDone)
                    link(.cleanerPaywall)
                    link(.cleanerLibrary)
                    link(.cleanerMeasured)
                    link(.cleanerMeasuredHome)
                }
                Section("Mẫu dùng chung") {
                    link(.onboarding)
                    link(.permission)
                    link(.paywall)
                    link(.paywallSubscriber)
                    link(.paywallBillingIssue)
                    link(.paywallBillingLegacy)
                    link(.paywallWinBack)
                    link(.settings)
                    link(.settingsBillingIssue)
                    link(.purchaseHelp)
                }
                Section {
                    Picker("Bảng màu", selection: $themeName) {
                        ForEach(DemoTheme.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    Toggle("Chữ và nút lớn (người lớn tuổi)", isOn: $largeText)
                } header: {
                    Text("Giao diện")
                } footer: {
                    Text("Đổi bảng màu để xem cùng một màn hình trong ba app. Chế độ tối và cỡ chữ lấy theo Cài đặt của máy.")
                }
            }
            .navigationTitle("IdeaLab UI")
            .navigationDestination(for: DemoScreen.self) { screen in
                screen.destination(store: store, meds: meds, cleaner: cleaner, largeText: $largeText)
                    .navigationTitle(screen.navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .labToast($toast)
            .welcomesRedemptions(from: purchases, plans: purchases.plans, isActive: isFront, toast: $toast)
            .onAppear { isFront = true }
            .onDisappear { isFront = false }
        }
        .onAppear(perform: showLedgerIfAsked)
        .onChange(of: quickEntry.pending) { showLedgerIfAsked() }
        // A tap on the parent's widget: their screen, with "ĐÃ UỐNG"; on
        // the family's: theirs, with "Gọi" and "Nhắc lại".
        .onOpenURL { url in
            if url == MedsWidgetShared.url, path.last != .medsToday {
                path.append(.medsToday)
            } else if url == CaregiverWidgetShared.url, path.last != .medsCaregiver {
                path.append(.medsCaregiver)
            }
        }
    }

    /// An entry asked for from outside the app: the ledger's home comes to
    /// the front, unless it is there, and takes the request.
    private func showLedgerIfAsked() {
        guard quickEntry.pending != nil, path.last != .ledgerHome, path.last != .ledgerEntry else { return }
        path.append(.ledgerHome)
    }

    private func link(_ screen: DemoScreen) -> some View {
        NavigationLink(value: screen) {
            Label {
                Text(screen.title)
            } icon: {
                SettingsIcon(screen.systemImage)
            }
        }
    }
}
