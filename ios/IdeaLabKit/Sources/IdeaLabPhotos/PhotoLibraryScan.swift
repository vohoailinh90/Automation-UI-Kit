#if os(iOS)
import Foundation
import IdeaLabCore
import Observation
import Photos

/// Sorts the photo library for the cleaner, on the device: lists the photos
/// and videos, looks at every photo not looked at yet for a QR code or a
/// document and for how well it was taken, and measures the
/// `LibraryFindings.candidates` (sharpness and feature print), groups the
/// look-alikes, sizes the videos, then sizes what the screens show.
///
/// Run it when the cleaner opens, and again after deleting or when the app
/// comes back. The first run looks at the whole library, a few minutes for
/// tens of thousands of photos, and reads every video; it remembers what it
/// measured and read, by item and the item's last change, so a later run
/// only measures new or edited photos and reads new or edited videos, and
/// keeps that on the device (`MeasurementStore`, and the videos' sizes in a
/// file beside it), so a later launch does too; scans made with one store
/// share what they measured, and take turns with it. Without access to the
/// photos, every scan forgets them, on the device too, for this launch and
/// the next. With iCloud's optimized storage, iOS frees an item's original
/// from the phone, or brings it back, without changing the item, so no size
/// stays true for sure: a photo's it reads again on every run, and of a
/// video read before it checks that each part is here still, unless the
/// video took too little to be offered even then.
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

    /// The window, threshold, `blurryBelow` and `largeVideoAtLeast` of
    /// `LibraryFindings`.
    public let window: TimeInterval
    public let threshold: Float
    public let blurryBelow: Float
    public let largeVideoAtLeast: Int64

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
    /// Videos handed to one task at once: reading one can take seconds.
    private static let videoBatchSize = 2
    /// Photos measured, or videos sized, between looks at whether to keep
    /// them on the device, and how often they are kept while a pass works.
    private static let roundSize = batchSize * parallelBatches * 4
    private static let videoRoundSize = videoBatchSize * parallelBatches * 4
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

    /// - Parameter store: where to keep the measurements between launches,
    ///   and the videos' sizes in a file beside it; `nil` keeps them in
    ///   memory only. Scans made with one store share what they measured.
    public init(
        window: TimeInterval = 120,
        threshold: Float = FeaturePrint.sameMoment,
        blurryBelow: Float = LibraryFindings.blurryBelow,
        largeVideoAtLeast: Int64 = LibraryFindings.largeVideoAtLeast,
        store: MeasurementStore? = .photoLibrary
    ) {
        self.window = window
        self.threshold = threshold
        self.blurryBelow = blurryBelow
        self.largeVideoAtLeast = largeVideoAtLeast
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
                    store.videoSizes(forgetting: 0).remove()
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
        let (photos, videos, candidates) = await Task.detached(priority: .userInitiated) {
            let photos = PhotoLibrary.photos()
            return (photos, PhotoLibrary.videos(), LibraryFindings.candidates(in: photos, within: window))
        }.value
        guard !isForgotten() else { return false }
        if !held.hasLoaded, let store {
            let (kept, keptVideos) = await read(store.since(forgetting: generation), store.videoSizes(forgetting: generation))
            guard !isForgotten() else { return false }
            held.load(kept, videos: keptVideos)
        }
        held.hasLoaded = true
        let modified = Dictionary(photos.map { ($0.id, $0.modified) }) { first, _ in first }
        /// Whether a measurement is of the photo as it is now.
        func isCurrent(_ id: String, _ photo: MeasuredPhoto) -> Bool {
            guard let now = modified[id] else { return false }
            return photo.modified == now
        }
        // Forget the photos gone or changed since, those kept from before
        // included, and the videos too.
        held.keep(where: isCurrent)
        let videoModified = Dictionary(videos.map { ($0.id, $0.modified) }) { first, _ in first }
        held.keepVideos { id, video in
            guard let now = videoModified[id] else { return false }
            return video.modified == now
        }

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
            let share = 0.7 / Double(toMeasure.count)
            let measuredNow = await inBatches(ids, progress: share * Double(start) ... share * Double(start + ids.count)) { [prints, looks] ids in
                await PhotoMeasurer.measure(ids, prints: prints, looks: looks)
            }
            guard !isForgotten() else { return false }
            for (id, measured) in measuredNow {
                // What was not asked for this time is kept from before: the
                // photo has not changed since, or it would have been pruned.
                let measurement = measured.keeping(held.photos[id]?.measurement)
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

        // Size the videos: what each takes decides whether it is offered,
        // so every one that may take enough. One read before, unchanged
        // since, is only checked to be here still, by `PhotoLibrary`; one
        // that took too little even then is left alone, as it cannot have
        // grown. The others are read, every byte: in rounds, kept on the
        // device as the photos are.
        let largeVideoAtLeast = largeVideoAtLeast
        var listedVideos = Set<String>()
        let toSize = videos.filter { video in
            guard listedVideos.insert(video.id).inserted, !video.isFavorite else { return false }
            return held.videos[video.id]?.mayTake(atLeast: largeVideoAtLeast) ?? true
        }.map(\.id)
        var bytes: [String: Int64] = [:]
        for start in stride(from: 0, to: toSize.count, by: Self.videoRoundSize) {
            guard !Task.isCancelled else { break }
            let ids = Array(toSize[start ..< min(start + Self.videoRoundSize, toSize.count)])
            let share = 0.2 / Double(toSize.count)
            let known = held.videos
            let sized = await inBatches(
                ids, size: Self.videoBatchSize, progress: 0.7 + share * Double(start) ... 0.7 + share * Double(start + ids.count)
            ) { ids in
                await PhotoLibrary.localBytes(ofVideos: ids, known: known)
            }
            guard !isForgotten() else { return false }
            for (id, size) in sized {
                held.record(size.sized, for: id)
                bytes[id] = size.bytes
            }
            if held.isUnsaved, clock.now - lastSave >= Self.saveInterval {
                await save(unlessForgottenSince: generation)
                lastSave = clock.now
            }
        }
        if held.isUnsaved {
            await save(unlessForgottenSince: generation)
        }
        guard !Task.isCancelled, !isForgotten() else { return false }

        // Size what the screens will show of the photos, all of it again,
        // then show it.
        let unsized = await sorted(photos, videos, bytes: [:])
        let photoBytes = await inBatches(unsized.sizedIDs, progress: 0.9 ... 1) { ids in await PhotoLibrary.localBytes(of: ids) }
        guard !Task.isCancelled, !isForgotten() else { return false }
        bytes.merge(photoBytes) { _, photo in photo }
        let found = await sorted(photos, videos, bytes: bytes)
        guard !isForgotten() else { return false }
        findings = found
        return true
    }

    /// What `store` and `videoStore` kept, read off the main actor, after
    /// the saves and deletions asked for before.
    private func read(_ store: MeasurementStore, _ videoStore: VideoSizeStore) async -> ([String: MeasuredPhoto], [String: SizedVideo]) {
        await withCheckedContinuation { continuation in
            Self.files.async {
                continuation.resume(returning: (store.load(), videoStore.load()))
            }
        }
    }

    /// Keeps on the device what the scans made with `store` measured, and
    /// the videos' sizes they read, off the main actor, unless the photos
    /// were forgotten since the pass of this `generation` started. A file
    /// that cannot be written, on a full phone say, stays as it was, and
    /// what it was to hold stays unsaved, to be tried again: what a file
    /// holds is checked against the library when read, as anything kept is.
    private func save(unlessForgottenSince generation: Int) async {
        guard let store, Self.timesForgotten == generation else { return }
        let photoFile = store.since(forgetting: generation)
        let videoFile = store.videoSizes(forgetting: generation)
        // Each file only if it changed: sizing a video does not rewrite the
        // photos' measurements, nor the other way round.
        let photos = held.arePhotosUnsaved ? held.photos : nil
        let videos = held.areVideosUnsaved ? held.videos : nil
        let version = held.version
        let saved: (photos: Bool, videos: Bool) = await withCheckedContinuation { continuation in
            // Queued now, before anything else can run here: a deletion
            // asked for later is queued after it.
            Self.files.async {
                let photosSaved = photos.map { (try? photoFile.save($0)) != nil } ?? false
                let videosSaved = videos.map { (try? videoFile.save($0)) != nil } ?? false
                continuation.resume(returning: (photos: photosSaved, videos: videosSaved))
            }
        }
        // Saved before a forgetting since, they hold forgotten photos.
        guard Self.timesForgotten == generation else { return }
        held.saved(version, photos: saved.photos, videos: saved.videos)
    }

    /// `LibraryFindings` of what is measured, sorted off the main actor.
    private func sorted(_ photos: [LibraryPhoto], _ videos: [LibraryVideo], bytes: [String: Int64]) async -> LibraryFindings {
        let measurements = held.photos.mapValues(\.measurement)
        let window = window
        let threshold = threshold
        let blurryBelow = blurryBelow
        let largeVideoAtLeast = largeVideoAtLeast
        return await Task.detached(priority: .userInitiated) {
            LibraryFindings(
                photos: photos, videos: videos, measurements: measurements, bytes: bytes, within: window, threshold: threshold,
                blurryBelow: blurryBelow, largeVideoAtLeast: largeVideoAtLeast
            )
        }.value
    }

    /// Runs `work` on `ids` in batches of `size`, a few at once, moving
    /// `progress` across `range` as they finish. Stops handing out batches
    /// once the task is cancelled.
    private func inBatches<Value: Sendable>(
        _ ids: [String],
        size: Int = PhotoLibraryScan.batchSize,
        progress range: ClosedRange<Double>,
        work: @escaping @Sendable ([String]) async -> [String: Value]
    ) async -> [String: Value] {
        var batches = stride(from: 0, to: ids.count, by: size).map {
            Array(ids[$0 ..< min($0 + size, ids.count)])
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
    /// What was read of the videos, by video id.
    private(set) var videos: [String: SizedVideo] = [:]
    /// Whether `photos` and `videos` have what the files kept: read by the
    /// first pass, and again by the first after the photos are forgotten,
    /// when the files hold only what was measured since.
    var hasLoaded = false
    /// Changes to `photos` and `videos`, and the latest of each kept on the
    /// device.
    private(set) var version = HeldVersion()
    private var savedVersion = HeldVersion()
    /// Whether a pass has it, and the passes waiting their turn, in order.
    private var isTaken = false
    private var turns: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private var lastTurn = 0

    /// Whether `photos` or `videos` changed since last kept on the device.
    var isUnsaved: Bool {
        version != savedVersion
    }

    var arePhotosUnsaved: Bool {
        version.photos != savedVersion.photos
    }

    var areVideosUnsaved: Bool {
        version.videos != savedVersion.videos
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
        version.photos += 1
    }

    /// Only a change counts: a video found as it was read needs no save.
    func record(_ video: SizedVideo, for id: String) {
        guard videos[id] != video else { return }
        videos[id] = video
        version.videos += 1
    }

    /// Keeps only the photos still as they were measured.
    func keep(where isCurrent: (String, MeasuredPhoto) -> Bool) {
        let kept = photos.filter { isCurrent($0.key, $0.value) }
        if kept.count != photos.count {
            photos = kept
            version.photos += 1
        }
    }

    /// Keeps only the videos still as they were read.
    func keepVideos(where isCurrent: (String, SizedVideo) -> Bool) {
        let kept = videos.filter { isCurrent($0.key, $0.value) }
        if kept.count != videos.count {
            videos = kept
            version.videos += 1
        }
    }

    /// Adds what the files kept; what was measured since wins.
    func load(_ kept: [String: MeasuredPhoto], videos keptVideos: [String: SizedVideo]) {
        photos.merge(kept) { inMemory, _ in inMemory }
        videos.merge(keptVideos) { inMemory, _ in inMemory }
    }

    /// A save of `version` succeeded, for the photos, the videos, or both.
    func saved(_ version: HeldVersion, photos: Bool, videos: Bool) {
        if photos {
            savedVersion.photos = max(savedVersion.photos, version.photos)
        }
        if videos {
            savedVersion.videos = max(savedVersion.videos, version.videos)
        }
    }

    /// Forgets the photos and videos, as when the app may no longer read
    /// them.
    func forget() {
        photos = [:]
        videos = [:]
        hasLoaded = false
        savedVersion = version
    }
}

/// How many times `Held`'s photos and videos changed.
private struct HeldVersion: Equatable {
    var photos = 0
    var videos = 0
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

    /// The file beside this one where the scans made with it keep the
    /// videos' sizes, "Measurements-videos.plist" beside
    /// "Measurements.plist", as it holds videos read after the photos were
    /// forgotten `times` times. A file of its own: sizing a video does not
    /// rewrite the photos' measurements, and measuring photos another way
    /// does not throw the sizes away.
    fileprivate func videoSizes(forgetting times: Int) -> VideoSizeStore {
        let name = url.deletingPathExtension().lastPathComponent + "-videos"
        let file = url.deletingLastPathComponent().appending(path: url.pathExtension.isEmpty ? name : "\(name).\(url.pathExtension)")
        return VideoSizeStore(url: file, method: "\(PhotoLibrary.videoSizing); forgotten \(times) times")
    }

    /// Where `PhotoLibraryScan` keeps the library's measurements unless told
    /// otherwise: in the app's Caches folder, which is not backed up, and
    /// which iOS may empty when the phone is short of space; the photos are
    /// then measured again, and the videos read again.
    public static var photoLibrary: MeasurementStore {
        MeasurementStore(url: .cachesDirectory.appending(path: "IdeaLabPhotos/Measurements.plist"), method: PhotoMeasurer.method)
    }
}
#endif
