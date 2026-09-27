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

/// A log whose items count after one second in view, with its viewport set
/// at time 0.
private func log() -> SeenOnScreen<String> {
    var seen = SeenOnScreen<String>(dwell: 1)
    seen.setViewport(viewport, at: 0)
    return seen
}

/// Reports a tile: `#expect` cannot call a mutating method itself.
private func report(_ seen: inout SeenOnScreen<String>, _ id: String, middle y: CGFloat, at time: TimeInterval) -> Bool {
    seen.report(id, at: tile(middle: y), time: time)
}

private func settle(_ seen: inout SeenOnScreen<String>, at time: TimeInterval) -> Bool {
    seen.settle(at: time)
}

@Suite("Seen on screen")
struct SeenOnScreenTests {
    @Test("An item counts once its middle has stayed in the viewport for the dwell")
    func dwell() {
        var seen = log()
        #expect(!report(&seen, "a", middle: 300, at: 0))
        #expect(!report(&seen, "a", middle: 320, at: 0.5))
        // Moving within the view keeps the clock running.
        #expect(report(&seen, "a", middle: 340, at: 1))
        #expect(seen.ids == ["a"])
        #expect(SeenOnScreen<String>().dwell == 0.3)
    }

    @Test("Its middle, not any part: drawn under the tray or the bars does not count")
    func middle() {
        var seen = log()
        // Drawn, and more than half of it clear of the tray, but not its middle.
        seen.report("under-tray", at: tile(middle: 600), time: 0)
        seen.report("under-bars", at: tile(middle: 99), time: 0)
        // The top edge is in; the bottom edge is the tray's.
        seen.report("top-edge", at: tile(middle: 100), time: 0)
        seen.report("bottom-edge", at: tile(middle: 599), time: 0)
        seen.settle(at: 5)
        #expect(seen.ids == ["top-edge", "bottom-edge"])
    }

    @Test("A moment in view does not count: leaving starts the dwell over")
    func leaving() {
        var seen = log()
        // A layout pass puts it in view for a frame.
        seen.report("a", at: tile(middle: 300), time: 0)
        seen.report("a", at: tile(middle: 900), time: 0.02)
        #expect(!settle(&seen, at: 5))
        // Back in view at 6: it counts from then.
        #expect(!report(&seen, "a", middle: 300, at: 6))
        #expect(!report(&seen, "a", middle: 300, at: 6.5))
        #expect(report(&seen, "a", middle: 300, at: 7))
    }

    @Test("An item at rest counts when the log is settled, and says when to settle")
    func atRest() {
        var seen = log()
        #expect(seen.nextSettle == nil)
        seen.report("a", at: tile(middle: 300), time: 2)
        seen.report("b", at: tile(middle: 400), time: 3)
        #expect(seen.nextSettle == 3)
        #expect(!settle(&seen, at: 2.5))
        #expect(settle(&seen, at: 3))
        #expect(seen.ids == ["a"])
        #expect(seen.nextSettle == 4)
        #expect(settle(&seen, at: 4))
        #expect(seen.ids == ["a", "b"])
        #expect(seen.nextSettle == nil)
        #expect(!settle(&seen, at: 10))
    }

    @Test("Frames reported before the viewport is measured start their dwell when it is")
    func viewportLast() {
        var seen = SeenOnScreen<String>(dwell: 1)
        seen.report("a", at: tile(middle: 300), time: 0)
        seen.report("b", at: tile(middle: 700), time: 0)
        #expect(seen.nextSettle == nil)
        seen.setViewport(viewport, at: 5)
        #expect(!settle(&seen, at: 5.5))
        #expect(settle(&seen, at: 6))
        #expect(seen.ids == ["a"])
    }

    @Test("A viewport that grows takes in the items already there; one that shrinks stops their dwell")
    func viewportChanges() {
        var seen = log()
        seen.report("a", at: tile(middle: 650), time: 0)
        seen.report("b", at: tile(middle: 550), time: 0)
        // The tray got taller: b is under it before its dwell is up.
        seen.setViewport(CGRect(x: 0, y: 100, width: 400, height: 400), at: 0.5)
        // Then shorter than at first: a is in view from 2, and b again.
        seen.setViewport(CGRect(x: 0, y: 100, width: 400, height: 600), at: 2)
        #expect(!settle(&seen, at: 2.5))
        #expect(settle(&seen, at: 3))
        #expect(seen.ids == ["a", "b"])
    }

    @Test("A forgotten item is not seen at its stale frame")
    func forget() {
        var seen = SeenOnScreen<String>(dwell: 1)
        seen.report("a", at: tile(middle: 300), time: 0)
        seen.forget("a")
        seen.setViewport(viewport, at: 0)
        #expect(!settle(&seen, at: 5))
        // Nor does a dwell it had started carry on.
        seen.report("b", at: tile(middle: 300), time: 5)
        seen.forget("b")
        #expect(!settle(&seen, at: 10))
        #expect(seen.ids.isEmpty)
        // Reported again, it counts again.
        seen.report("a", at: tile(middle: 300), time: 10)
        #expect(settle(&seen, at: 11))
        #expect(seen.ids == ["a"])
    }

    @Test("Seen stays seen: scrolled away, forgotten, or under a smaller viewport")
    func staysSeen() {
        var seen = log()
        seen.report("a", at: tile(middle: 300), time: 0)
        #expect(report(&seen, "a", middle: 300, at: 1))
        // Staying in view starts no new dwell: it is counted once.
        #expect(!report(&seen, "a", middle: 300, at: 2))
        #expect(!report(&seen, "a", middle: 300, at: 3.5))
        #expect(seen.nextSettle == nil)
        #expect(!settle(&seen, at: 10))
        seen.report("a", at: tile(middle: 2_000), time: 3)
        seen.forget("a")
        seen.setViewport(CGRect(x: 0, y: 100, width: 400, height: 10), at: 4)
        #expect(seen.ids == ["a"])
        #expect(seen.nextSettle == nil)
    }

    @Test("A viewport not yet measured, or empty, sees nothing")
    func nothingMeasured() {
        var seen = SeenOnScreen<String>(dwell: 1)
        seen.report("a", at: tile(middle: 300), time: 0)
        #expect(!settle(&seen, at: 5))
        seen.setViewport(CGRect(x: 0, y: 300, width: 400, height: 0), at: 5)
        #expect(!settle(&seen, at: 10))
        #expect(seen.ids.isEmpty)
    }
}
