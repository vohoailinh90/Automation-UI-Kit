// swift-tools-version: 6.0
import PackageDescription

// Six libraries, split by what they need to build:
// - IdeaLabCore: Foundation only (colour maths, VND money, ledger sums, plan maths),
//   plus CoreGraphics' geometry on Apple platforms.
//   Builds and tests anywhere Swift runs, including the Linux CI job.
// - IdeaLabUI: SwiftUI components and screen templates. Every file is wrapped in
//   `#if os(iOS)`, so on macOS/Linux it compiles to an empty module and
//   `swift test` still runs the core tests there.
// - IdeaLabPhotos: the photo cleaner's side of PhotoKit and Vision (access,
//   measuring, thumbnails, deleting), wrapped in `#if os(iOS)` the same way.
//   A library of its own, so the apps that do not clean photos link neither
//   framework, and need no photo-library purpose string.
// - IdeaLabStore: selling with StoreKit 2 (plans, purchase, restore, what
//   the customer owns, and the App Store's own messages), wrapped in
//   `#if os(iOS)` too. The rules it follows, plans from products, access
//   from transactions and when messages show, are in IdeaLabCore, tested on
//   Linux; LabStore itself is tested against StoreKit's test
//   environment by the demo's IdeaLabDemoTests, hosted by the demo app, as
//   that environment is an app's own.
// - IdeaLabWidgets: the views of the apps' widgets (WidgetKit), wrapped in
//   `#if os(iOS)` too. Apart from IdeaLabUI, as a widget extension may only
//   use what extensions can: IdeaLabUI shows the App Store's own sheets,
//   which only an app can. What a widget shows, and when, is in IdeaLabCore.
// - IdeaLabNotifications: dose alerts as local notifications
//   (UserNotifications), `#if os(iOS)` as well. Extension-safe like
//   IdeaLabWidgets, as a widget's "ĐÃ UỐNG" plans the parent's reminders
//   again; IdeaLabUI builds on it, and adds opening Settings.
let package = Package(
    name: "IdeaLabKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IdeaLabCore", targets: ["IdeaLabCore"]),
        .library(name: "IdeaLabUI", targets: ["IdeaLabUI"]),
        .library(name: "IdeaLabPhotos", targets: ["IdeaLabPhotos"]),
        .library(name: "IdeaLabStore", targets: ["IdeaLabStore"]),
        .library(name: "IdeaLabWidgets", targets: ["IdeaLabWidgets"]),
        .library(name: "IdeaLabNotifications", targets: ["IdeaLabNotifications"]),
    ],
    targets: [
        .target(name: "IdeaLabCore"),
        .target(name: "IdeaLabUI", dependencies: ["IdeaLabCore", "IdeaLabNotifications"]),
        .target(name: "IdeaLabPhotos", dependencies: ["IdeaLabCore"]),
        .target(name: "IdeaLabStore", dependencies: ["IdeaLabCore"]),
        .target(name: "IdeaLabWidgets", dependencies: ["IdeaLabCore"]),
        .target(name: "IdeaLabNotifications", dependencies: ["IdeaLabCore"]),
        .testTarget(name: "IdeaLabCoreTests", dependencies: ["IdeaLabCore"]),
    ]
)
