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
/// change, so a later run only measures new or edited photos, and keeps
/// that on the device (`MeasurementStore`), so a later launch does too.
/// Without access to the photos, it deletes what it kept of them. Sizes it
/// reads again on every run: with
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

    /// Where the measurements are kept between launches, `nil` for memory
    /// only.
    private let store: MeasurementStore?
    @ObservationIgnored private var measured: [String: MeasuredPhoto] = [:]
    /// Whether `measured` has what `store` kept: read once, by the first pass.
    @ObservationIgnored private var hasLoaded = false
    /// Passes started so far, and the latest that completed: a call is done
    /// once a pass that started after it completes.
    @ObservationIgnored private var passesStarted = 0
    @ObservationIgnored private var lastCompletedPass = 0
    /// Calls waiting for the pass in progress to end.
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Photos handed to one background task at once, and tasks at once.
    private static let batchSize = 24
    private static let parallelBatches = 3
    /// Photos measured between looks at whether to keep them on the device,
    /// and how often they are kept while a pass measures.
    private static let roundSize = batchSize * parallelBatches * 4
    private static let saveInterval = Duration.seconds(60)

    /// - Parameter store: where to keep the measurements between launches;
    ///   `nil` keeps them in memory only.
    public init(window: TimeInterval = 120, threshold: Float = FeaturePrint.sameMoment, store: MeasurementStore? = .photoLibrary) {
        self.window = window
        self.threshold = threshold
        self.store = store
    }

    /// Sorts the library again. When it returns, `findings` is of a pass
    /// that listed the photos after the call, so what was added, deleted or
    /// changed before it is in — unless the task running it was cancelled.
    /// Returns at once without access to the photos, once it has deleted
    /// what it kept of them.
    ///
    /// While another call's pass is in progress, it waits for that one to
    /// end, then runs a pass of its own; calls that wait together share it.
    /// When the task running it is cancelled, it stops once the photos in
    /// hand are done, keeping what it measured for the next pass, and
    /// `findings` stays as it was; a call waiting on it runs in its place.
    public func run() async {
        guard PhotoLibrary.access.canRead else {
            // What was measured of photos the app may no longer see goes
            // with the access: one file, quickly deleted.
            measured = [:]
            store?.remove()
            return
        }
        let needed = passesStarted + 1
        while lastCompletedPass < needed, !Task.isCancelled {
            if progress != nil {
                await withCheckedContinuation { waiting.append($0) }
                continue
            }
            passesStarted += 1
            let pass = passesStarted
            progress = 0
            if await sortOnce() {
                lastCompletedPass = pass
            }
            progress = nil
            let waited = waiting
            waiting = []
            for call in waited {
                call.resume()
            }
        }
    }

    /// One pass: lists, measures, sizes, then publishes `findings`. Returns
    /// whether it got that far, not cancelled.
    private func sortOnce() async -> Bool {
        // Off the main actor: tens of thousands of photos take a moment, and
        // so does the file of what they measured.
        let window = window
        let unread = hasLoaded ? nil : store
        let (photos, candidates, kept) = await Task.detached(priority: .userInitiated) {
            let photos = PhotoLibrary.photos()
            return (photos, LibraryFindings.candidates(in: photos, within: window), unread?.load() ?? [:])
        }.value
        if !hasLoaded {
            hasLoaded = true
            measured.merge(kept) { inMemory, _ in inMemory }
        }
        let modified = Dictionary(photos.map { ($0.id, $0.modified) }) { first, _ in first }
        /// Whether a measurement is of the photo as it is now.
        func isCurrent(_ id: String) -> Bool {
            guard let remembered = measured[id], let now = modified[id] else { return false }
            return remembered.modified == now
        }
        // Forget the photos gone or changed since, those kept from before
        // included.
        let remembered = measured.count
        measured = measured.filter { isCurrent($0.key) }
        var unsaved = measured.count != remembered

        // Measure: most of the work, most of the bar. In rounds, keeping what
        // was measured on the device every minute or so: an app iOS closes
        // during a long first pass loses little of it.
        let unmeasured = candidates.filter { !isCurrent($0) }
        let clock = ContinuousClock()
        var lastSave = clock.now
        for start in stride(from: 0, to: unmeasured.count, by: Self.roundSize) {
            guard !Task.isCancelled else { break }
            let ids = Array(unmeasured[start ..< min(start + Self.roundSize, unmeasured.count)])
            let share = 0.8 / Double(unmeasured.count)
            let measuredNow = await inBatches(ids, progress: share * Double(start) ... share * Double(start + ids.count)) { ids in
                await PhotoMeasurer.measure(ids)
            }
            for (id, measurement) in measuredNow where measurement.print != nil {
                measured[id] = MeasuredPhoto(modified: modified[id] ?? nil, measurement: measurement)
                unsaved = true
            }
            if unsaved, clock.now - lastSave >= Self.saveInterval {
                await save()
                unsaved = false
                lastSave = clock.now
            }
        }
        if unsaved {
            await save()
        }
        guard !Task.isCancelled else { return false }

        // Size what the screens will show, all of it again, then show it.
        let unsized = await sorted(photos, bytes: [:])
        let bytes = await inBatches(unsized.sizedIDs, progress: 0.8 ... 1) { ids in await PhotoLibrary.localBytes(of: ids) }
        guard !Task.isCancelled else { return false }
        findings = await sorted(photos, bytes: bytes)
        return true
    }

    /// Keeps what is measured on the device, off the main actor. A file that
    /// cannot be written, on a full phone say, stays as it was: what it
    /// holds is checked against the photos when read, as anything kept is.
    private func save() async {
        guard let store else { return }
        let photos = measured
        await Task.detached(priority: .utility) {
            try? store.save(photos)
        }.value
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

extension MeasurementStore {
    /// Where `PhotoLibraryScan` keeps the library's measurements unless told
    /// otherwise: in the app's Caches folder, which is not backed up, and
    /// which iOS may empty when the phone is short of space; the photos are
    /// then measured again.
    public static var photoLibrary: MeasurementStore {
        MeasurementStore(url: .cachesDirectory.appending(path: "IdeaLabPhotos/Measurements.plist"), method: PhotoMeasurer.method)
    }
}
#endif
