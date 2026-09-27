#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import IdeaLabCore
import Testing

/// A phone-sized viewport: below the bars (y 100) and above the tray (y 600).
private let viewport = CGRect(x: 0, y: 100, width: 400, height: 500)

/// A 120-point tile whose middle is at `y`.
private func tile(middle y: CGFloat) -> CGRect {
    CGRect(x: 10, y: y - 60, width: 120, height: 120)
}

/// Reports a tile: `#expect` cannot call a mutating method itself.
private func report(_ seen: inout SeenOnScreen<String>, _ id: String, middle y: CGFloat) -> Bool {
    seen.report(id, at: tile(middle: y))
}

@Suite("Seen on screen")
struct SeenOnScreenTests {
    @Test("An item is seen once its middle is in the viewport, not when it is only drawn under the tray or the bars")
    func middle() {
        var seen = SeenOnScreen<String>()
        seen.viewport = viewport
        // Drawn, and more than half of it clear of the tray, but not its middle.
        #expect(!report(&seen, "under-tray", middle: 600))
        #expect(!report(&seen, "under-bars", middle: 99))
        // The top edge is in; the bottom edge is the tray's.
        #expect(report(&seen, "top-edge", middle: 100))
        #expect(report(&seen, "bottom-edge", middle: 599))
        #expect(seen.ids == ["top-edge", "bottom-edge"])
    }

    @Test("Frames reported before the viewport is measured are checked when it is")
    func viewportLast() {
        var seen = SeenOnScreen<String>()
        seen.report("a", at: tile(middle: 300))
        seen.report("b", at: tile(middle: 700))
        #expect(seen.ids.isEmpty)
        seen.viewport = viewport
        #expect(seen.ids == ["a"])
    }

    @Test("A viewport that grows takes in the items already there")
    func viewportGrows() {
        var seen = SeenOnScreen<String>()
        seen.viewport = viewport
        seen.report("a", at: tile(middle: 650))
        #expect(seen.ids.isEmpty)
        // The tray got shorter.
        seen.viewport = CGRect(x: 0, y: 100, width: 400, height: 600)
        #expect(seen.ids == ["a"])
    }

    @Test("A forgotten item is not seen at its stale frame")
    func forget() {
        var seen = SeenOnScreen<String>()
        seen.report("a", at: tile(middle: 300))
        seen.forget("a")
        seen.viewport = viewport
        #expect(seen.ids.isEmpty)
        // Reported again, it counts again.
        seen.report("a", at: tile(middle: 300))
        #expect(seen.ids == ["a"])
    }

    @Test("Seen stays seen: scrolled away, forgotten, or under a smaller viewport")
    func staysSeen() {
        var seen = SeenOnScreen<String>()
        seen.viewport = viewport
        #expect(report(&seen, "a", middle: 300))
        #expect(!report(&seen, "a", middle: 300))
        seen.report("a", at: tile(middle: 2_000))
        seen.forget("a")
        seen.viewport = CGRect(x: 0, y: 100, width: 400, height: 10)
        #expect(seen.ids == ["a"])
    }

    @Test("A viewport not yet measured, or empty, sees nothing")
    func nothingMeasured() {
        var seen = SeenOnScreen<String>()
        #expect(!report(&seen, "a", middle: 300))
        seen.viewport = CGRect(x: 0, y: 300, width: 400, height: 0)
        #expect(seen.ids.isEmpty)
    }
}
