import AVFoundation
import IdeaLabCore
import IdeaLabStore
import IdeaLabUI
import SwiftUI

@main
struct IdeaLabDemoApp: App {
    /// Purchases, from launch: the store hears about what happens outside
    /// the app (Ask to Buy, another device, a refund) from the start.
    @State private var purchases = LabStore(productIDs: DemoLaunch.soldProductIDs)
    /// The App Store's sheets (a billing issue, a price increase, an offer
    /// to come back), from launch too: they wait while the parent answers a
    /// dose or a sale is written down, and show after.
    @State private var messages = LabMessages()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The ledger says saved entries aloud (LabSpeaker), and the demo makes
        // no other sound: other apps' audio plays on under the voice, and the
        // Silent switch silences it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    var body: some Scene {
        WindowGroup {
            DemoRoot()
                .environment(purchases)
                .showsStoreMessages(messages)
        }
        // Back in the foreground: what changed meanwhile, such as a renewal
        // the App Store could not charge for, which StoreKit may not announce.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await purchases.refreshEntitlements() }
            }
        }
        // In Assistive Access (the Info.plist has UISupportsAssistiveAccess),
        // iOS 26 shows this scene instead: the parent's medicines, alone.
        if #available(iOS 26.0, *) {
            AssistiveAccess {
                DemoAssistiveRoot()
            }
        }
    }
}

/// What the demo is in Assistive Access: the one screen a parent needs.
struct DemoAssistiveRoot: View {
    @State private var meds = DemoMedsStore()

    var body: some View {
        NavigationStack {
            MedsAssistiveDemo(store: meds)
        }
        .labTheme(.meds)
        .task { meds.shareWithWidget() }
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .environment(\.calendar, LedgerSamples.calendar)
        .environment(\.timeZone, LedgerSamples.calendar.timeZone)
    }
}

/// Opens the gallery, or a single screen when launched with `-screen <id>`
/// (how `ios/scripts/render-previews.sh` takes its screenshots). With
/// `-scroll bottom` as well, the screen opens scrolled to its end, the sheet
/// it presents included: the cards of a long form the first screenful does
/// not reach.
struct DemoRoot: View {
    @State private var store = DemoLedgerStore()
    @State private var meds = DemoMedsStore()
    @State private var cleaner = DemoCleanerStore()
    @AppStorage("demo.theme") private var themeName = DemoTheme.ledger.rawValue
    @AppStorage("demo.largeText") private var largeText = false

    private var theme: LabTheme {
        var theme = (DemoTheme(rawValue: themeName) ?? .ledger).theme
        if largeText { theme.density = .senior }
        return theme
    }

    var body: some View {
        Group {
            if let screen = DemoLaunch.screen {
                NavigationStack {
                    screen.destination(store: store, meds: meds, cleaner: cleaner, largeText: $largeText)
                        .navigationTitle(screen.navigationTitle)
                }
                .defaultScrollAnchor(DemoLaunch.scrollAnchor)
                .onAppear {
                    // A screen that opens a sheet is up once the sheet is, and
                    // the photo screens once sorted: those say so themselves.
                    if !screen.saysWhenReady { DemoLaunch.markReady() }
                }
            } else {
                GalleryView(store: store, meds: meds, cleaner: cleaner, themeName: $themeName, largeText: $largeText)
            }
        }
        .labTheme(theme)
        // What the parent's widget shows, from launch.
        .task { meds.shareWithWidget() }
        // The kit is Vietnamese-first, and the sample book is kept in Vietnam
        // time: show it that way whatever the simulator's region and zone
        // (CI simulators run in UTC). System controls such as DatePicker read these.
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .environment(\.calendar, LedgerSamples.calendar)
        .environment(\.timeZone, LedgerSamples.calendar.timeZone)
    }
}

/// Launch arguments for the screenshots, and the demo's side of taking them.
enum DemoLaunch {
    /// The screen `-screen <id>` opens; `nil` for the gallery.
    static var screen: DemoScreen? {
        UserDefaults.standard.string(forKey: "screen").flatMap(DemoScreen.init(rawValue:))
    }

    /// `-scroll bottom`: scroll views open at their end. Leading as well, so a
    /// row that scrolls sideways still opens at its first item. A sheet does
    /// not inherit it from the screen that presents it, so a demo sheet
    /// applies it again.
    static var scrollAnchor: UnitPoint? {
        UserDefaults.standard.string(forKey: "scroll") == "bottom" ? .bottomLeading : nil
    }

    /// Whether Xcode launched the demo to host its tests (IdeaLabDemoTests),
    /// which it says in the environment it gives the app.
    static var isTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains { environment[$0] != nil }
    }

    /// What the demo's store sells: the Pro plans, and nothing while the demo
    /// hosts the store tests, whose transactions it would otherwise finish
    /// before the tests could see whether their own store does.
    static var soldProductIDs: [String] {
        isTestHost ? [] : DemoContent.proProductIDs
    }

    /// Tells `render-previews.sh` that the screen it shoots has appeared, by
    /// creating `Library/Caches/demo-ready`. The script deletes the file
    /// before each launch, waits for it, then for the screen to stand still.
    /// The screen's view calls this, or the sheet's for a screen that opens
    /// one (`DemoScreen.saysWhenReady`): a slow simulator can show the screen
    /// under a sheet for a while before the sheet.
    static func markReady() {
        guard screen != nil,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        try? Data().write(to: caches.appending(path: "demo-ready"))
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
    /// Whether each saved entry is said aloud: the home screen's speaker
    /// button. Turning it off also stops a sentence being said.
    var readsBack = true {
        didSet {
            if !readsBack { LabSpeaker.shared.stop() }
        }
    }
    private var lastSaved: LedgerEntry?

    let now = LedgerSamples.referenceNow
    let calendar = LedgerSamples.calendar

    func add(_ entry: LedgerEntry) {
        entries.insert(entry, at: 0)
        lastSaved = entry
        let kind = entry.kind == .income ? "thu" : "chi"
        toast = LabToastMessage(
            text: "Đã lưu khoản \(kind) \(VND.string(entry.amount))",
            announcement: "Đã lưu khoản \(kind) \(VND.string(entry.amount, style: .spoken))",
            actionTitle: "Hoàn tác"
        )
        if readsBack {
            LabSpeaker.shared.say(entry.readback)
        }
    }

    func undoLastSave() {
        guard let lastSaved else { return }
        entries.removeAll { $0.id == lastSaved.id }
        self.lastSaved = nil
        LabSpeaker.shared.stop()
    }
}
