import IdeaLabCore
import IdeaLabUI
import SwiftUI

@main
struct IdeaLabDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoRoot()
        }
    }
}

/// Opens the gallery, or a single screen when launched with `-screen <id>`
/// (how `ios/scripts/render-previews.sh` takes its screenshots).
struct DemoRoot: View {
    @State private var store = DemoLedgerStore()
    @AppStorage("demo.theme") private var themeName = DemoTheme.ledger.rawValue
    @AppStorage("demo.largeText") private var largeText = false

    private var theme: LabTheme {
        var theme = (DemoTheme(rawValue: themeName) ?? .ledger).theme
        if largeText { theme.density = .senior }
        return theme
    }

    var body: some View {
        Group {
            if let id = UserDefaults.standard.string(forKey: "screen"), let screen = DemoScreen(rawValue: id) {
                NavigationStack {
                    screen.destination(store: store, largeText: $largeText)
                        .navigationTitle(screen.navigationTitle)
                }
            } else {
                GalleryView(store: store, themeName: $themeName, largeText: $largeText)
            }
        }
        .labTheme(theme)
        // The kit is Vietnamese-first, and the sample book is kept in Vietnam
        // time: show it that way whatever the simulator's region and zone
        // (CI simulators run in UTC). System controls such as DatePicker read these.
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .environment(\.calendar, LedgerSamples.calendar)
        .environment(\.timeZone, LedgerSamples.calendar.timeZone)
    }
}

enum DemoTheme: String, CaseIterable, Identifiable {
    case ledger
    case meds
    case cleaner

    var id: String { rawValue }

    var theme: LabTheme {
        switch self {
        case .ledger: .ledger
        case .meds: .meds
        case .cleaner: .cleaner
        }
    }

    var title: String {
        switch self {
        case .ledger: "Sổ thu chi (xanh dương)"
        case .meds: "Nhắc thuốc (xanh ngọc)"
        case .cleaner: "Dọn ảnh (tím)"
        }
    }
}

/// In-memory book seeded with the deterministic sample, so every screenshot
/// shows the same numbers.
@Observable
@MainActor
final class DemoLedgerStore {
    var entries: [LedgerEntry] = LedgerSamples.entries()
    var toast: LabToastMessage?
    private var lastSaved: LedgerEntry?

    let now = LedgerSamples.referenceNow
    let calendar = LedgerSamples.calendar

    func add(_ entry: LedgerEntry) {
        entries.insert(entry, at: 0)
        lastSaved = entry
        let kind = entry.kind == .income ? "thu" : "chi"
        toast = LabToastMessage(text: "Đã lưu khoản \(kind) \(VND.string(entry.amount))", actionTitle: "Hoàn tác")
    }

    func undoLastSave() {
        guard let lastSaved else { return }
        entries.removeAll { $0.id == lastSaved.id }
        self.lastSaved = nil
    }
}
