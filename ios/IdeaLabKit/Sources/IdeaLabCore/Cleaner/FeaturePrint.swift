import Foundation

/// What Vision's `VNGenerateImageFeaturePrintRequest` makes of a photo, as
/// plain numbers, so the kit can compare prints anywhere and test the
/// comparison. Since revision 2 (iOS 17) a print is 768 numbers and its
/// length is 1, so two prints are between 0 (the same picture) and 2 apart.
public struct FeaturePrint: Hashable, Sendable {
    /// At least one, each a finite number.
    public let values: [Float]

    /// `nil` for no numbers, or one that is not finite: nothing could be
    /// compared with such a print, and NaN is not even equal to itself.
    public init?(_ values: [Float]) {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        self.values = values
    }

    /// The Euclidean distance, as `VNFeaturePrintObservation.computeDistance`
    /// measures it. `nil` between prints of different lengths, which come
    /// from different revisions of the request and cannot be compared.
    public func distance(to other: FeaturePrint) -> Float? {
        guard values.count == other.values.count else { return nil }
        var sum: Double = 0
        for (a, b) in zip(values, other.values) {
            let difference = Double(a) - Double(b)
            sum += difference * difference
        }
        return Float(sum.squareRoot())
    }

    /// How far apart two shots of one moment can be: 0.35. ShutterSlim, a
    /// photo cleaner, arrived at it by labelling a few hundred pairs of
    /// photos; MWM found the line between alike and not somewhere from 0.4
    /// to 0.6. The stricter one, because a photo taken wrongly for another
    /// shot of the moment is offered for deletion.
    public static let sameMoment: Float = 0.35

    /// Whether two photos look alike enough to be shots of one moment: their
    /// prints are at most `threshold` apart. A photo with no print, or with
    /// one that cannot be compared, looks like no other photo.
    public static func alike(_ a: FeaturePrint?, _ b: FeaturePrint?, within threshold: Float = sameMoment) -> Bool {
        guard let a, let b, let distance = a.distance(to: b) else { return false }
        return distance <= threshold
    }
}
