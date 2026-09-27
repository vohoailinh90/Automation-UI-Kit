import IdeaLabCore
import IdeaLabUI
import SwiftUI

/// The kit's table of contents: foundations, components, then whole screens.
struct GalleryView: View {
    let store: DemoLedgerStore
    let meds: DemoMedsStore
    let cleaner: DemoCleanerStore
    @Binding var themeName: String
    @Binding var largeText: Bool
    @Environment(\.labTheme) private var theme

    var body: some View {
        NavigationStack {
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
                }
                Section("Mẫu: Dọn ảnh, mua một lần") {
                    link(.cleanerHome)
                    link(.cleanerSwipe)
                    link(.cleanerReview)
                    link(.cleanerSimilar)
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
                    link(.settings)
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
        }
    }

    private func link(_ screen: DemoScreen) -> some View {
        NavigationLink {
            screen.destination(store: store, meds: meds, cleaner: cleaner, largeText: $largeText)
                .navigationTitle(screen.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            Label {
                Text(screen.title)
            } icon: {
                SettingsIcon(screen.systemImage)
            }
        }
    }
}
