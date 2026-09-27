import Foundation
import IdeaLabCore
import Testing

private func featurePrint(_ values: Float...) throws -> FeaturePrint {
    try #require(FeaturePrint(values))
}

@Suite("Feature prints")
struct FeaturePrintTests {
    @Test("A print has numbers, all finite")
    func valid() {
        #expect(FeaturePrint([]) == nil)
        #expect(FeaturePrint([0.5, .nan]) == nil)
        #expect(FeaturePrint([.infinity, 0]) == nil)
        #expect(FeaturePrint([-.infinity]) == nil)
        #expect(FeaturePrint([0.6, 0.8])?.values == [0.6, 0.8])
    }

    @Test("The Euclidean distance, as Vision's computeDistance")
    func distance() throws {
        let origin = try featurePrint(0, 0)
        let point = try featurePrint(3, 4)
        #expect(origin.distance(to: point) == 5)
        #expect(point.distance(to: origin) == 5)
        #expect(point.distance(to: point) == 0)
        // Revision 2 prints have length 1: at right angles they are √2 apart,
        // and opposite ones 2, the most there is.
        let x = try featurePrint(1, 0)
        #expect(try #require(x.distance(to: featurePrint(0, 1))) == Float(2).squareRoot())
        #expect(x.distance(to: try featurePrint(-1, 0)) == 2)
    }

    @Test("Prints of different lengths come from different revisions: no distance")
    func revisions() throws {
        #expect(try featurePrint(1, 0).distance(to: featurePrint(1, 0, 0)) == nil)
        #expect(try !FeaturePrint.alike(featurePrint(1, 0), featurePrint(1, 0, 0), within: 10))
    }

    @Test("Shots of one moment: at most the threshold apart, 0.35 unless said")
    func alike() throws {
        #expect(FeaturePrint.sameMoment == 0.35)
        let a = try featurePrint(1, 0)
        #expect(try FeaturePrint.alike(a, featurePrint(0.7, 0)))
        #expect(try !FeaturePrint.alike(a, featurePrint(0.6, 0)))
        #expect(try FeaturePrint.alike(a, featurePrint(0.6, 0), within: 0.5))
        #expect(try FeaturePrint.alike(a, featurePrint(0.5, 0), within: 0.5))
        #expect(try !FeaturePrint.alike(a, featurePrint(0.5, 0), within: 0.49))
        #expect(FeaturePrint.alike(a, a, within: 0))
        #expect(!FeaturePrint.alike(a, a, within: .nan))
    }

    @Test("A photo with no print looks like no other, not even another without one")
    func missing() throws {
        let a = try featurePrint(1, 0)
        #expect(!FeaturePrint.alike(a, nil))
        #expect(!FeaturePrint.alike(nil, a))
        #expect(!FeaturePrint.alike(nil, nil, within: 100))
    }

    @Test("Large numbers do not overflow the distance")
    func large() throws {
        let big = try featurePrint(3e30, 0)
        let bigger = try featurePrint(0, 4e30)
        let distance = try #require(big.distance(to: bigger))
        #expect(abs(distance - 5e30) / 5e30 < 1e-6)
    }
}
