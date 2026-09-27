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
    /// What deleting it frees on this device. With iCloud Photos' "Optimise
    /// iPhone Storage" that is the smaller local copy, not the original: an
    /// estimate from the original's size would promise space that never
    /// comes back.
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
    /// Photos taken out by `remove(_:)` once PhotoKit deleted them.
    public private(set) var removedCount = 0
    /// Cards looked at, the deleted ones included: "12/48" stays 12/48
    /// after the 8 marked there are deleted.
    public var seenCount: Int { decisions.count + removedCount }
    /// The deck's size, the deleted photos included.
    public var totalCount: Int { items.count + removedCount }
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
    /// already empty — or, with `expected`, when the card on top is no longer
    /// that one (the deck changed while the card was flying off).
    @discardableResult
    public mutating func decide(_ decision: Decision, expecting expected: CleanupItem.ID? = nil) -> CleanupItem? {
        guard let item = current, expected.map({ $0 == item.id }) ?? true else { return nil }
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

    /// Takes photos out of the session once PhotoKit has deleted them: they
    /// leave the deck, the review grid, the undo history and the count, so
    /// nothing asks to delete them again.
    public mutating func remove(_ ids: Set<CleanupItem.ID>) {
        guard !ids.isEmpty else { return }
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        removedCount += before - items.count
        for id in ids { decisions[id] = nil }
        history.removeAll { ids.contains($0) }
        rescued.subtract(ids)
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
    /// order kept. A photo that is a favourite in any of its records stays out,
    /// even if an older record of it is not.
    public static func candidates(_ items: [CleanupItem]) -> [CleanupItem] {
        let favorites = Set(items.lazy.filter(\.isFavorite).map(\.id))
        var seen = Set<CleanupItem.ID>()
        return items.filter { !favorites.contains($0.id) && seen.insert($0.id).inserted }
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

    /// What a delete button deletes when tapped: the photos it counted when
    /// it was drawn, less any no longer marked, in its order. A tap can land
    /// before the button is drawn again, after a mark was undone, a photo
    /// left, or another came into view; it never deletes a photo the button
    /// did not count, so "Xoá 4 ảnh" never deletes a fifth.
    public static func stillMarked(_ counted: [CleanupItem], in marked: [CleanupItem]) -> [CleanupItem] {
        let ids = Set(marked.lazy.map(\.id))
        return counted.filter { ids.contains($0.id) }
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

    /// Reads a stored allowance. Only what this type writes — a whole count,
    /// zero or more, that fits in `Int` — is taken as it is. Anything else
    /// (negative, fractional, too large, not a number, missing, null, the
    /// wrong type) is corrupt, and counts against the free tier: `used` is
    /// taken as used up and `limit` as zero, never a fresh 100 or a tier that
    /// never runs out. Such a value does not fail the decode either, since
    /// failing would make the app start over with a fresh 100 — and storage
    /// that cannot be read at all should count as used up too:
    /// `FreeAllowance(used: .max)`.
    ///
    /// "Whole" is checked as closely as the decoder can tell: every numeric
    /// read rounds somewhere (JSON's `Decimal` keeps 38 digits). This guards
    /// against corrupt data, not against someone editing the app's files,
    /// who could as easily write a valid `"used": 0`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) -> Int? {
            // `decode(Int.self)` rounds before it checks: it reads
            // "12.0000000000000001" as 12 and "1e-400" as 0. So the number
            // must read as the same Double too — which refuses an exponent
            // out of range — and, where the decoder reads the digits
            // themselves (JSON, as a Decimal), as the same Decimal.
            guard let value = try? container.decode(Int.self, forKey: key), value >= 0,
                  (try? container.decode(Double.self, forKey: key)) == Double(value),
                  (try? container.decode(Decimal.self, forKey: key)).map({ $0 == Decimal(value) }) ?? true
            else { return nil }
            return value
        }
        self.init(limit: count(.limit) ?? 0, used: count(.used) ?? .max)
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
