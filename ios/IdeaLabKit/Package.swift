// swift-tools-version: 6.0
import PackageDescription

// Four libraries, split by what they need to build:
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
//   the customer owns), wrapped in `#if os(iOS)` too. The rules it follows,
//   plans from products and access from transactions, are in IdeaLabCore,
//   tested on Linux; LabStore itself is tested against StoreKit's test
//   environment by the demo's IdeaLabDemoTests, hosted by the demo app, as
//   that environment is an app's own.
let package = Package(
    name: "IdeaLabKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IdeaLabCore", targets: ["IdeaLabCore"]),
        .library(name: "IdeaLabUI", targets: ["IdeaLabUI"]),
        .library(name: "IdeaLabPhotos", targets: ["IdeaLabPhotos"]),
        .library(name: "IdeaLabStore", targets: ["IdeaLabStore"]),
    ],
    targets: [
        .target(name: "IdeaLabCore"),
        .target(name: "IdeaLabUI", dependencies: ["IdeaLabCore"]),
        .target(name: "IdeaLabPhotos", dependencies: ["IdeaLabCore"]),
        .target(name: "IdeaLabStore", dependencies: ["IdeaLabCore"]),
        .testTarget(name: "IdeaLabCoreTests", dependencies: ["IdeaLabCore"]),
    ]
)
