import Foundation

/// Which items of a scrolling list have been on screen: those whose middle
/// has been inside the viewport, the part of the screen nothing covers. A
/// cleanup screen deletes only these, so nothing is deleted unseen.
///
/// Drawn is not the same as seen: a lazy stack draws rows under a tray and a
/// little past the screen's edges, before anyone could have looked at them.
///
/// Frames and the viewport are in the same coordinates (in SwiftUI, global)
/// and can come in either order: when the viewport changes, the frames
/// already reported are checked again. An item once seen stays seen.
public struct SeenOnScreen<ID: Hashable & Sendable>: Sendable {
    /// Every item that has been on screen.
    public private(set) var ids: Set<ID> = []

    /// The part of the screen the items can be seen in; null until measured,
    /// and then nothing counts as seen.
    public var viewport = CGRect.null {
        didSet {
            for (id, frame) in frames { check(id, frame) }
        }
    }

    /// The latest frame of each item the list holds.
    private var frames: [ID: CGRect] = [:]

    public init() {}

    /// Records where an item is now. Returns whether this made it seen for
    /// the first time.
    @discardableResult
    public mutating func report(_ id: ID, at frame: CGRect) -> Bool {
        frames[id] = frame
        return check(id, frame)
    }

    /// The list let go of the item: its last frame goes stale, and a new
    /// viewport must not count it as seen there. Whether it was seen stays.
    public mutating func forget(_ id: ID) {
        frames[id] = nil
    }

    @discardableResult
    private mutating func check(_ id: ID, _ frame: CGRect) -> Bool {
        guard !ids.contains(id), viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        ids.insert(id)
        return true
    }
}
