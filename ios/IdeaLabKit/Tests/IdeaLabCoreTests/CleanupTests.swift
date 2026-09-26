import Foundation
import IdeaLabCore
import Testing

private let nbsp = "\u{00A0}"
private let day = LedgerSamples.referenceNow

private func photo(_ id: String, _ category: CleanupCategory = .screenshots, bytes: Int64 = 1_000_000, favorite: Bool = false) -> CleanupItem {
    CleanupItem(id: id, category: category, bytes: bytes, date: day, isFavorite: favorite)
}

@Suite("Byte sizes")
struct ByteSizeTests {
    @Test(arguments: [
        (0, "0 B"), (999, "999 B"), (1_000, "1 KB"), (12_500, "12,5 KB"),
        (4_650_000, "4,7 MB"), (12_345_678, "12,3 MB"), (99_949_999, "99,9 MB"), (99_950_000, "100 MB"),
        (350_000_000, "350 MB"), (1_234_567_890, "1,2 GB"), (128_000_000_000, "128 GB"),
        (2_000_000_000_000, "2 TB"),
    ] as [(Int64, String)])
    func formats(bytes: Int64, expected: String) {
        #expect(ByteSize.string(bytes) == expected.replacingOccurrences(of: " ", with: nbsp))
    }

    @Test("A size that rounds up to 1.000 of a unit is said in the next one")
    func promotes() {
        #expect(ByteSize.string(999_500) == "1\(nbsp)MB")
        #expect(ByteSize.string(999_960_000) == "1\(nbsp)GB")
        #expect(ByteSize.string(999_499) == "999\(nbsp)KB")
    }

    @Test("Negative and huge sizes don't crash")
    func extremes() {
        #expect(ByteSize.string(-5) == "0\(nbsp)B")
        #expect(ByteSize.string(.max) == "9.223.372\(nbsp)TB")
    }
}

@Suite("Vietnamese counts")
struct VietnameseNumberTests {
    @Test(arguments: [(0, "0"), (999, "999"), (1_284, "1.284"), (1_000_000, "1.000.000"), (-1_284, "\u{2212}1.284")] as [(Int, String)])
    func grouped(value: Int, expected: String) {
        #expect(VietnameseNumber.grouped(value) == expected)
    }

    @Test("Int.min does not trap")
    func extremes() {
        #expect(VietnameseNumber.grouped(.min) == "\u{2212}9.223.372.036.854.775.808")
    }
}

@Suite("Cleanup session")
struct CleanupSessionTests {
    @Test("Favourites and repeated ids never reach the deck")
    func candidatesOnly() {
        let session = CleanupSession(items: [photo("a"), photo("b", favorite: true), photo("a"), photo("c")])
        #expect(session.items.map(\.id) == ["a", "c"])
    }

    @Test("A photo that is a favourite in any record stays out, whatever the order")
    func favoriteInAnyRecord() {
        #expect(CleanupSession(items: [photo("a", favorite: true), photo("a")]).items.isEmpty)
        #expect(CleanupSession(items: [photo("a"), photo("a", favorite: true)]).items.isEmpty)
        #expect(CleanupMath.summary(of: [photo("a"), photo("a", favorite: true)]).isEmpty)
    }

    @Test("Deleted photos leave the session: no second request, counts follow")
    func removeDeleted() {
        var session = CleanupSession(items: [
            photo("a", bytes: 2_000_000), photo("b", bytes: 3_000_000), photo("c", bytes: 5_000_000),
        ])
        session.decide(.delete)
        session.decide(.delete)
        session.decide(.delete)
        session.toggleMark("c")
        session.remove(["a", "c"])
        #expect(session.items.map(\.id) == ["b"])
        #expect(session.toDelete.map(\.id) == ["b"])
        #expect(session.swipedToDelete.map(\.id) == ["b"])
        #expect(session.bytesToFree == 3_000_000)
        #expect(session.decidedCount == 1)
        #expect(session.isFinished)
        #expect(session.removedCount == 2)
        #expect(session.seenCount == 3 && session.totalCount == 3, "progress does not go backwards")
        session.remove(["a", "zzz"])
        #expect(session.removedCount == 2, "only photos still in the session count")
        let undone = session.undo()
        #expect(undone?.id == "b", "undo skips removed photos")
        let nothing = session.undo()
        #expect(nothing == nil)
        let marked = session.toggleMark("c")
        #expect(!marked, "a removed photo can't be marked again")
        // Nothing about a removed photo is kept, a rescue included.
        var rescuedFirst = CleanupSession(items: [photo("a"), photo("b")])
        rescuedFirst.decide(.delete)
        rescuedFirst.toggleMark("a")
        rescuedFirst.remove(["a"])
        var plain = CleanupSession(items: [photo("a"), photo("b")])
        plain.decide(.delete)
        plain.remove(["a"])
        #expect(rescuedFirst == plain)
    }

    @Test("Deleting mid-deck keeps the progress: 12/48 stays 12/48")
    func progressAfterDeleting() {
        var session = CleanupSession(items: (0..<48).map { photo("p\($0)") })
        for index in 0..<12 {
            session.decide(index % 3 == 1 ? .keep : .delete)
        }
        session.remove(Set(session.toDelete.map(\.id)))
        #expect(session.removedCount == 8)
        #expect(session.seenCount == 12)
        #expect(session.totalCount == 48)
        #expect(session.remainingCount == 36)
    }

    @Test("A decision for a card that is no longer on top is ignored")
    func decideExpecting() {
        var session = CleanupSession(items: [photo("a"), photo("b")])
        let stale = session.decide(.delete, expecting: "b")
        #expect(stale == nil)
        #expect(session.current?.id == "a")
        let fresh = session.decide(.delete, expecting: "a")
        #expect(fresh?.id == "a")
        #expect(session.current?.id == "b")
    }

    @Test("Swipes go through the deck in order, and stop at the end")
    func decideInOrder() {
        var session = CleanupSession(items: [photo("a"), photo("b")])
        #expect(session.current?.id == "a")
        let first = session.decide(.delete)
        let second = session.decide(.keep)
        let third = session.decide(.delete)
        #expect(first?.id == "a")
        #expect(second?.id == "b")
        #expect(third == nil, "an empty deck ignores a late swipe")
        #expect(session.isFinished)
        #expect(session.decidedCount == 2)
        #expect(session.decision(for: "a") == .delete)
        #expect(session.decision(for: "b") == .keep)
    }

    @Test("Undo puts the last card back on top and says which side it left from")
    func undo() {
        var session = CleanupSession(items: [photo("a"), photo("b"), photo("c")])
        session.decide(.keep)
        session.decide(.delete)
        #expect(session.lastDecision == .delete)
        let undone = session.undo()
        #expect(undone?.id == "b")
        #expect(session.current?.id == "b")
        #expect(session.remainingCount == 2)
        #expect(session.lastDecision == .keep)
        session.undo()
        #expect(session.current?.id == "a")
        let nothing = session.undo()
        #expect(nothing == nil)
        #expect(session.lastDecision == nil)
    }

    @Test("Review: a rescued photo stays in the grid and can be marked again")
    func review() {
        var session = CleanupSession(items: [
            photo("a", bytes: 2_000_000), photo("b", bytes: 3_000_000), photo("c", bytes: 5_000_000),
        ])
        session.decide(.delete)
        session.decide(.keep)
        session.decide(.delete)
        #expect(session.toDelete.map(\.id) == ["a", "c"])
        #expect(session.bytesToFree == 7_000_000)

        let rescued = session.toggleMark("a")
        #expect(rescued)
        #expect(session.swipedToDelete.map(\.id) == ["a", "c"], "the grid keeps its shape")
        #expect(session.toDelete.map(\.id) == ["c"])
        #expect(!session.isMarkedForDeletion("a"))
        #expect(session.bytesToFree == 5_000_000)

        session.toggleMark("a")
        #expect(session.toDelete.map(\.id) == ["a", "c"])

        let kept = session.toggleMark("b")
        let unknown = session.toggleMark("zzz")
        #expect(!kept, "a photo swiped to keep is not in the review grid")
        #expect(!unknown)
        #expect(session.toDelete.map(\.id) == ["a", "c"])
    }

    @Test("Undoing a swipe forgets its rescue")
    func undoForgetsRescue() {
        var session = CleanupSession(items: [photo("a"), photo("b")])
        session.decide(.delete)
        session.toggleMark("a")
        session.undo()
        session.decide(.delete)
        #expect(session.isMarkedForDeletion("a"), "swiped to delete again: marked, not still rescued")
    }

    @Test("Sizes add up without wrapping, and negative sizes count as zero")
    func sizes() {
        #expect(photo("a", bytes: -10).bytes == 0)
        let huge = [photo("a", bytes: .max), photo("b", bytes: .max)]
        #expect(CleanupMath.bytes(of: huge) == .max)
    }
}

@Suite("Cleanup summary")
struct CleanupSummaryTests {
    @Test("Per category, in a fixed order, without empty ones or favourites")
    func summary() {
        let summary = CleanupMath.summary(of: [
            photo("q", .qrCodes, bytes: 300_000),
            photo("s1", .screenshots, bytes: 1_000_000),
            photo("s2", .screenshots, bytes: 2_000_000),
            photo("fav", .screenshots, bytes: 9_000_000, favorite: true),
        ])
        #expect(summary == [
            CategorySummary(category: .screenshots, count: 2, bytes: 3_000_000),
            CategorySummary(category: .qrCodes, count: 1, bytes: 300_000),
        ])
    }
}

@Suite("Free allowance")
struct FreeAllowanceTests {
    @Test("100 free deletions, used up by confirmed deletions only")
    func allowance() {
        var free = FreeAllowance()
        #expect(free.remaining == 100)
        #expect(free.covered(of: 40) == 40)
        free.use(63)
        #expect(free.remaining == 37)
        #expect(free.covered(of: 40) == 37)
        free.use(50)
        #expect(free.remaining == 0)
        #expect(free.covered(of: 5) == 0)
    }

    @Test("Nonsense counts are clamped, also when decoding")
    func clamps() throws {
        var free = FreeAllowance(limit: -3, used: -1)
        #expect(free.limit == 0 && free.used == 0)
        #expect(free.remaining == 0)
        #expect(free.covered(of: -4) == 0)
        #expect(FreeAllowance(limit: .min, used: 1).remaining == 0, "no trap")
        // A negative count gives nothing back.
        free = FreeAllowance(used: 10)
        free.use(-5)
        free.use(.min)
        #expect(free.used == 10 && free.remaining == 90)
        free = FreeAllowance(used: .max)
        free.use(.max)
        #expect(free.remaining == 0)
        let decoded = try JSONDecoder().decode(FreeAllowance.self, from: Data(#"{"limit":100,"used":-20}"#.utf8))
        #expect(decoded.remaining == 100)
        for json in [#"{"limit":100,"used":1e20}"#, #"{"limit":100,"used":99999999999999999999}"#] {
            let huge = try JSONDecoder().decode(FreeAllowance.self, from: Data(json.utf8))
            #expect(huge.remaining == 0, "a corrupt count uses the allowance up, not resets it: \(json)")
        }
        // Too negative for Int: clamped like -20, without trapping.
        let veryNegative = try JSONDecoder().decode(FreeAllowance.self, from: Data(#"{"limit":100,"used":-1e20}"#.utf8))
        #expect(veryNegative.remaining == 100)
        let negativeLimit = try JSONDecoder().decode(FreeAllowance.self, from: Data(#"{"limit":-1e19,"used":0}"#.utf8))
        #expect(negativeLimit.remaining == 0)
        // Not a number (a lenient decoder lets one through): nothing free left.
        let lenient = JSONDecoder()
        lenient.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        for json in [#"{"limit":100,"used":"nan"}"#, #"{"limit":"nan","used":0}"#, #"{"limit":100,"used":"inf"}"#] {
            let corrupt = try lenient.decode(FreeAllowance.self, from: Data(json.utf8))
            #expect(corrupt.remaining == 0, "\(json)")
        }
        let minusInfinity = try lenient.decode(FreeAllowance.self, from: Data(#"{"limit":100,"used":"-inf"}"#.utf8))
        #expect(minusInfinity.remaining == 100)
        let fractional = try JSONDecoder().decode(FreeAllowance.self, from: Data(#"{"limit":100,"used":12.7}"#.utf8))
        #expect(fractional.remaining == 88)
        let roundTrip = try JSONDecoder().decode(FreeAllowance.self, from: JSONEncoder().encode(FreeAllowance(used: 12)))
        #expect(roundTrip == FreeAllowance(used: 12))
    }
}

@Suite("Phone storage")
struct StorageStatusTests {
    @Test("Used share now and after cleaning")
    func fractions() {
        let storage = StorageStatus(capacity: 100_000, available: 10_000)
        #expect(storage.used == 90_000)
        #expect(storage.usedFraction == 0.9)
        #expect(storage.usedFraction(afterFreeing: 30_000) == 0.6)
        #expect(storage.usedFraction(afterFreeing: 500_000) == 0, "can't free more than is used")
        #expect(storage.usedFraction(afterFreeing: -1) == 0.9)
    }

    @Test("Impossible readings are clamped")
    func clamps() {
        #expect(StorageStatus(capacity: 100, available: 400).used == 0)
        #expect(StorageStatus(capacity: 100, available: -5).used == 100)
        #expect(StorageStatus(capacity: 0, available: 0).usedFraction == 0)
        #expect(StorageStatus(capacity: -1, available: 0).usedFraction(afterFreeing: 1) == 0)
    }
}

@Suite("Sample library")
struct CleanupSamplesTests {
    @Test("Deterministic, unique ids, oldest first in each category")
    func deterministic() {
        let items = CleanupSamples.items()
        #expect(items == CleanupSamples.items())
        #expect(Set(items.map(\.id)).count == items.count)
        for category in CleanupCategory.allCases {
            let dates = items.filter { $0.category == category }.map(\.date)
            #expect(dates == dates.sorted(), "\(category) is oldest first")
        }
        #expect(items.allSatisfy { $0.date <= LedgerSamples.referenceNow })
    }

    @Test("About 1.900 photos and 3,3 GB, mostly screenshots")
    func shape() {
        let summary = CleanupMath.summary(of: CleanupSamples.items())
        #expect(summary.map(\.category) == CleanupCategory.allCases)
        #expect(summary.map(\.count) == [1_284, 342, 87, 156, 41])
        let total = summary.reduce(0) { $0 + $1.bytes }
        #expect(ByteSize.string(total) == "3,3\(nbsp)GB")
        #expect(summary.max { $0.bytes < $1.bytes }?.category == .screenshots)
    }

    @Test("A deck is the oldest photos of one category")
    func deck() {
        let deck = CleanupSamples.deck(.screenshots, count: 5)
        #expect(deck.map(\.id) == (1...5).map { "screenshots-\($0)" })
    }
}
