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
/// comes back. It remembers what it measured, by photo and the photo's last
/// change, so a later run only measures new or edited photos; it keeps that
/// in memory only, so a library of tens of thousands of photos is measured
/// again on the next launch. Sizes it reads again on every run: with
/// iCloud's optimized storage, iOS frees a photo's original from the phone,
/// or brings it back, without changing the photo, so no size stays true
/// for sure.
@MainActor
@Observable
public final class PhotoLibraryScan {
    /// How far the run in progress is, `0...1`, for `CleanerHomeScreen`'s
    /// `scanProgress`; `nil` when none is.
    public private(set) var progress: Double?
    /// What the latest complete run found: every photo measured, grouped and
    /// sized, all of one run, so a screen opened on it never holds sizes
    /// still to come. While another run is in progress it stays as the last
    /// one left it. `nil` until a run completes.
    public private(set) var findings: LibraryFindings?

    /// The window and threshold of `LibraryFindings`.
    public let window: TimeInterval
    public let threshold: Float

    @ObservationIgnored private var measured: [String: Measured] = [:]
    /// A run was asked for while one was in progress: that one goes again.
    @ObservationIgnored private var isAskedAgain = false

    /// A photo's measurement, and when the photo last changed then.
    private struct Measured: Sendable {
        let modified: Date?
        let measurement: PhotoMeasurement
    }

    /// Photos handed to one background task at once, and tasks at once.
    private static let batchSize = 24
    private static let parallelBatches = 3

    public init(window: TimeInterval = 120, threshold: Float = FeaturePrint.sameMoment) {
        self.window = window
        self.threshold = threshold
    }

    /// Sorts the library again. Returns at once without access to the
    /// photos. While another run is in progress, it asks that one to go
    /// again once it is done, from a new list of the photos, so what was
    /// added, deleted or changed meanwhile is not missed; and it returns at
    /// once: `progress` and `findings` say how that one goes. When the task
    /// running it is cancelled, it stops once the photos in hand are done,
    /// keeping what it measured for the next run; `findings` stays as it
    /// was, and a pass asked for meanwhile is dropped with it, since the next
    /// run lists the photos afresh anyway.
    public func run() async {
        guard PhotoLibrary.access.canRead else { return }
        guard progress == nil else {
            isAskedAgain = true
            return
        }
        defer { progress = nil }
        repeat {
            isAskedAgain = false
            progress = 0
            await sortOnce()
        } while isAskedAgain && !Task.isCancelled
    }

    /// One pass: lists, measures, sizes, then publishes `findings`.
    private func sortOnce() async {
        // Off the main actor: tens of thousands of photos take a moment.
        let window = window
        let (listed, candidates) = await Task.detached(priority: .userInitiated) {
            let listed = PhotoLibrary.listed()
            return (listed, LibraryFindings.candidates(in: listed.map(\.photo), within: window))
        }.value
        let modified = Dictionary(listed.map { ($0.photo.id, $0.modified) }) { first, _ in first }
        /// Whether a measurement is of the photo as it is now.
        func isCurrent(_ id: String) -> Bool {
            guard let remembered = measured[id], let now = modified[id] else { return false }
            return remembered.modified == now
        }
        let photos = listed.map(\.photo)

        // Measure: most of the work, most of the bar.
        let unmeasured = candidates.filter { !isCurrent($0) }
        let measuredNow = await inBatches(unmeasured, progress: 0 ... 0.8) { ids in await PhotoMeasurer.measure(ids) }
        for (id, measurement) in measuredNow where measurement.print != nil {
            measured[id] = Measured(modified: modified[id] ?? nil, measurement: measurement)
        }
        guard !Task.isCancelled else { return }
        // Forget the photos gone or changed since.
        measured = measured.filter { isCurrent($0.key) }

        // Size what the screens will show, all of it again, then show it.
        let unsized = await sorted(photos, bytes: [:])
        let bytes = await inBatches(unsized.sizedIDs, progress: 0.8 ... 1) { ids in await PhotoLibrary.localBytes(of: ids) }
        guard !Task.isCancelled else { return }
        findings = await sorted(photos, bytes: bytes)
    }

    /// `LibraryFindings` of what is measured, sorted off the main actor.
    private func sorted(_ photos: [LibraryPhoto], bytes: [String: Int64]) async -> LibraryFindings {
        let measurements = measured.mapValues(\.measurement)
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
