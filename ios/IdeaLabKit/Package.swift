// swift-tools-version: 6.0
import PackageDescription

// Two libraries, split by what they need to build:
// - IdeaLabCore: Foundation only (colour maths, VND money, ledger sums, plan maths).
//   Builds and tests anywhere Swift runs, including the Linux CI job.
// - IdeaLabUI: SwiftUI components and screen templates. Every file is wrapped in
//   `#if os(iOS)`, so on macOS/Linux it compiles to an empty module and
//   `swift test` still runs the core tests there.
let package = Package(
    name: "IdeaLabKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IdeaLabCore", targets: ["IdeaLabCore"]),
        .library(name: "IdeaLabUI", targets: ["IdeaLabUI"]),
    ],
    targets: [
        .target(name: "IdeaLabCore"),
        .target(name: "IdeaLabUI", dependencies: ["IdeaLabCore"]),
        .testTarget(name: "IdeaLabCoreTests", dependencies: ["IdeaLabCore"]),
    ]
)
