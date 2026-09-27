#if os(iOS)
import CoreML
import IdeaLabCore
import ImageIO
import Photos
import UIKit
import Vision

/// Measures photos for `LibraryFindings`: how sharp each one is
/// (`Sharpness`), and its feature print (Vision), both from one copy
/// `side` pixels on its long side. For the library, `PhotoLibraryScan` uses
/// it on the copy the phone has: a photo that has none there, kept only in
/// iCloud, is not downloaded, and not measured.
public enum PhotoMeasurer {
    /// The long side of the copy measured, in pixels: large enough that a
    /// shake of a few pixels in a 12-megapixel shot still shows, small enough
    /// to read quickly. Every photo is drawn at this size, so sharpness
    /// compares across photos of different resolutions.
    public static let side = 1024

    /// The revision of the feature print, whatever the SDK's default: prints
    /// of different revisions cannot be compared. Revision 2 is iOS 17's.
    private static let printRevision = VNGenerateImageFeaturePrintRequestRevision2

    /// How photos are measured here, kept with the measurements on the
    /// device (`MeasurementStore`): change it along with the measuring, and
    /// the photos measured the old way are measured again.
    public static let method = "sharpness: Laplacian variance at \(side) px; print: revision \(printRevision)"

    private static let queue = DispatchQueue(label: "IdeaLabPhotos.measure", qos: .utility, attributes: .concurrent)

    /// Measures the photos with these ids, one after another on a background
    /// queue: PhotoKit and Vision block while they work. A photo not in the
    /// library, or with no copy of `side` pixels on the phone, is left out.
    static func measure(_ ids: [String]) async -> [String: PhotoMeasurement] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: measureNow(ids))
            }
        }
    }

    private static func measureNow(_ ids: [String]) -> [String: PhotoMeasurement] {
        var measurements: [String: PhotoMeasurement] = [:]
        PhotoLibrary.assets(ids).enumerateObjects { asset, _, _ in
            // One photo's images at a time, not the whole batch's.
            autoreleasepool {
                measurements[asset.localIdentifier] = measure(asset)
            }
        }
        return measurements
    }

    private static func measure(_ asset: PHAsset) -> PhotoMeasurement? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
        ) { result, _ in
            image = result
        }
        // A copy much smaller than asked, a thumbnail, is not the photo:
        // measured, it would look soft, and the group would drop it.
        let expected = min(side, max(asset.pixelWidth, asset.pixelHeight))
        guard let image, let cgImage = image.cgImage,
              max(cgImage.width, cgImage.height) * 10 >= expected * 9
        else { return nil }
        return measure(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    /// Measures an image as a photo of the library is measured: its
    /// sharpness, drawn `side` pixels on its long side, and its feature
    /// print, `nil` when Vision cannot make one. For images from elsewhere,
    /// the app's own or a test's. Vision works while it runs: call it off
    /// the main actor.
    public static func measure(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) -> PhotoMeasurement {
        PhotoMeasurement(sharpness: sharpness(of: image), print: featurePrint(of: image, orientation: orientation))
    }

    /// `Sharpness.laplacianVariance` of the image drawn in gray, `side`
    /// pixels on its long side.
    private static func sharpness(of image: CGImage) -> Double {
        let scale = Double(side) / Double(max(image.width, image.height, 1))
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        var luma = [UInt8](repeating: 0, count: width * height)
        let drawn = luma.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Sharpness.laplacianVariance(of: luma, width: width, height: height) : .nan
    }

    /// The image's feature print, of `printRevision`.
    private static func featurePrint(of image: CGImage, orientation: CGImagePropertyOrientation) -> FeaturePrint? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = printRevision
        #if targetEnvironment(simulator)
        useCPU(for: request)
        #endif
        do {
            try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        } catch {
            return nil
        }
        return request.results?.first.flatMap { FeaturePrint(values(of: $0)) }
    }

    /// The print's numbers, whether Vision gives them as floats or doubles.
    private static func values(of observation: VNFeaturePrintObservation) -> [Float] {
        let count = observation.elementCount
        return observation.data.withUnsafeBytes { bytes -> [Float] in
            switch observation.elementType {
            case .float where bytes.count >= count * MemoryLayout<Float>.size:
                (0 ..< count).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
            case .double where bytes.count >= count * MemoryLayout<Double>.size:
                (0 ..< count).map { Float(bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Double>.size, as: Double.self)) }
            default:
                []
            }
        }
    }

    #if targetEnvironment(simulator)
    /// Runs the request on the CPU. The simulator has no Neural Engine, and
    /// Vision's models can fail to load on its GPU ("Could not create
    /// inference context"); the CPU runs them anywhere.
    private static func useCPU(for request: VNRequest) {
        guard let devices = try? request.supportedComputeStageDevices[.main],
              let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } })
        else { return }
        request.setComputeDevice(cpu, for: .main)
    }
    #endif
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
