import Foundation
import IdeaLabCore
import Testing

private let start = LedgerSamples.referenceNow

/// A photo taken `seconds` after `start`.
private func shot(
    _ id: String, at seconds: TimeInterval = 0, sharpness: Double = 0.5, bytes: Int64 = 1_000_000, favorite: Bool = false
) -> SimilarPhoto {
    SimilarPhoto(
        CleanupItem(id: id, category: .similar, bytes: bytes, date: start.addingTimeInterval(seconds), isFavorite: favorite),
        sharpness: sharpness
    )
}

/// Photos look alike when their ids start with the same letter: "a1" and
/// "a2" do, "a1" and "b1" do not.
private func sameLetter(_ a: SimilarPhoto, _ b: SimilarPhoto) -> Bool {
    a.id.first == b.id.first
}

/// Taps a photo in the review: `#expect` cannot call a mutating method itself.
private func tap(_ review: inout SimilarReview, _ id: String) -> Bool {
    review.toggle(id)
}

private func ids(_ groups: [SimilarGroup]) -> [[String]] {
    groups.map { $0.photos.map(\.id) }
}

@Suite("Similar photos: the group")
struct SimilarGroupTests {
    @Test("Oldest first, then by id; a repeated id is its first record, a favourite if any record is")
    func order() throws {
        let group = try #require(SimilarGroup([
            shot("c", at: 20), shot("b", at: 10, bytes: 1), shot("a", at: 20), shot("b", at: 99, favorite: true),
        ]))
        #expect(group.photos.map(\.id) == ["b", "a", "c"])
        #expect(group.photos[0].item.bytes == 1)
        #expect(group.photos[0].item.isFavorite)
        #expect(group.id == "b")
        #expect(group.latestDate == start.addingTimeInterval(20))
    }

    @Test("Fewer than two photos make no group")
    func tooSmall() {
        #expect(SimilarGroup([]) == nil)
        #expect(SimilarGroup([shot("a")]) == nil)
        #expect(SimilarGroup([shot("a"), shot("a", at: 5)]) == nil)
    }

    @Test("The sharpest wins; ties go to the larger file, then the earlier photo, then the id")
    func sharpest() throws {
        func sharpest(_ photos: [SimilarPhoto]) throws -> String {
            try #require(SimilarGroup(photos)).sharpest.id
        }
        #expect(try sharpest([shot("a", sharpness: 0.4), shot("b", sharpness: 0.9), shot("c", sharpness: 0.7)]) == "b")
        #expect(try sharpest([shot("a", sharpness: 0.9, bytes: 1), shot("b", sharpness: 0.9, bytes: 2)]) == "b")
        #expect(try sharpest([shot("a", at: 5, sharpness: 0.9), shot("b", at: 1, sharpness: 0.9)]) == "b")
        #expect(try sharpest([shot("b", sharpness: 0.9), shot("a", sharpness: 0.9)]) == "a")
        // Any scale works, negative ones included.
        #expect(try sharpest([shot("a", sharpness: -3), shot("b", sharpness: -1)]) == "b")
    }

    @Test("A sharpness that is not a number is the least sharp, and the photo stays equal to itself")
    func notANumber() throws {
        let unmeasured = shot("a", sharpness: .nan)
        #expect(unmeasured.sharpness == -.infinity)
        #expect(unmeasured == unmeasured)
        #expect(try #require(SimilarGroup([unmeasured, shot("b", sharpness: -1_000)])).sharpest.id == "b")
        var changed = shot("c", sharpness: 1)
        changed.sharpness = .nan
        #expect(changed.sharpness == -.infinity)
    }

    @Test("The suggestion keeps the sharpest and every favourite, even a blurrier one")
    func suggestion() throws {
        let group = try #require(SimilarGroup([
            shot("a", sharpness: 0.2, favorite: true), shot("b", sharpness: 0.9), shot("c", sharpness: 0.5),
        ]))
        #expect(group.suggestedKeep == ["a", "b"])
        let plain = try #require(SimilarGroup([shot("a", sharpness: 0.2), shot("b", sharpness: 0.9)]))
        #expect(plain.suggestedKeep == ["b"])
    }
}

@Suite("Similar photos: grouping")
struct SimilarGroupingTests {
    @Test("A burst of look-alikes is one group; a photo with no look-alike is left out")
    func burst() {
        let groups = SimilarGrouping.groups(
            [shot("a1", at: 0), shot("a2", at: 5), shot("b1", at: 8), shot("a3", at: 9)],
            alike: sameLetter
        )
        #expect(ids(groups) == [["a1", "a2", "a3"]])
    }

    @Test("The window counts from the group's latest photo, and its edge is in")
    func window() {
        // Each photo 60 s after the one before: one group, though it lasts 3 minutes.
        let chain = SimilarGrouping.groups((0...3).map { shot("a\($0)", at: Double($0) * 60) }, within: 60, alike: sameLetter)
        #expect(ids(chain) == [["a0", "a1", "a2", "a3"]])
        // One second more is a new moment.
        let split = SimilarGrouping.groups(
            [shot("a0", at: 0), shot("a1", at: 60), shot("a2", at: 121), shot("a3", at: 150)],
            within: 60, alike: sameLetter
        )
        #expect(ids(split) == [["a2", "a3"], ["a0", "a1"]])
    }

    @Test("A group that takes a photo stays open a window from it; the others close on time")
    func windowAfterJoining() {
        // a's group starts first but takes the photo before b2, which comes
        // 190 s after b's last photo: a new moment, whichever group started
        // first.
        let photos = [shot("a0", at: 0), shot("b1", at: 10), shot("a1", at: 100), shot("b2", at: 200)]
        #expect(ids(SimilarGrouping.groups(photos, alike: sameLetter)) == [["a0", "a1"]])
    }

    @Test("A photo joins only a group whose every photo it looks like, so a slow pan does not chain")
    func everyPhoto() {
        let alike: Set<Set<String>> = [["a", "b"], ["b", "c"]]
        let groups = SimilarGrouping.groups([shot("a", at: 0), shot("b", at: 1), shot("c", at: 2)]) { x, y in
            alike.contains([x.id, y.id])
        }
        #expect(ids(groups) == [["a", "b"]])
    }

    @Test("Two subjects shot in turn make two groups")
    func interleaved() {
        let groups = SimilarGrouping.groups(
            [shot("a1", at: 0), shot("b1", at: 1), shot("a2", at: 2), shot("b2", at: 3), shot("a3", at: 4)],
            alike: sameLetter
        )
        #expect(ids(groups) == [["a1", "a2", "a3"], ["b1", "b2"]])
    }

    @Test("A photo like two open groups joins the one with the most recent photo")
    func mostRecent() {
        // An x and a y never look alike, so they make two groups; z looks like
        // every photo.
        let alike: (SimilarPhoto, SimilarPhoto) -> Bool = { a, b in
            Set([a.id.first, b.id.first]) != ["x", "y"]
        }
        let groups = SimilarGrouping.groups(
            [shot("x1", at: 0), shot("y1", at: 10), shot("x2", at: 20), shot("y2", at: 30), shot("z", at: 35)],
            alike: alike
        )
        #expect(ids(groups) == [["y1", "y2", "z"], ["x1", "x2"]])
        // The group started first can be the one with the most recent photo.
        let later = SimilarGrouping.groups(
            [shot("x1", at: 0), shot("y1", at: 10), shot("y2", at: 20), shot("x2", at: 30), shot("z", at: 35)],
            alike: alike
        )
        #expect(ids(later) == [["x1", "x2", "z"], ["y1", "y2"]])
    }

    @Test("Photos are taken in date order, whatever order they come in")
    func unsorted() {
        let groups = SimilarGrouping.groups(
            [shot("a3", at: 500), shot("a1", at: 0), shot("a2", at: 100), shot("a4", at: 580)],
            within: 120, alike: sameLetter
        )
        #expect(ids(groups) == [["a3", "a4"], ["a1", "a2"]])
    }

    @Test("Newest group first; groups ending at the same moment go by id")
    func newestFirst() {
        let groups = SimilarGrouping.groups(
            [shot("c1", at: 0), shot("c2", at: 10), shot("a1", at: 1_000), shot("a2", at: 1_010),
             shot("b1", at: 1_000), shot("b2", at: 1_010)],
            alike: sameLetter
        )
        #expect(ids(groups) == [["a1", "a2"], ["b1", "b2"], ["c1", "c2"]])
    }

    @Test("A negative window, or one that is not a number, groups only photos taken at the same instant")
    func badWindow() {
        let photos = [shot("a1", at: 0), shot("a2", at: 0), shot("a3", at: 1)]
        for window in [-5, .nan] as [TimeInterval] {
            #expect(ids(SimilarGrouping.groups(photos, within: window, alike: sameLetter)) == [["a1", "a2"]])
        }
        #expect(ids(SimilarGrouping.groups(photos, within: .infinity, alike: sameLetter)) == [["a1", "a2", "a3"]])
    }

    @Test("A repeated id is one photo, a favourite if any record is")
    func repeated() throws {
        let groups = SimilarGrouping.groups(
            [shot("a1", at: 0), shot("a2", at: 1), shot("a1", at: 2, favorite: true)],
            alike: sameLetter
        )
        let group = try #require(groups.first)
        #expect(group.photos.map(\.id) == ["a1", "a2"])
        #expect(group.photos[0].item.isFavorite)
    }

    @Test("A date that is not a finite number is the distant past, and the photo stays equal to itself")
    func badDates() {
        let undated = SimilarPhoto(
            CleanupItem(id: "a0", category: .similar, bytes: 1, date: Date(timeIntervalSinceReferenceDate: .nan)),
            sharpness: 0.5
        )
        #expect(undated.item.date == .distantPast)
        #expect(undated == undated)
        var changed = shot("a9")
        changed.item.date = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(changed.item.date == .distantPast)
        // Undated photos group only with each other, and in any input order.
        let photos = [shot("a1", at: 0), undated, shot("a2", at: 1), shot("a3", at: 31_536_000), changed]
        let expected = [["a1", "a2"], ["a0", "a9"]]
        #expect(ids(SimilarGrouping.groups(photos, alike: sameLetter)) == expected)
        #expect(ids(SimilarGrouping.groups(photos.reversed(), alike: sameLetter)) == expected)
    }

    @Test("Only the most recent open groups are tried")
    func openGroupLimit() {
        // Seventeen subjects shot once each, then the second and the first again.
        let limit = SimilarGrouping.openGroupLimit
        #expect(limit == 16)
        var photos = (1...(limit + 1)).map { shot("s\($0)-1", at: Double($0)) }
        photos.append(shot("s2-2", at: 100))
        photos.append(shot("s1-2", at: 101))
        let bySubject: (SimilarPhoto, SimilarPhoto) -> Bool = { a, b in a.id.split(separator: "-")[0] == b.id.split(separator: "-")[0] }
        // s2 is among the 16 most recent groups; s1, the oldest of 17, is not.
        #expect(ids(SimilarGrouping.groups(photos, alike: bySubject)) == [["s2-1", "s2-2"]])
    }

    @Test("Photos sharing one timestamp by the hundred are compared a bounded number of times")
    func bulkImport() {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let photos = (0..<400).map { shot("p\($0)") }
        let groups = SimilarGrouping.groups(photos) { _, _ in
            counter.calls += 1
            return false
        }
        #expect(groups.isEmpty)
        #expect(counter.calls <= 400 * SimilarGrouping.openGroupLimit)
    }
}

@Suite("Similar photos: the review")
struct SimilarReviewTests {
    /// Two groups, newest first:
    /// - "b": b1 (favourite, blurry), b2 (sharpest), b3.
    /// - "a": a1, a2 (sharpest), a3, a4.
    private func review() -> SimilarReview {
        SimilarReview(photos: [
            shot("a1", at: 0, sharpness: 0.3, bytes: 1_000),
            shot("a2", at: 1, sharpness: 0.9, bytes: 2_000),
            shot("a3", at: 2, sharpness: 0.5, bytes: 3_000),
            shot("a4", at: 3, sharpness: 0.1, bytes: 4_000),
            shot("b1", at: 1_000, sharpness: 0.2, bytes: 10_000, favorite: true),
            shot("b2", at: 1_001, sharpness: 0.8, bytes: 20_000),
            shot("b3", at: 1_002, sharpness: 0.4, bytes: 30_000),
        ], alike: sameLetter)
    }

    @Test("It starts from the suggestions: everything but the sharpest and the favourites, group by group")
    func suggestions() {
        let review = review()
        #expect(ids(review.groups) == [["b1", "b2", "b3"], ["a1", "a2", "a3", "a4"]])
        #expect(review.toDelete.map(\.id) == ["b3", "a1", "a3", "a4"])
        #expect(review.bytesToFree == 38_000)
        #expect(review.toDelete(in: "a1").map(\.id) == ["a1", "a3", "a4"])
        #expect(review.isKept("b1") && review.isKept("b2") && review.isKept("a2"))
    }

    @Test("A tap keeps a photo, or lets it go")
    func toggle() {
        var review = review()
        #expect(tap(&review, "a3"))
        #expect(review.toDelete(in: "a1").map(\.id) == ["a1", "a4"])
        #expect(tap(&review, "a2"))
        #expect(review.toDelete(in: "a1").map(\.id) == ["a1", "a2", "a4"])
        #expect(review.toDelete.map(\.id) == ["b3", "a1", "a2", "a4"])
        #expect(tap(&review, "a2"))
        #expect(review.toDelete(in: "a1").map(\.id) == ["a1", "a4"])
    }

    @Test("A favourite is always kept")
    func favorite() {
        var review = review()
        #expect(!tap(&review, "b1"))
        #expect(review.isKept("b1"))
        review.suggest(in: "b1")
        #expect(review.isKept("b1"))
    }

    @Test("A group always keeps one photo")
    func lastOne() {
        var review = review()
        #expect(!tap(&review, "a2"))
        #expect(review.isKept("a2"))
        #expect(tap(&review, "a1"))
        #expect(tap(&review, "a2"))
        #expect(!tap(&review, "a1"))
        #expect(review.toDelete(in: "a1").map(\.id) == ["a2", "a3", "a4"])
        // "b" keeps its favourite, so its sharpest can go.
        #expect(tap(&review, "b2"))
        #expect(review.toDelete(in: "b1").map(\.id) == ["b2", "b3"])
    }

    @Test("A photo in no group is refused")
    func unknown() {
        var review = review()
        let before = review
        #expect(!tap(&review, "zz"))
        review.keepAll(in: "zz")
        review.suggest(in: "zz")
        #expect(review == before)
        #expect(review.toDelete(in: "zz").isEmpty)
    }

    @Test("Keep all skips a group; suggest brings its suggestion back")
    func keepAllAndSuggest() {
        var review = review()
        review.keepAll(in: "a1")
        #expect(review.toDelete(in: "a1").isEmpty)
        #expect(review.toDelete.map(\.id) == ["b3"])
        review.toggle("a4")
        review.suggest(in: "a1")
        #expect(review.toDelete(in: "a1").map(\.id) == ["a1", "a3", "a4"])
        #expect(review.toDelete(in: "b1").map(\.id) == ["b3"])
    }

    @Test("A photo in two groups stays in the first; a group left with one photo is dropped")
    func overlapping() throws {
        let first = try #require(SimilarGroup([shot("a1"), shot("a2", at: 1)]))
        let second = try #require(SimilarGroup([shot("a2", at: 1), shot("a3", at: 2), shot("a4", at: 3)]))
        let third = try #require(SimilarGroup([shot("a1"), shot("a5", at: 4)]))
        let review = SimilarReview(groups: [first, second, third])
        #expect(ids(review.groups) == [["a1", "a2"], ["a3", "a4"]])
    }

    @Test("A photo in two groups is a favourite if any of its records is")
    func favoriteInLaterGroup() throws {
        let first = try #require(SimilarGroup([shot("x", sharpness: 0.1), shot("y", at: 1, sharpness: 0.9)]))
        let second = try #require(SimilarGroup([shot("x", favorite: true), shot("z", at: 2), shot("w", at: 3)]))
        let review = SimilarReview(groups: [first, second])
        #expect(ids(review.groups) == [["x", "y"], ["z", "w"]])
        #expect(review.isKept("x"))
        #expect(!review.toDelete.map(\.id).contains("x"))
        #expect(review.groups[0].photos[0].item.isFavorite)
    }

    @Test("A group dropped for having one photo left takes none from the groups after it")
    func droppedGroupTakesNothing() throws {
        let groups = try [["a", "b"], ["b", "c"], ["c", "d"]].map { pair in
            try #require(SimilarGroup(pair.enumerated().map { shot($1, at: Double($0)) }))
        }
        #expect(ids(SimilarReview(groups: groups).groups) == [["a", "b"], ["c", "d"]])
    }

    @Test("Deleted photos leave the review; a group down to one photo is done")
    func remove() {
        var review = review()
        review.remove(["b3", "a1", "a3"])
        #expect(ids(review.groups) == [["b1", "b2"], ["a2", "a4"]])
        #expect(review.toDelete.map(\.id) == ["a4"])
        review.remove(["a4"])
        #expect(ids(review.groups) == [["b1", "b2"]])
        #expect(review.toDelete.isEmpty)
        #expect(!review.isKept("a2"))
    }

    @Test("A group whose kept photos were deleted elsewhere keeps its new suggestion, never deleting all that is left")
    func keptPhotoGone() {
        var review = review()
        review.remove(["a2"])
        #expect(ids(review.groups).last == ["a1", "a3", "a4"])
        #expect(review.toDelete(in: "a1").map(\.id) == ["a1", "a4"])
        #expect(review.isKept("a3"))
    }

    @Test("Removing nothing, or photos in no group, changes nothing")
    func removeNothing() {
        var review = review()
        let before = review
        review.remove([])
        review.remove(["zz"])
        #expect(review == before)
    }

    @Test("Whatever is tapped or deleted, every group keeps a photo and every favourite")
    func invariants() {
        var random = SeededRandom(seed: 7)
        for _ in 0..<200 {
            var review = review()
            for _ in 0..<12 {
                let all = review.groups.flatMap(\.photos)
                guard !all.isEmpty else { break }
                let photo = all[Int(random.next() % UInt64(all.count))]
                switch random.next() % 5 {
                case 0: review.keepAll(in: review.groups[Int(random.next() % UInt64(review.groups.count))].id)
                case 1: review.suggest(in: review.groups[Int(random.next() % UInt64(review.groups.count))].id)
                case 2: review.remove([photo.id])
                default: review.toggle(photo.id)
                }
                for group in review.groups {
                    #expect(group.photos.contains { review.isKept($0.id) })
                    #expect(group.photos.allSatisfy { !$0.item.isFavorite || review.isKept($0.id) })
                }
                #expect(Set(review.toDelete.map(\.id)).isDisjoint(with: all.filter(\.item.isFavorite).map(\.id)))
            }
        }
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Similar photos: samples")
struct SimilarSamplesTests {
    @Test("Six moments, newest first; each keeps its sharp shot, and the favourite is kept too")
    func sampleReview() {
        let review = CleanupSamples.similarReview()
        #expect(review.groups.map(\.photos.count) == [5, 6, 3, 4, 2, 3])
        #expect(review.groups.map(\.sharpest.id) == [
            "similar-1-3", "similar-2-2", "similar-3-1", "similar-4-4", "similar-5-1", "similar-6-2",
        ])
        #expect(review.isKept("similar-3-3"))
        #expect(review.toDelete.count == 23 - 6 - 1)
        #expect(CleanupSamples.similarPhotos() == CleanupSamples.similarPhotos())
    }

    @Test("Only shots of one moment look alike")
    func alike() {
        let photos = CleanupSamples.similarPhotos()
        #expect(CleanupSamples.looksAlike(photos[0], photos[1]))
        #expect(!CleanupSamples.looksAlike(photos[0], photos[5]))
        #expect(!CleanupSamples.looksAlike(shot("similar-1"), shot("similar-1")))
    }
}
