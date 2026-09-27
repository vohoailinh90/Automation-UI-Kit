import Foundation
#if canImport(CoreGraphics)
// On Apple platforms Foundation has the CGRect type but not its members
// (`null`, `contains`, `midX`); Linux's Foundation has both.
import CoreGraphics
#endif

/// Which items of a scrolling list have been on screen: those whose middle
/// stayed inside the viewport, the part of the screen nothing covers, for
/// `dwell` seconds. A cleanup screen deletes only these, so nothing is
/// deleted unseen.
///
/// Drawn is not the same as seen: a lazy stack draws rows under a tray and a
/// little past the screen's edges. Nor is a moment in view: a layout pass
/// can put a row in the viewport for a frame, and a fling carries rows
/// through it faster than anyone looks. Hence the dwell, as with ad
/// viewability.
///
/// Frames and the viewport are in the same coordinates (in SwiftUI, global)
/// and can come in either order: when the viewport changes, the frames
/// already reported are checked again. Times are seconds on any clock that
/// only goes forward. An item once seen stays seen.
///
/// Frames are reported whenever they change, so an item with no report since
/// it came into view stayed where it was: when it leaves, or is let go, a
/// dwell it completed by then counts, even if nobody settled in time.
public struct SeenOnScreen<ID: Hashable & Sendable>: Sendable {
    /// Every item that has been on screen.
    public private(set) var ids: Set<ID> = []

    /// The part of the screen the items can be seen in; null until
    /// measured, and then nothing is in view.
    public private(set) var viewport = CGRect.null

    /// How long an item's middle must stay in view to count.
    public let dwell: TimeInterval

    /// The latest frame of each item the list holds.
    private var frames: [ID: CGRect] = [:]
    /// When each item not yet seen came into view, while it stays there.
    private var since: [ID: TimeInterval] = [:]

    /// - Parameter dwell: long enough that a layout pass or a fling does not
    ///   count, short enough that looking does.
    public init(dwell: TimeInterval = 0.3) {
        self.dwell = dwell
    }

    /// When `settle(at:)` would next count an item, if one is waiting in
    /// view: a screen at rest reports no frames, so it has to ask then.
    public var nextSettle: TimeInterval? {
        since.values.min().map { $0 + dwell }
    }

    /// The viewport changed: items in the new one start their dwell, and
    /// items out of it stop.
    public mutating func setViewport(_ viewport: CGRect, at time: TimeInterval) {
        self.viewport = viewport
        for (id, frame) in frames {
            track(id, frame, at: time)
        }
    }

    /// Records where an item is now. Returns whether this made it seen for
    /// the first time: a dwell completed by `time`, in view or just left.
    @discardableResult
    public mutating func report(_ id: ID, at frame: CGRect, time: TimeInterval) -> Bool {
        let wasSeen = ids.contains(id)
        frames[id] = frame
        track(id, frame, at: time)
        settle(id, at: time)
        return !wasSeen && ids.contains(id)
    }

    /// Counts the items that have stayed in view for `dwell` by `time`.
    /// Returns whether any did.
    @discardableResult
    public mutating func settle(at time: TimeInterval) -> Bool {
        var counted = false
        for id in Array(since.keys) {
            if settle(id, at: time) { counted = true }
        }
        return counted
    }

    /// The list let go of the item at `time`: a dwell it completed by then
    /// counts, and its last frame goes stale, so a new viewport must not
    /// count it as seen there. Whether it was seen stays.
    public mutating func forget(_ id: ID, at time: TimeInterval) {
        settle(id, at: time)
        frames[id] = nil
        since[id] = nil
    }

    private func isInView(_ frame: CGRect) -> Bool {
        viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private mutating func track(_ id: ID, _ frame: CGRect, at time: TimeInterval) {
        guard !ids.contains(id) else { return }
        if !isInView(frame) {
            // It stayed in view until now: a dwell completed meanwhile counts.
            settle(id, at: time)
            since[id] = nil
        } else if since[id] == nil {
            since[id] = time
        }
    }

    @discardableResult
    private mutating func settle(_ id: ID, at time: TimeInterval) -> Bool {
        guard let start = since[id], time - start >= dwell else { return false }
        since[id] = nil
        ids.insert(id)
        return true
    }
}
