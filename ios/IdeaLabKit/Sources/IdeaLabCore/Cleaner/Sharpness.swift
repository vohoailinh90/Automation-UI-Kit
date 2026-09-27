import Foundation

/// How sharp a photo is, for `SimilarPhoto.sharpness`: the variance of the
/// Laplacian of a small grayscale copy, the classic measure of focus
/// (Pech-Pacheco et al., 2000; OpenCV's `Laplacian` with its 3 × 3 kernel).
///
/// The Laplacian is large where brightness changes abruptly, at edges and
/// fine detail. A shaken or out-of-focus shot has none, so its Laplacian stays
/// small everywhere and varies little. The number depends on the scene as
/// much as on the focus, though: a sharp photo of the sky scores lower than a
/// blurred one of grass. So it only ranks shots of one scene, measured at
/// one size, as the photos of a `SimilarGroup` are.
public enum Sharpness {
    /// The variance of the Laplacian of `luma`, a `width` × `height` grayscale
    /// image, one byte a pixel, row after row with no padding.
    ///
    /// Each pixel with all four neighbours gets its Laplacian, the sum of the
    /// neighbours less four times itself; the edge pixels, which lack one,
    /// are left out. The result is 0 for a flat image. It is NaN when there is
    /// nothing to measure: fewer than 3 rows or columns, or not exactly
    /// `width` × `height` bytes. `SimilarPhoto` takes NaN as the least sharp.
    public static func laplacianVariance(of luma: [UInt8], width: Int, height: Int) -> Double {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width >= 3, height >= 3, !overflow, luma.count == count else { return .nan }
        // Exact sums: a Laplacian is within ±1020, so its square is at most
        // 1_040_400, and it would take more pixels than memory holds for the
        // sum of squares to leave Int64.
        var sum: Int64 = 0
        var squares: Int64 = 0
        luma.withUnsafeBufferPointer { pixels in
            for y in 1 ..< height - 1 {
                for index in y * width + 1 ..< (y + 1) * width - 1 {
                    let laplacian = Int64(pixels[index - 1]) + Int64(pixels[index + 1])
                        + Int64(pixels[index - width]) + Int64(pixels[index + width])
                        - 4 * Int64(pixels[index])
                    sum += laplacian
                    squares += laplacian * laplacian
                }
            }
        }
        let measured = Double((width - 2) * (height - 2))
        let mean = Double(sum) / measured
        // Rounding can leave a flat image a hair below zero.
        return max(Double(squares) / measured - mean * mean, 0)
    }
}
