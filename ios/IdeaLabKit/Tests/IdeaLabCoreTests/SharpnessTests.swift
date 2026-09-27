import Foundation
import IdeaLabCore
import Testing

/// A grayscale image from rows of brightness.
private struct Gray {
    var pixels: [UInt8]
    var width: Int
    var height: Int { pixels.count / width }

    init(_ rows: [[UInt8]]) {
        pixels = rows.flatMap { $0 }
        width = rows.first?.count ?? 0
    }

    init(width: Int, height: Int, _ brightness: (Int, Int) -> UInt8) {
        self.width = width
        pixels = (0 ..< height).flatMap { y in (0 ..< width).map { x in brightness(x, y) } }
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    var sharpness: Double {
        Sharpness.laplacianVariance(of: pixels, width: width, height: height)
    }

    /// Each pixel the mean of the 3 × 3 square around it, the edges kept as
    /// they are: a photo slightly out of focus.
    var blurred: Gray {
        var result = self
        for y in 1 ..< height - 1 {
            for x in 1 ..< width - 1 {
                var sum = 0
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 { sum += Int(self[x + dx, y + dy]) }
                }
                result[x, y] = UInt8(sum / 9)
            }
        }
        return result
    }

    /// Rows become columns: the photo turned on its side.
    var transposed: Gray {
        Gray(width: height, height: width) { x, y in self[y, x] }
    }
}

/// Fine detail: a pseudo-random texture, the same every run.
private let texture = Gray(width: 40, height: 30) { x, y in
    UInt8(truncatingIfNeeded: (x &* 7_919 &+ y &* 104_729 &+ x &* y &* 31) % 200 + 20)
}

@Suite("Sharpness: variance of the Laplacian")
struct SharpnessTests {
    @Test("A flat image has none")
    func flat() {
        #expect(Gray(width: 5, height: 4) { _, _ in 128 }.sharpness == 0)
        #expect(Gray(width: 3, height: 3) { _, _ in 0 }.sharpness == 0)
    }

    @Test("The variance of each inner pixel's neighbours less four times itself")
    func value() {
        // Inner pixels: (1, 1), whose Laplacian is -4 × 255 = -1020, and
        // (2, 1), whose left neighbour is 255. Their mean is -382.5, and each
        // is 637.5 from it.
        let image = Gray([
            [0, 0, 0, 0],
            [0, 255, 0, 0],
            [0, 0, 0, 0],
        ])
        #expect(image.sharpness == 637.5 * 637.5)
    }

    @Test("Edge pixels are only neighbours; the corners take no part")
    func edges() {
        var image = texture
        let before = image.sharpness
        image[0, 0] = 0
        image[image.width - 1, image.height - 1] = 255
        #expect(image.sharpness == before)
        image[1, 0] &+= 50
        #expect(image.sharpness != before)
    }

    @Test("A blurred copy is less sharp, and blurring it again lowers it further")
    func blur() {
        let sharp = texture.sharpness
        let soft = texture.blurred.sharpness
        let softer = texture.blurred.blurred.sharpness
        #expect(sharp > soft)
        #expect(soft > softer)
        #expect(softer > 0)
    }

    @Test("Brightness does not count, only its changes; nor which way the photo is turned")
    func invariance() {
        let brighter = Gray(width: texture.width, height: texture.height) { x, y in texture[x, y] + 30 }
        #expect(brighter.sharpness == texture.sharpness)
        #expect(texture.transposed.sharpness == texture.sharpness)
    }

    @Test("Nothing to measure: fewer than three rows or columns, or not width × height bytes")
    func unmeasurable() {
        #expect(Sharpness.laplacianVariance(of: [], width: 0, height: 0).isNaN)
        #expect(Sharpness.laplacianVariance(of: [UInt8](repeating: 9, count: 6), width: 2, height: 3).isNaN)
        #expect(Sharpness.laplacianVariance(of: [UInt8](repeating: 9, count: 6), width: 3, height: 2).isNaN)
        #expect(Sharpness.laplacianVariance(of: [UInt8](repeating: 9, count: 8), width: 3, height: 3).isNaN)
        #expect(Sharpness.laplacianVariance(of: [UInt8](repeating: 9, count: 10), width: 3, height: 3).isNaN)
        #expect(Sharpness.laplacianVariance(of: [UInt8](repeating: 9, count: 9), width: -3, height: -3).isNaN)
        // A size whose byte count does not fit in an Int is refused, not a trap.
        #expect(Sharpness.laplacianVariance(of: [1, 2, 3], width: .max, height: 3).isNaN)
    }

    @Test("Unmeasured is the least sharp in a group")
    func nanIsLeastSharp() throws {
        let item = { (id: String) in CleanupItem(id: id, category: .similar, bytes: 1, date: LedgerSamples.referenceNow) }
        let unmeasured = SimilarPhoto(item("a"), sharpness: Sharpness.laplacianVariance(of: [], width: 0, height: 0))
        let measured = SimilarPhoto(item("b"), sharpness: texture.blurred.blurred.sharpness)
        #expect(try #require(SimilarGroup([unmeasured, measured])).sharpest.id == "b")
    }
}
