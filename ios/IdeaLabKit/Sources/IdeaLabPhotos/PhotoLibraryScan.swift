#if os(iOS)
import Foundation
import IdeaLabCore
import Observation
import Photos

/// Sorts the photo library for the cleaner, on the device: lists the photos,
/// measures the `LibraryFindings.candidates` not measured yet (sharpness and
/// feature print), groups the look-alikes, then sizes what the screens show.
///
/// Run it when the cleaner opens, and again after deleting or when the app
/// comes back: it remembers what it measured and sized, by photo and the
/// photo's last change, so a later run only measures new or edited photos.
/// It keeps that in memory only; a library of tens of thousands of photos
/// is measured again on the next launch.
@MainActor
@Observable
public final class PhotoLibraryScan {
    /// How far the run in progress is, `0...1`, for `CleanerHomeScreen`'s
    /// `scanProgress`; `nil` when none is.
    public private(set) var progress: Double?
    /// What the latest run found: the counts once the photos are measured,
    /// then the sizes too. `nil` until a run has measured the library.
    public private(set) var findings: LibraryFindings?

    /// The window and threshold of `LibraryFindings`.
    public let window: TimeInterval
    public let threshold: Float

    @ObservationIgnored private var measured: [String: Remembered<PhotoMeasurement>] = [:]
    @ObservationIgnored private var sizes: [String: Remembered<Int64>] = [:]

    /// What was learnt about a photo, and when the photo last changed then.
    private struct Remembered<Value: Sendable>: Sendable {
        let modified: Date?
        let value: Value
    }

    /// Photos handed to one background task at once, and tasks at once.
    private static let batchSize = 24
    private static let parallelBatches = 3

    public init(window: TimeInterval = 120, threshold: Float = FeaturePrint.sameMoment) {
        self.window = window
        self.threshold = threshold
    }

    /// Sorts the library again. Returns at once without access to the
    /// photos, or while another run is in progress: `progress` and
    /// `findings` say how that one goes. When the task running it is
    /// cancelled, it stops once the photos in hand are done, keeping what it
    /// measured and sized for the next run, and `findings` as far as it got.
    public func run() async {
        guard progress == nil, PhotoLibrary.access.canRead else { return }
        progress = 0
        defer { progress = nil }

        // Off the main actor: tens of thousands of photos take a moment.
        let window = window
        let (listed, candidates) = await Task.detached(priority: .userInitiated) {
            let listed = PhotoLibrary.listed()
            return (listed, LibraryFindings.candidates(in: listed.map(\.photo), within: window))
        }.value
        let modified = Dictionary(listed.map { ($0.photo.id, $0.modified) }) { first, _ in first }
        func isCurrent<Value: Sendable>(_ remembered: Remembered<Value>?, for id: String) -> Bool {
            guard let remembered, let now = modified[id] else { return false }
            return remembered.modified == now
        }
        func current<Value: Sendable>(_ remembered: [String: Remembered<Value>]) -> [String: Remembered<Value>] {
            remembered.filter { isCurrent($0.value, for: $0.key) }
        }
        let photos = listed.map(\.photo)

        // Measure: most of the work, most of the bar.
        let unmeasured = candidates.filter { !isCurrent(measured[$0], for: $0) }
        let measuredNow = await inBatches(unmeasured, progress: 0 ... 0.8) { ids in await PhotoMeasurer.measure(ids) }
        for (id, measurement) in measuredNow where measurement.print != nil {
            measured[id] = Remembered(modified: modified[id] ?? nil, value: measurement)
        }
        guard !Task.isCancelled else { return }
        // Forget the photos gone or changed since.
        measured = current(measured)
        sizes = current(sizes)
        findings = await sorted(photos)

        // Size what the screens show.
        let unsized = (findings?.sizedIDs ?? []).filter { sizes[$0] == nil }
        let sizedNow = await inBatches(unsized, progress: 0.8 ... 1) { ids in await PhotoLibrary.localBytes(of: ids) }
        for (id, bytes) in sizedNow {
            sizes[id] = Remembered(modified: modified[id] ?? nil, value: bytes)
        }
        guard !Task.isCancelled else { return }
        findings = await sorted(photos)
    }

    /// `LibraryFindings` of what is remembered, sorted off the main actor.
    private func sorted(_ photos: [LibraryPhoto]) async -> LibraryFindings {
        let measurements = measured.mapValues(\.value)
        let bytes = sizes.mapValues(\.value)
        let window = window
        let threshold = threshold
        return await Task.detached(priority: .userInitiated) {
            LibraryFindings(photos: photos, measurements: measurements, bytes: bytes, within: window, threshold: threshold)
        }.value
    }

    /// Runs `work` on `ids` in batches, a few at once, moving `progress`
    /// across `range` as they finish. Stops handing out batches once the task
    /// is cancelled.
    private func inBatches<Value: Sendable>(
        _ ids: [String],
        progress range: ClosedRange<Double>,
        work: @escaping @Sendable ([String]) async -> [String: Value]
    ) async -> [String: Value] {
        var batches = stride(from: 0, to: ids.count, by: Self.batchSize).map {
            Array(ids[$0 ..< min($0 + Self.batchSize, ids.count)])
        }.makeIterator()
        var results: [String: Value] = [:]
        var done = 0
        await withTaskGroup(of: (count: Int, values: [String: Value]).self) { group in
            func start() {
                guard !Task.isCancelled, let batch = batches.next() else { return }
                group.addTask { (batch.count, await work(batch)) }
            }
            for _ in 0 ..< Self.parallelBatches { start() }
            for await (count, values) in group {
                results.merge(values) { _, new in new }
                done += count
                progress = range.lowerBound + (range.upperBound - range.lowerBound) * Double(done) / Double(max(ids.count, 1))
                start()
            }
        }
        return results
    }
}
#endif
