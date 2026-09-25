import Foundation

/// Why a photo is offered for cleanup. Detected on the device (Vision /
/// Core ML); the kit only models the result.
public enum CleanupCategory: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case screenshots
    case similar
    case blurry
    case documents
    case qrCodes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenshots: "Ảnh chụp màn hình"
        case .similar: "Ảnh gần giống nhau"
        case .blurry: "Ảnh mờ, rung"
        case .documents: "Hoá đơn, giấy tờ"
        case .qrCodes: "Mã QR"
        }
    }
}

/// One photo offered for cleanup.
public struct CleanupItem: Identifiable, Hashable, Sendable {
    /// `PHAsset.localIdentifier` in a real app.
    public var id: String
    public var category: CleanupCategory
    public var bytes: Int64
    public var date: Date
    /// Favourites are never offered for deletion, whatever the detector says.
    public var isFavorite: Bool

    public init(id: String, category: CleanupCategory, bytes: Int64, date: Date, isFavorite: Bool = false) {
        self.id = id
        self.category = category
        self.bytes = max(bytes, 0)
        self.date = date
        self.isFavorite = isFavorite
    }
}

/// A swipe-through: keep or delete one photo at a time, undo the last swipe,
/// and change your mind again on the review step. Nothing is deleted by the
/// session itself — `toDelete` goes to PhotoKit only after the user confirms,
/// and iOS still keeps the photos in "Đã xoá gần đây" for 30 days.
public struct CleanupSession: Hashable, Sendable {
    public enum Decision: Hashable, Sendable {
        case keep
        case delete
    }

    /// The deck, in the order it is shown.
    public private(set) var items: [CleanupItem]
    private var decisions: [CleanupItem.ID: Decision] = [:]
    /// Decided item ids, most recent last, for undo.
    private var history: [CleanupItem.ID] = []
    /// Swiped to delete, then kept on the review step.
    private var rescued: Set<CleanupItem.ID> = []

    /// Favourites and repeated ids are left out: a repeated id would make one
    /// swipe decide two cards.
    public init(items: [CleanupItem]) {
        self.items = CleanupMath.candidates(items)
    }

    /// The card on top of the deck: the first undecided item.
    public var current: CleanupItem? {
        items.first { decisions[$0.id] == nil }
    }

    public var decidedCount: Int { decisions.count }
    public var remainingCount: Int { items.count - decisions.count }
    public var isFinished: Bool { remainingCount == 0 }

    public func decision(for id: CleanupItem.ID) -> Decision? {
        decisions[id]
    }

    /// The most recent swipe, which `undo()` takes back: the UI flies the card
    /// back in from that side.
    public var lastDecision: Decision? {
        history.last.flatMap { decisions[$0] }
    }

    /// Decides the card on top. Returns that item, or `nil` when the deck is
    /// already empty.
    @discardableResult
    public mutating func decide(_ decision: Decision) -> CleanupItem? {
        guard let item = current else { return nil }
        decisions[item.id] = decision
        history.append(item.id)
        return item
    }

    /// Takes back the most recent swipe; that card is on top again, and a
    /// rescue made on the review step for it is forgotten.
    @discardableResult
    public mutating func undo() -> CleanupItem? {
        guard let id = history.popLast() else { return nil }
        decisions[id] = nil
        rescued.remove(id)
        return items.first { $0.id == id }
    }

    /// Everything swiped to delete, in deck order: the review step's grid.
    /// A photo stays in it when it is rescued, so it can be marked again.
    public var swipedToDelete: [CleanupItem] {
        items.filter { decisions[$0.id] == .delete }
    }

    public func isMarkedForDeletion(_ id: CleanupItem.ID) -> Bool {
        decisions[id] == .delete && !rescued.contains(id)
    }

    /// On the review step: keep a photo swiped to delete, or mark it again.
    /// Returns `false` for a photo that was never swiped to delete.
    @discardableResult
    public mutating func toggleMark(_ id: CleanupItem.ID) -> Bool {
        guard decisions[id] == .delete else { return false }
        if rescued.remove(id) == nil {
            rescued.insert(id)
        }
        return true
    }

    /// Marked for deletion now, in deck order.
    public var toDelete: [CleanupItem] {
        items.filter { isMarkedForDeletion($0.id) }
    }

    public var bytesToFree: Int64 {
        CleanupMath.bytes(of: toDelete)
    }
}

public struct CategorySummary: Identifiable, Hashable, Sendable {
    public var category: CleanupCategory
    public var count: Int
    public var bytes: Int64
    public var id: CleanupCategory { category }

    public init(category: CleanupCategory, count: Int, bytes: Int64) {
        self.category = category
        self.count = count
        self.bytes = bytes
    }
}

public enum CleanupMath {
    /// What may be offered for deletion: favourites and repeated ids removed,
    /// order kept.
    public static func candidates(_ items: [CleanupItem]) -> [CleanupItem] {
        var seen = Set<CleanupItem.ID>()
        return items.filter { !$0.isFavorite && seen.insert($0.id).inserted }
    }

    /// Count and size per category, in `CleanupCategory` order, empty
    /// categories left out. Only `candidates` are counted.
    public static func summary(of items: [CleanupItem]) -> [CategorySummary] {
        let candidates = candidates(items)
        return CleanupCategory.allCases.compactMap { category in
            let matching = candidates.filter { $0.category == category }
            guard !matching.isEmpty else { return nil }
            return CategorySummary(category: category, count: matching.count, bytes: bytes(of: matching))
        }
    }

    /// Saturating sum: a corrupt size can't wrap the total around to negative.
    public static func bytes(of items: [CleanupItem]) -> Int64 {
        items.reduce(0) { total, item in
            let (sum, overflow) = total.addingReportingOverflow(item.bytes)
            return overflow ? .max : sum
        }
    }
}

/// "Miễn phí dọn 100 ảnh đầu": how many more photos the free tier deletes.
/// Only confirmed deletions count, so browsing and swiping stay free.
public struct FreeAllowance: Hashable, Sendable, Codable {
    public let limit: Int
    public private(set) var used: Int

    public init(limit: Int = 100, used: Int = 0) {
        self.limit = max(limit, 0)
        self.used = max(used, 0)
    }

    public var remaining: Int { max(limit - used, 0) }

    /// How many of `count` photos the free tier covers now.
    public func covered(of count: Int) -> Int {
        min(max(count, 0), remaining)
    }

    /// Record a confirmed deletion.
    public mutating func use(_ count: Int) {
        let (sum, overflow) = used.addingReportingOverflow(max(count, 0))
        used = overflow ? .max : sum
    }

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(limit: try container.decode(Int.self, forKey: .limit), used: try container.decode(Int.self, forKey: .used))
    }
}

/// The phone's storage, for the "Đã dùng 118 GB / 128 GB" bar. A real app
/// reads `volumeTotalCapacity` and `volumeAvailableCapacityForImportantUsage`.
public struct StorageStatus: Hashable, Sendable {
    public let capacity: Int64
    public let available: Int64

    /// `available` is clamped into `0...capacity`.
    public init(capacity: Int64, available: Int64) {
        self.capacity = max(capacity, 0)
        self.available = min(max(available, 0), self.capacity)
    }

    public var used: Int64 { capacity - available }

    /// Share of the phone in use, `0...1`; `0` for an unknown (zero) capacity.
    public var usedFraction: Double {
        capacity > 0 ? Double(used) / Double(capacity) : 0
    }

    /// Share in use after freeing `bytes` (never below zero).
    public func usedFraction(afterFreeing bytes: Int64) -> Double {
        guard capacity > 0 else { return 0 }
        return Double(used - min(max(bytes, 0), used)) / Double(capacity)
    }
}

/// Storage sizes the way iOS Settings counts them — decimal units, 1 GB =
/// 1.000.000.000 bytes — with the Vietnamese decimal comma: "1,2 GB",
/// "350 MB", "12,5 KB". One decimal below 100 of a unit, none from 100 up;
/// a size that rounds up to 1.000 of a unit is said in the next one.
public enum ByteSize {
    public static func string(_ bytes: Int64) -> String {
        let magnitude = UInt64(max(bytes, 0))
        guard magnitude >= 1_000 else { return "\(magnitude)\(VND.nbsp)B" }
        return DecimalUnits.string(magnitude, units: [
            (1_000, "\(VND.nbsp)KB"),
            (1_000_000, "\(VND.nbsp)MB"),
            (1_000_000_000, "\(VND.nbsp)GB"),
            (1_000_000_000_000, "\(VND.nbsp)TB"),
        ])
    }
}
