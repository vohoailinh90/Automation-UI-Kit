import Foundation

/// A photo the similar-photo detector looked at: the item, and how sharp it
/// is. Both are measured on the device; the kit only takes the results.
/// - Sharpness: for example the variance of the image's Laplacian (vImage),
///   or Vision's aesthetics score. Only photos of one group are compared, so
///   any scale works, as long as higher is sharper.
/// - Whether two photos look alike, for `SimilarGrouping.groups`: for example
///   the distance between their `VNFeaturePrintObservation`s, under a
///   threshold.
public struct SimilarPhoto: Identifiable, Hashable, Sendable {
    public var item: CleanupItem
    /// Higher is sharper. A value that is not a number is stored as −∞: the
    /// least sharp, never picked over a measured photo. It also keeps the
    /// photo equal to itself, which NaN would not be.
    public var sharpness: Double {
        didSet { if sharpness.isNaN { sharpness = -.infinity } }
    }

    public var id: CleanupItem.ID { item.id }

    public init(_ item: CleanupItem, sharpness: Double) {
        self.item = item
        self.sharpness = sharpness.isNaN ? -.infinity : sharpness
    }
}

/// Photos of one moment that look alike. Every photo in a group looks like
/// every other one, so whichever is kept, each photo deleted still has a
/// look-alike in the library.
public struct SimilarGroup: Identifiable, Hashable, Sendable {
    /// Oldest first, then by id; two or more, each id once.
    public let photos: [SimilarPhoto]

    /// Makes a group of `photos`, oldest first. A repeated id is one photo:
    /// its first record, a favourite if any of its records is. `nil` for
    /// fewer than two photos: there is nothing to choose between.
    public init?(_ photos: [SimilarPhoto]) {
        let unique = SimilarGrouping.unique(photos)
        guard unique.count >= 2 else { return nil }
        self.photos = unique.sorted(by: SimilarGrouping.isTakenEarlier)
    }

    /// The first photo's id.
    public var id: CleanupItem.ID { photos[0].id }

    /// When the last photo was taken.
    public var latestDate: Date { photos[photos.count - 1].item.date }

    /// The one to keep when only one is kept: the highest sharpness. Ties go
    /// to the larger file (more detail), then the earlier photo, then the
    /// lower id.
    public var sharpest: SimilarPhoto {
        photos.max { SimilarGrouping.isSharper($1, than: $0) } ?? photos[0]
    }

    /// What the review keeps at first: the sharpest photo and every
    /// favourite. Favourites are never deleted, and the sharpest is kept even
    /// next to a favourite, so no suggestion deletes the best shot.
    public var suggestedKeep: Set<CleanupItem.ID> {
        Set(photos.lazy.filter(\.item.isFavorite).map(\.id)).union([sharpest.id])
    }
}

public enum SimilarGrouping {
    /// Groups photos taken in bursts of look-alikes, newest group first (by
    /// its latest photo, then its id).
    ///
    /// Photos are taken in date order. Each joins the group with the most
    /// recent photo among those whose latest photo is at most `window` older
    /// and whose every photo it looks like (`alike`). Otherwise it starts a
    /// group of its own. Groups of one are left out: there is nothing to
    /// choose between.
    ///
    /// Every photo, not only the last one: comparing with the last one would
    /// chain a slow pan from one end to the other, until photos that look
    /// nothing alike share a group and the one kept stands in for none of
    /// them. Every group within the window is tried, not only the newest, so
    /// shots of two subjects taken in turn still make two groups.
    ///
    /// A repeated id is one photo: its first record, a favourite if any of
    /// its records is. A window that is negative or not a number is zero.
    public static func groups(
        _ photos: [SimilarPhoto],
        within window: TimeInterval = 120,
        alike: (SimilarPhoto, SimilarPhoto) -> Bool
    ) -> [SimilarGroup] {
        let window = window.isNaN ? 0 : max(window, 0)
        var groups: [[SimilarPhoto]] = []
        // Groups that can still take a photo: their latest photo is within
        // the window of the photo being placed. Photos come in date order, so
        // a group that falls out of the window never comes back.
        var open: [Int] = []
        for photo in unique(photos).sorted(by: isTakenEarlier) {
            open.removeAll { photo.item.date.timeIntervalSince(groups[$0].last!.item.date) > window }
            let candidates = open.sorted { a, b in
                let (latestA, latestB) = (groups[a].last!.item.date, groups[b].last!.item.date)
                return latestA != latestB ? latestA > latestB : a > b
            }
            if let index = candidates.first(where: { index in groups[index].allSatisfy { alike(photo, $0) } }) {
                groups[index].append(photo)
            } else {
                groups.append([photo])
                open.append(groups.count - 1)
            }
        }
        return groups.compactMap(SimilarGroup.init)
            .sorted { a, b in a.latestDate != b.latestDate ? a.latestDate > b.latestDate : a.id < b.id }
    }

    /// Each id once, in the order given: its first record, marked a favourite
    /// if any of its records is.
    static func unique(_ photos: [SimilarPhoto]) -> [SimilarPhoto] {
        let favorites = Set(photos.lazy.filter(\.item.isFavorite).map(\.id))
        var seen = Set<CleanupItem.ID>()
        return photos.compactMap { photo in
            guard seen.insert(photo.id).inserted else { return nil }
            var photo = photo
            photo.item.isFavorite = favorites.contains(photo.id)
            return photo
        }
    }

    static func isTakenEarlier(_ a: SimilarPhoto, _ b: SimilarPhoto) -> Bool {
        a.item.date != b.item.date ? a.item.date < b.item.date : a.id < b.id
    }

    static func isSharper(_ a: SimilarPhoto, than b: SimilarPhoto) -> Bool {
        if a.sharpness != b.sharpness { return a.sharpness > b.sharpness }
        if a.item.bytes != b.item.bytes { return a.item.bytes > b.item.bytes }
        return isTakenEarlier(a, b)
    }
}

/// Which photos of each similar group to keep. It starts from each group's
/// suggestion — the sharpest photo and every favourite — and a tap keeps a
/// photo or lets it go. Two things hold whatever is tapped: favourites are
/// kept, and every group keeps at least one photo. The point is one good
/// copy of each moment, never none.
///
/// Nothing is deleted here: `toDelete` goes to PhotoKit once the user
/// confirms, and iOS keeps the photos in "Đã xoá gần đây" for 30 days.
public struct SimilarReview: Hashable, Sendable {
    /// Newest first, as given.
    public private(set) var groups: [SimilarGroup]
    /// Across all groups: each photo is in one group only.
    private var kept: Set<CleanupItem.ID>

    /// A photo in more than one of `groups` stays in the first; a group left
    /// with fewer than two photos is dropped.
    public init(groups: [SimilarGroup]) {
        var seen = Set<CleanupItem.ID>()
        self.groups = groups.compactMap { group in
            SimilarGroup(group.photos.filter { seen.insert($0.id).inserted })
        }
        kept = self.groups.reduce(into: []) { $0.formUnion($1.suggestedKeep) }
    }

    /// Groups `photos` with `SimilarGrouping.groups` and starts from their
    /// suggestions.
    public init(photos: [SimilarPhoto], within window: TimeInterval = 120, alike: (SimilarPhoto, SimilarPhoto) -> Bool) {
        self.init(groups: SimilarGrouping.groups(photos, within: window, alike: alike))
    }

    public func isKept(_ id: CleanupItem.ID) -> Bool {
        kept.contains(id)
    }

    /// Keeps a photo marked for deletion, or marks a kept one for deletion.
    /// Refused, returning `false`, for a favourite, for the last photo its
    /// group keeps, and for a photo in no group.
    @discardableResult
    public mutating func toggle(_ id: CleanupItem.ID) -> Bool {
        guard let group = groups.first(where: { $0.photos.contains { $0.id == id } }),
              let photo = group.photos.first(where: { $0.id == id }),
              !photo.item.isFavorite
        else { return false }
        if kept.contains(id) {
            guard group.photos.filter({ kept.contains($0.id) }).count > 1 else { return false }
            kept.remove(id)
        } else {
            kept.insert(id)
        }
        return true
    }

    /// Keeps every photo of the group: nothing of it is deleted.
    public mutating func keepAll(in groupID: SimilarGroup.ID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        kept.formUnion(group.photos.map(\.id))
    }

    /// Back to the group's suggestion: the sharpest photo and the favourites.
    public mutating func suggest(in groupID: SimilarGroup.ID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        kept.subtract(group.photos.map(\.id))
        kept.formUnion(group.suggestedKeep)
    }

    /// The group's photos marked for deletion, oldest first.
    public func toDelete(in groupID: SimilarGroup.ID) -> [SimilarPhoto] {
        groups.first { $0.id == groupID }?.photos.filter { !kept.contains($0.id) } ?? []
    }

    /// Everything marked for deletion: group by group, oldest first in each.
    public var toDelete: [CleanupItem] {
        groups.flatMap { group in group.photos.lazy.filter { !kept.contains($0.id) }.map(\.item) }
    }

    public var bytesToFree: Int64 {
        CleanupMath.bytes(of: toDelete)
    }

    /// Takes photos out once PhotoKit has deleted them, or found them already
    /// gone. A group left with one photo is done and leaves the review; its
    /// last photo is not asked about again. A group left without a kept photo
    /// — one was deleted elsewhere — keeps its new suggestion, so it never
    /// asks to delete everything that is left.
    public mutating func remove(_ ids: Set<CleanupItem.ID>) {
        guard !ids.isEmpty else { return }
        groups = groups.compactMap { group in
            guard group.photos.contains(where: { ids.contains($0.id) }) else { return group }
            guard let left = SimilarGroup(group.photos.filter { !ids.contains($0.id) }) else { return nil }
            if !left.photos.contains(where: { kept.contains($0.id) }) {
                kept.formUnion(left.suggestedKeep)
            }
            return left
        }
        let remaining = Set(groups.flatMap { $0.photos.map(\.id) })
        kept.formIntersection(remaining)
    }
}
