#if os(iOS)
import CoreML
import IdeaLabCore
import ImageIO
import Photos
import UIKit
import Vision

/// Measures photos for `LibraryFindings`, all from one copy `side` pixels on
/// its long side: how sharp each one is (`Sharpness`), its feature print,
/// and what it shows, a QR code or a document (Vision). For the library,
/// `PhotoLibraryScan` uses it on the copy the phone has: a photo that has
/// none there, kept only in iCloud, is not downloaded, and not measured.
public enum PhotoMeasurer {
    /// The long side of the copy measured, in pixels: large enough that a
    /// shake of a few pixels in a 12-megapixel shot still shows, small enough
    /// to read quickly. Every photo is drawn at this size, so sharpness
    /// compares across photos of different resolutions.
    public static let side = 1024

    /// The revisions of Vision's requests, whatever the SDK's default: prints
    /// of different revisions cannot be compared, and what the others find
    /// changes with them. These are iOS 17's.
    private static let printRevision = VNGenerateImageFeaturePrintRequestRevision2
    private static let barcodesRevision = VNDetectBarcodesRequestRevision4
    private static let labelsRevision = VNClassifyImageRequestRevision2

    /// The labels of `VNClassifyImageRequest` that make a photo a document:
    /// a receipt, a page, a note, a whiteboard, a ticket.
    static let documentLabels: Set<String> = ["document", "handwriting", "printed_page", "receipt", "sticky_note", "ticket", "whiteboard"]
    /// How sure of such a label Vision must be: as sure as it is when right
    /// 9 times in 10, as Apple's sample asks of a search that must not show
    /// what is not there. A photo taken wrongly for a document is offered
    /// for deletion.
    static let documentPrecision: Float = 0.9

    /// How photos are measured here, kept with the measurements on the
    /// device (`MeasurementStore`): change it along with the measuring, and
    /// the photos measured the old way are measured again.
    public static let method = [
        "sharpness: Laplacian variance at \(side) px",
        "print: revision \(printRevision)",
        "QR codes: revision \(barcodesRevision)",
        "documents: labels revision \(labelsRevision), \(documentLabels.sorted().joined(separator: " ")) at precision \(documentPrecision)",
    ].joined(separator: "; ")

    private static let queue = DispatchQueue(label: "IdeaLabPhotos.measure", qos: .utility, attributes: .concurrent)

    /// Measures the photos with these ids, one after another on a background
    /// queue: PhotoKit and Vision block while they work. Every one is looked
    /// at for what it shows; those in `prints` get their feature print too.
    /// A photo not in the library, or with no copy of `side` pixels on the
    /// phone, is left out.
    static func measure(_ ids: [String], prints: Set<String>) async -> [String: PhotoMeasurement] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: measureNow(ids, prints: prints))
            }
        }
    }

    private static func measureNow(_ ids: [String], prints: Set<String>) -> [String: PhotoMeasurement] {
        var measurements: [String: PhotoMeasurement] = [:]
        PhotoLibrary.assets(ids).enumerateObjects { asset, _, _ in
            // One photo's images at a time, not the whole batch's.
            autoreleasepool {
                let id = asset.localIdentifier
                measurements[id] = measure(asset, withPrint: prints.contains(id))
            }
        }
        return measurements
    }

    private static func measure(_ asset: PHAsset, withPrint: Bool) -> PhotoMeasurement? {
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
        return measure(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation), withPrint: withPrint)
    }

    /// Measures an image as a photo of the library is measured: its
    /// sharpness, drawn `side` pixels on its long side; what it shows; and,
    /// unless `withPrint` is false, its feature print, `nil` when Vision
    /// cannot make one. For images from elsewhere, the app's own or a
    /// test's. Vision works while it runs: call it off the main actor.
    public static func measure(_ image: CGImage, orientation: CGImagePropertyOrientation = .up, withPrint: Bool = true) -> PhotoMeasurement {
        PhotoMeasurement(
            sharpness: sharpness(of: image),
            print: withPrint ? featurePrint(of: image, orientation: orientation) : nil,
            content: content(of: image, orientation: orientation)
        )
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

    /// What Vision recognises in the image: a QR code, a document. A request
    /// that fails finds nothing, rather than have the photo looked at again
    /// on every scan.
    private static func content(of image: CGImage, orientation: CGImagePropertyOrientation) -> PhotoContent {
        let barcodes = VNDetectBarcodesRequest()
        // The revision first: setting it resets the symbologies.
        barcodes.revision = barcodesRevision
        barcodes.symbologies = [.qr]
        let labels = VNClassifyImageRequest()
        labels.revision = labelsRevision
        #if targetEnvironment(simulator)
        useCPU(for: barcodes)
        useCPU(for: labels)
        #endif
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        var content: PhotoContent = []
        if (try? handler.perform([barcodes])) != nil, barcodes.results?.isEmpty == false {
            content.insert(.qrCode)
        }
        if (try? handler.perform([labels])) != nil, labels.results?.contains(where: isDocument) == true {
            content.insert(.document)
        }
        return content
    }

    /// Whether a label says document, surely enough: at `documentPrecision`
    /// on the label's own precision-recall curve, or, for a label without
    /// one, with that much confidence.
    private static func isDocument(_ observation: VNClassificationObservation) -> Bool {
        guard documentLabels.contains(observation.identifier) else { return false }
        return observation.hasPrecisionRecallCurve
            ? observation.hasMinimumRecall(0.01, forPrecision: documentPrecision)
            : observation.confidence >= documentPrecision
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
