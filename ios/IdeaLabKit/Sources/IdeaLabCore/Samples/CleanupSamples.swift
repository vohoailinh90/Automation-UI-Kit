import Foundation

/// A deterministic photo library to clean, for previews, the demo app and
/// screenshots: about 1.900 candidates and 3,3 GB, most of it screenshots,
/// like a phone that has been used for chat and banking for two years.
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
    ]

    /// Every candidate, oldest first within each category — the order a deck
    /// shows them, since the oldest screenshots are the safest to let go.
    /// Ids are "<category>-<n>", `n` counting from 1 in that order.
    public static func items(endingAt now: Date = LedgerSamples.referenceNow) -> [CleanupItem] {
        var generator = SplitMix64(seed: 2026_09_25_0941)
        var items: [CleanupItem] = []
        for (category, count, kilobytes) in shape {
            // Spread over the last two years, drawn first, then sorted.
            let ages = (0..<count).map { _ in TimeInterval(generator.next() % (730 * 86_400)) }
            for (index, age) in ages.sorted(by: >).enumerated() {
                let span = kilobytes.upperBound - kilobytes.lowerBound + 1
                let size = (kilobytes.lowerBound + generator.next() % span) * 1_000
                items.append(CleanupItem(
                    id: "\(category.rawValue)-\(index + 1)",
                    category: category,
                    bytes: Int64(size),
                    date: now.addingTimeInterval(-age)
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
}
