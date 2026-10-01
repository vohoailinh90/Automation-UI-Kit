import Foundation

/// A deterministic photo library to clean, for previews, the demo app and
/// screenshots: about 1.900 candidates and 14,8 GB, most of the photos
/// screenshots and most of the room videos, like a phone that has been used
/// for chat and banking, and for filming the family, for two years.
public enum CleanupSamples {
    /// A 128 GB iPhone with 9,6 GB left: the moment people go looking for a
    /// cleaner.
    public static let storage = StorageStatus(capacity: 128_000_000_000, available: 9_600_000_000)

    /// Per category: how many, and the range of sizes in KB.
    static let shape: [(category: CleanupCategory, count: Int, kilobytes: ClosedRange<UInt64>)] = [
        (.screenshots, 1_284, 400...2_200),
        (.similar, 342, 1_800...4_500),
        (.blurry, 87, 1_500...4_000),
        (.documents, 156, 800...3_000),
        (.qrCodes, 41, 200...900),
        (.largeVideos, 24, 20_000...900_000),
    ]

    /// How many bytes a second of video takes, for the samples' lengths: HD
    /// at 30 frames, 4K at 30, 4K at 60, as an iPhone records in HEVC.
    public static let videoBytesPerSecond: [UInt64] = [1_000_000, 2_800_000, 5_600_000]

    /// Every candidate, oldest first within each category — the order a deck
    /// shows them, since the oldest screenshots are the safest to let go —
    /// and the videos largest first, with a length that fits their size.
    /// Ids are "<category>-<n>", `n` counting from 1 in that order.
    public static func items(endingAt now: Date = LedgerSamples.referenceNow) -> [CleanupItem] {
        var generator = SplitMix64(seed: 2026_09_25_0941)
        var items: [CleanupItem] = []
        for (category, count, kilobytes) in shape {
            // Spread over the last two years, drawn first, then sorted.
            let ages = (0..<count).map { _ in TimeInterval(generator.next() % (730 * 86_400)) }
            var drawn: [(size: UInt64, age: TimeInterval, duration: TimeInterval?)] = []
            for age in ages.sorted(by: >) {
                let span = kilobytes.upperBound - kilobytes.lowerBound + 1
                let size = (kilobytes.lowerBound + generator.next() % span) * 1_000
                var duration: TimeInterval?
                if category == .largeVideos {
                    let rate = videoBytesPerSecond[Int(generator.next() % UInt64(videoBytesPerSecond.count))]
                    duration = (Double(size) / Double(rate)).rounded()
                }
                drawn.append((size, age, duration))
            }
            if category == .largeVideos {
                drawn.sort { a, b in a.size > b.size }
            }
            for (index, item) in drawn.enumerated() {
                items.append(CleanupItem(
                    id: "\(category.rawValue)-\(index + 1)",
                    category: category,
                    bytes: Int64(item.size),
                    date: now.addingTimeInterval(-item.age),
                    duration: item.duration
                ))
            }
        }
        return items
    }

    /// The first `count` items of one category: a deck short enough to
    /// swipe through in a preview.
    public static func deck(_ category: CleanupCategory, count: Int = 12, endingAt now: Date = LedgerSamples.referenceNow) -> [CleanupItem] {
        Array(items(endingAt: now).lazy.filter { $0.category == category }.prefix(count))
    }

    /// Moments shot several times, for the similar-photos review: six bursts
    /// over the last month, newest first, of two to six shots a few seconds
    /// apart. In each burst one shot is sharp and the rest are a little
    /// shaken. The third burst holds a favourite that is not its sharpest.
    /// Ids are "similar-<moment>-<shot>", both counting from 1.
    public static func similarPhotos(endingAt now: Date = LedgerSamples.referenceNow) -> [SimilarPhoto] {
        let moments: [(daysAgo: Int, minute: Int, shots: Int, sharp: Int, favorite: Int?)] = [
            (2, 19 * 60 + 12, 5, 3, nil),
            (4, 17 * 60 + 48, 6, 2, nil),
            (7, 9 * 60 + 5, 3, 1, 3),
            (12, 15 * 60 + 30, 4, 4, nil),
            (20, 8 * 60 + 20, 2, 1, nil),
            (33, 20 * 60 + 40, 3, 2, nil),
        ]
        let calendar = LedgerSamples.calendar
        let today = calendar.startOfDay(for: now)
        var generator = SplitMix64(seed: 2026_09_23_1912)
        var photos: [SimilarPhoto] = []
        for (index, moment) in moments.enumerated() {
            let day = calendar.date(byAdding: .day, value: -moment.daysAgo, to: today) ?? today
            var date = day.addingTimeInterval(TimeInterval(moment.minute * 60))
            for shot in 1...moment.shots {
                let bytes = Int64(1_800 + generator.next() % 2_700) * 1_000
                let shaken = 0.25 + Double(generator.next() % 450) / 1_000
                photos.append(SimilarPhoto(
                    CleanupItem(
                        id: "similar-\(index + 1)-\(shot)",
                        category: .similar,
                        bytes: bytes,
                        date: date,
                        isFavorite: shot == moment.favorite
                    ),
                    sharpness: shot == moment.sharp ? 0.92 : shaken
                ))
                date.addTimeInterval(TimeInterval(3 + generator.next() % 6))
            }
        }
        return photos
    }

    /// Whether two sample photos look alike: shots of the same moment.
    public static func looksAlike(_ a: SimilarPhoto, _ b: SimilarPhoto) -> Bool {
        moment(of: a.id) != nil && moment(of: a.id) == moment(of: b.id)
    }

    /// The similar-photos review the demo opens: `similarPhotos`, grouped.
    public static func similarReview(endingAt now: Date = LedgerSamples.referenceNow) -> SimilarReview {
        SimilarReview(photos: similarPhotos(endingAt: now), alike: looksAlike)
    }

    /// "similar-3-2" → "3".
    private static func moment(of id: String) -> Substring? {
        let parts = id.split(separator: "-")
        return parts.count == 3 && parts[0] == "similar" ? parts[1] : nil
    }
}
