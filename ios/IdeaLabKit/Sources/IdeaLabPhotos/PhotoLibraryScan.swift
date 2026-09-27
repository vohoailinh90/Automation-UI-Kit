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
/// that on the device (`MeasurementStore`), so a later launch does too;
/// scans made with one store share what they measured, and take turns
/// with it. Without access to the photos, every scan forgets them, on the
/// device too. Sizes it reads again on every run: with iCloud's optimized
/// storage, iOS frees a photo's original from the phone, or brings it back,
/// without changing the photo, so no size stays true for sure.
@MainActor
@Observable
public final class PhotoLibraryScan {
    /// How far the run in progress is, `0...1`, for `CleanerHomeScreen`'s
    /// `scanProgress`; `nil` when none is.
    public private(set) var progress: Double?
    /// What the latest complete run found: every photo measured, grouped and
    /// sized, all of one run, so a screen opened on it never holds sizes
    /// still to come. While another run is in progress it stays as the last
    /// one left it. `nil` until a run completes, and again once a run, of
    /// any scan, finds that the app may no longer read the photos.
    public private(set) var findings: LibraryFindings?

    /// The window and threshold of `LibraryFindings`.
    public let window: TimeInterval
    public let threshold: Float

    /// Where the measurements are kept between launches, `nil` for memory
    /// only.
    private let store: MeasurementStore?
    /// What was measured: shared by the live scans made with `store`, whose
    /// passes take turns with it; this scan's own without one.
    private let held: Held
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
    /// How many times a scan forgot the photos, any scan: access is the
    /// app's, so one forgetting stops every pass in progress.
    private static var timesForgotten = 0
    /// Every live scan, which forgetting the photos clears.
    private static var live: [WeakScan] = []
    /// Every store a scan was made with in this process, whose file
    /// forgetting the photos deletes, the scan gone or not.
    private static var stores: Set<MeasurementStore> = []
    /// The stores whose file may hold forgotten photos: never read, but
    /// deleted before a pass would read it, unless a save has replaced what
    /// it holds.
    private static var unreadable: Set<MeasurementStore> = []
    /// What the live scans made with each store hold, shared by them; gone
    /// with the last of them.
    private static var heldByStore: [MeasurementStore: WeakHeld] = [:]
    /// Where every scan reads, saves and deletes its file, one after another
    /// in the order asked: a deletion is never undone by a save asked before
    /// it, and a read asked after it finds nothing from before.
    private static let files = DispatchQueue(label: "IdeaLabPhotos.measurements", qos: .utility)

    /// - Parameter store: where to keep the measurements between launches;
    ///   `nil` keeps them in memory only. Scans made with one store share
    ///   what they measured.
    public init(window: TimeInterval = 120, threshold: Float = FeaturePrint.sameMoment, store: MeasurementStore? = .photoLibrary) {
        self.window = window
        self.threshold = threshold
        self.store = store
        if let store, let shared = Self.heldByStore[store]?.held {
            held = shared
        } else {
            held = Held()
        }
        if let store {
            Self.heldByStore[store] = WeakHeld(held: held)
            // A store new after the photos were forgotten missed the
            // deletion: its file may hold them.
            if Self.stores.insert(store).inserted, Self.timesForgotten > 0 {
                Self.unreadable.insert(store)
            }
        }
        Self.live.removeAll { $0.scan == nil }
        Self.live.append(WeakScan(scan: self))
    }

    /// Sorts the library again. When it returns, `findings` is of a pass
    /// that listed the photos after the call, so what was added, deleted or
    /// changed before it is in — unless the task running it was cancelled.
    ///
    /// Without access to the photos, it returns at once, having forgotten
    /// them for every scan: what they measured, in memory and on the
    /// device, and their `findings`. A pass in progress of any of them keeps
    /// nothing more of the photos, and every file a scan was made with is
    /// deleted.
    ///
    /// While another call's pass is in progress, it waits for that one to
    /// end, then runs a pass of its own; calls that wait together share it.
    /// When the task running it is cancelled, it stops once the photos in
    /// hand are done, keeping what it measured for the next pass, and
    /// `findings` stays as it was; a call waiting on it runs in its place.
    public func run() async {
        let needed = passesStarted + 1
        while lastCompletedPass < needed, !Task.isCancelled {
            // For every pass, a waiting call's too: access can go meanwhile.
            guard PhotoLibrary.access.canRead else {
                await forget()
                return
            }
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

    /// Forgets the photos for every scan, as when the app may no longer read
    /// them: what was measured of them, in memory and on the device, and
    /// what was found. Every pass in progress keeps nothing more of them, not
    /// even on the device, and every file a scan was made with is deleted.
    /// Returns once the files are dealt with.
    private func forget() async {
        Self.timesForgotten += 1
        Self.live.removeAll { $0.scan == nil }
        for scan in Self.live.compactMap(\.scan) {
            scan.findings = nil
            scan.held.forget()
        }
        await Self.delete(Self.stores)
    }

    /// Deletes the files of `stores`. They are not read meanwhile, nor after
    /// if deleting one fails: a pass deletes it before it would read it,
    /// unless a save has replaced what it holds.
    private static func delete(_ stores: Set<MeasurementStore>) async {
        guard !stores.isEmpty else { return }
        let generation = timesForgotten
        unreadable.formUnion(stores)
        let removed: [MeasurementStore] = await withCheckedContinuation { continuation in
            files.async {
                continuation.resume(returning: stores.filter { $0.remove() })
            }
        }
        // A later forgetting deals with them again.
        guard timesForgotten == generation else { return }
        unreadable.subtract(removed)
    }

    /// One pass: lists, measures, sizes, then publishes `findings`. Returns
    /// whether it got that far: not cancelled, nor forgotten meanwhile.
    private func sortOnce() async -> Bool {
        let generation = Self.timesForgotten
        /// Whether the photos were forgotten since the pass started, by any
        /// scan: it must then keep nothing more of them.
        func isForgotten() -> Bool { Self.timesForgotten != generation }
        // The passes of the scans sharing `held` take turns: a listing's
        // pruning never undoes what a pass that listed later measured.
        await held.take()
        defer { held.give() }
        guard !isForgotten() else { return false }

        // Off the main actor: tens of thousands of photos take a moment.
        let window = window
        let (photos, candidates) = await Task.detached(priority: .userInitiated) {
            let photos = PhotoLibrary.photos()
            return (photos, LibraryFindings.candidates(in: photos, within: window))
        }.value
        guard !isForgotten() else { return false }
        if !held.hasLoaded, let store {
            var kept: [String: MeasuredPhoto] = [:]
            if Self.unreadable.contains(store) {
                // It may hold forgotten photos: deleted, not read.
                await Self.delete([store])
            } else {
                kept = await read(store)
            }
            guard !isForgotten() else { return false }
            held.load(kept)
        }
        held.hasLoaded = true
        let modified = Dictionary(photos.map { ($0.id, $0.modified) }) { first, _ in first }
        /// Whether a measurement is of the photo as it is now.
        func isCurrent(_ id: String, _ photo: MeasuredPhoto) -> Bool {
            guard let now = modified[id] else { return false }
            return photo.modified == now
        }
        // Forget the photos gone or changed since, those kept from before
        // included.
        held.keep(where: isCurrent)

        // Measure: most of the work, most of the bar. In rounds, keeping what
        // was measured on the device every minute or so: an app iOS closes
        // during a long first pass loses little of it.
        let unmeasured = candidates.filter { held.photos[$0] == nil }
        let clock = ContinuousClock()
        var lastSave = clock.now
        for start in stride(from: 0, to: unmeasured.count, by: Self.roundSize) {
            guard !Task.isCancelled else { break }
            let ids = Array(unmeasured[start ..< min(start + Self.roundSize, unmeasured.count)])
            let share = 0.8 / Double(unmeasured.count)
            let measuredNow = await inBatches(ids, progress: share * Double(start) ... share * Double(start + ids.count)) { ids in
                await PhotoMeasurer.measure(ids)
            }
            guard !isForgotten() else { return false }
            for (id, measurement) in measuredNow where measurement.print != nil {
                held.record(MeasuredPhoto(modified: modified[id] ?? nil, measurement: measurement), for: id)
            }
            if held.isUnsaved, clock.now - lastSave >= Self.saveInterval {
                // Tried at most once a minute, even while it fails.
                await save(unlessForgottenSince: generation)
                lastSave = clock.now
            }
        }
        if held.isUnsaved {
            await save(unlessForgottenSince: generation)
        }
        guard !Task.isCancelled, !isForgotten() else { return false }

        // Size what the screens will show, all of it again, then show it.
        let unsized = await sorted(photos, bytes: [:])
        let bytes = await inBatches(unsized.sizedIDs, progress: 0.8 ... 1) { ids in await PhotoLibrary.localBytes(of: ids) }
        guard !Task.isCancelled, !isForgotten() else { return false }
        let found = await sorted(photos, bytes: bytes)
        guard !isForgotten() else { return false }
        findings = found
        return true
    }

    /// What `store` kept, read off the main actor, after the saves and
    /// deletions asked for before.
    private func read(_ store: MeasurementStore) async -> [String: MeasuredPhoto] {
        await withCheckedContinuation { continuation in
            Self.files.async {
                continuation.resume(returning: store.load())
            }
        }
    }

    /// Keeps on the device what the scans made with `store` measured, off
    /// the main actor, unless the photos were forgotten since the pass of
    /// this `generation` started. A file that cannot be written, on a full
    /// phone say, stays as it was, and what was measured stays unsaved, to
    /// be tried again: what the file holds is checked against the photos
    /// when read, as anything kept is.
    private func save(unlessForgottenSince generation: Int) async {
        guard let store, Self.timesForgotten == generation else { return }
        let photos = held.photos
        let version = held.version
        let saved = await withCheckedContinuation { continuation in
            // Queued now, before anything else can run here: a deletion
            // asked for later is queued after it.
            Self.files.async {
                do {
                    try store.save(photos)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        // Saved before a forgetting since, it holds forgotten photos.
        guard saved, Self.timesForgotten == generation else { return }
        held.saved(version)
        Self.unreadable.remove(store)
    }

    /// `LibraryFindings` of what is measured, sorted off the main actor.
    private func sorted(_ photos: [LibraryPhoto], bytes: [String: Int64]) async -> LibraryFindings {
        let measurements = held.photos.mapValues(\.measurement)
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

/// What the scans made with one store measured, held in memory once for
/// all of them; a scan without a store holds its own.
@MainActor
private final class Held {
    /// By photo id.
    private(set) var photos: [String: MeasuredPhoto] = [:]
    /// Whether `photos` has what the file kept: read by the first pass, and
    /// again by the first after the photos are forgotten, when the file
    /// holds only what was measured since.
    var hasLoaded = false
    /// Changes to `photos`, and the latest of them kept on the device.
    private(set) var version = 0
    private var savedVersion = 0
    /// Whether a pass has it, and the passes waiting their turn, in order.
    private var isTaken = false
    private var turns: [CheckedContinuation<Void, Never>] = []

    /// Whether `photos` changed since it was last kept on the device.
    var isUnsaved: Bool {
        version != savedVersion
    }

    /// Waits for the passes before to be done with it. Every call is
    /// followed by one to `give()`.
    func take() async {
        if isTaken {
            await withCheckedContinuation { turns.append($0) }
        } else {
            isTaken = true
        }
    }

    /// Hands it to the next pass waiting, if any.
    func give() {
        if turns.isEmpty {
            isTaken = false
        } else {
            turns.removeFirst().resume()
        }
    }

    func record(_ photo: MeasuredPhoto, for id: String) {
        photos[id] = photo
        version += 1
    }

    /// Keeps only the photos still as they were measured.
    func keep(where isCurrent: (String, MeasuredPhoto) -> Bool) {
        let kept = photos.filter { isCurrent($0.key, $0.value) }
        if kept.count != photos.count {
            photos = kept
            version += 1
        }
    }

    /// Adds what the file kept; what was measured since wins.
    func load(_ kept: [String: MeasuredPhoto]) {
        photos.merge(kept) { inMemory, _ in inMemory }
    }

    /// A save of `version` succeeded.
    func saved(_ version: Int) {
        savedVersion = max(savedVersion, version)
    }

    /// Forgets the photos, as when the app may no longer read them.
    func forget() {
        photos = [:]
        hasLoaded = false
        savedVersion = version
    }
}

/// A live scan, not kept alive by the list of them.
private struct WeakScan {
    weak var scan: PhotoLibraryScan?
}

/// A `Held` of the registry, not kept alive by it.
private struct WeakHeld {
    weak var held: Held?
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
