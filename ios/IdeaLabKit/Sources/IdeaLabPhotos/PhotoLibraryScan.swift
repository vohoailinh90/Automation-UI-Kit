#if os(iOS)
import Foundation
import IdeaLabCore
import Observation
import Photos

/// Sorts the photo library for the cleaner, on the device: lists the photos,
/// looks at every one not looked at yet for a QR code or a document, and
/// measures the `LibraryFindings.candidates` (sharpness and feature print),
/// groups the look-alikes, then sizes what the screens show.
///
/// Run it when the cleaner opens, and again after deleting or when the app
/// comes back. The first run looks at the whole library, a few minutes for
/// tens of thousands of photos; it remembers what it measured, by photo and
/// the photo's last change, so a later run only measures new or edited
/// photos, and keeps
/// that on the device (`MeasurementStore`), so a later launch does too;
/// scans made with one store share what they measured, and take turns
/// with it. Without access to the photos, every scan forgets them, on the
/// device too, for this launch and the next. Sizes it reads again on every
/// run: with iCloud's optimized storage, iOS frees a photo's original from
/// the phone, or brings it back, without changing the photo, so no size
/// stays true for sure.
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
    /// How many times a scan forgot the photos, any scan, in this launch or
    /// before: access is the app's, so one forgetting stops every pass in
    /// progress. Kept in the app's defaults, and in every file saved, as
    /// part of its method (`since(forgetting:)`): a file saved before a
    /// forgetting reads as empty, even if deleting it failed, even in a
    /// later launch.
    private static var timesForgotten = UserDefaults.standard.integer(forKey: forgettingsKey)
    private static let forgettingsKey = "IdeaLabPhotos.PhotoLibraryScan.timesForgotten"
    /// Every live scan, which forgetting the photos clears.
    private static var live: [WeakScan] = []
    /// Every store a scan was made with in this process, whose file
    /// forgetting the photos deletes, the scan gone or not.
    private static var stores: Set<MeasurementStore> = []
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
            Self.stores.insert(store)
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
    /// nothing more of the photos, every file a scan was made with is
    /// deleted, and any file saved before, deleted or not, reads as empty
    /// from then on, in later launches too.
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
    /// even on the device, and every file saved before reads as empty from
    /// now on, in later launches too; those of the stores scans were made
    /// with are deleted as well. Returns once they are.
    private func forget() async {
        Self.timesForgotten += 1
        UserDefaults.standard.set(Self.timesForgotten, forKey: Self.forgettingsKey)
        Self.live.removeAll { $0.scan == nil }
        for scan in Self.live.compactMap(\.scan) {
            scan.findings = nil
            scan.held.forget()
        }
        let stores = Self.stores
        guard !stores.isEmpty else { return }
        await withCheckedContinuation { continuation in
            Self.files.async {
                for store in stores {
                    store.remove()
                }
                continuation.resume()
            }
        }
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
        guard await held.take() else { return false }
        defer { held.give() }
        guard !Task.isCancelled, !isForgotten() else { return false }

        // Off the main actor: tens of thousands of photos take a moment.
        let window = window
        let (photos, candidates) = await Task.detached(priority: .userInitiated) {
            let photos = PhotoLibrary.photos()
            return (photos, LibraryFindings.candidates(in: photos, within: window))
        }.value
        guard !isForgotten() else { return false }
        if !held.hasLoaded, let store {
            let kept = await read(store.since(forgetting: generation))
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

        // Measure: most of the work, most of the bar. Every photo but a
        // screenshot is looked at, once; a candidate is measured for its
        // print too. In rounds, keeping what was measured on the device every
        // minute or so: an app iOS closes during a long first pass loses
        // little of it.
        // Only what is missing: a photo looked at keeps what it showed while
        // its print is tried again.
        let groupable = Set(candidates)
        var toMeasure: [String] = []
        var looks = Set<String>()
        var prints = Set<String>()
        for photo in photos where !photo.isScreenshot {
            let kept = held.photos[photo.id]?.measurement
            if kept?.content == nil {
                looks.insert(photo.id)
            }
            if groupable.contains(photo.id), kept?.print == nil {
                prints.insert(photo.id)
            }
            if looks.contains(photo.id) || prints.contains(photo.id) {
                toMeasure.append(photo.id)
            }
        }
        let clock = ContinuousClock()
        var lastSave = clock.now
        for start in stride(from: 0, to: toMeasure.count, by: Self.roundSize) {
            guard !Task.isCancelled else { break }
            let ids = Array(toMeasure[start ..< min(start + Self.roundSize, toMeasure.count)])
            let share = 0.8 / Double(toMeasure.count)
            let measuredNow = await inBatches(ids, progress: share * Double(start) ... share * Double(start + ids.count)) { [prints, looks] ids in
                await PhotoMeasurer.measure(ids, prints: prints, looks: looks)
            }
            guard !isForgotten() else { return false }
            for (id, measured) in measuredNow {
                // What was not asked for this time is kept from before: the
                // photo has not changed since, or it would have been pruned.
                let kept = held.photos[id]?.measurement
                let measurement = PhotoMeasurement(
                    sharpness: measured.sharpness,
                    print: measured.print ?? kept?.print,
                    content: measured.content ?? kept?.content
                )
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
        guard let store = store?.since(forgetting: generation), Self.timesForgotten == generation else { return }
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
    private var turns: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private var lastTurn = 0

    /// Whether `photos` changed since it was last kept on the device.
    var isUnsaved: Bool {
        version != savedVersion
    }

    /// Waits for the passes before to be done with it. Returns whether this
    /// pass has it: not when its task is cancelled first, which ends the
    /// wait. A pass that has it calls `give()` when done.
    func take() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard isTaken else {
            isTaken = true
            return true
        }
        lastTurn += 1
        let id = lastTurn
        return await withTaskCancellationHandler {
            await withCheckedContinuation { turns.append((id, $0)) }
        } onCancel: {
            Task { @MainActor in self.drop(id) }
        }
    }

    /// Hands it to the next pass waiting, if any.
    func give() {
        if turns.isEmpty {
            isTaken = false
        } else {
            turns.removeFirst().continuation.resume(returning: true)
        }
    }

    /// Ends the wait of a cancelled pass, unless it had its turn already.
    private func drop(_ id: Int) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        turns.remove(at: index).continuation.resume(returning: false)
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
    /// The same file, as it holds photos measured after the photos were
    /// forgotten `times` times: a file saved before one of them, of another
    /// method so, reads as empty.
    fileprivate func since(forgetting times: Int) -> MeasurementStore {
        MeasurementStore(url: url, method: "\(method); forgotten \(times) times")
    }

    /// Where `PhotoLibraryScan` keeps the library's measurements unless told
    /// otherwise: in the app's Caches folder, which is not backed up, and
    /// which iOS may empty when the phone is short of space; the photos are
    /// then measured again.
    public static var photoLibrary: MeasurementStore {
        MeasurementStore(url: .cachesDirectory.appending(path: "IdeaLabPhotos/Measurements.plist"), method: PhotoMeasurer.method)
    }
}
#endif
