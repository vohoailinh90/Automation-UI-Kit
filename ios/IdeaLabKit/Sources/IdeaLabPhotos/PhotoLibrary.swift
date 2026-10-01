#if os(iOS)
import IdeaLabCore
import os
import Photos
import UIKit

/// How much of the photo library the app may see and change.
public enum PhotoAccess: Hashable, Sendable {
    /// Not asked yet: explain first (`PermissionPrimerScreen`), then
    /// `PhotoLibrary.requestAccess()`.
    case notAsked
    /// Refused. Only Settings can change it: `PhotoLibrary.openSettings()`.
    case denied
    /// Not the person's to give, as under Screen Time's limits: Settings
    /// cannot change it either, so say so without offering it.
    case restricted
    /// The photos the person chose: the cleaner sees, and cleans, only those.
    case limited
    case full

    /// Whether the app can list and delete photos.
    public var canRead: Bool {
        self == .limited || self == .full
    }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notAsked
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .limited: self = .limited
        case .authorized: self = .full
        @unknown default: self = .denied
        }
    }
}

/// What `PhotoLibrary.delete` did, to photos and videos alike.
public struct PhotoDeletion: Hashable, Sendable {
    /// The photos no longer in the library: deleted now, or gone already.
    public let gone: Set<String>
    /// The photos that are favourites now, or burst shots the person picked
    /// in Photos, though perhaps not when they were listed: never deleted,
    /// and not to be offered again.
    public let favorites: Set<String>
    /// The photos changed since they were listed, edited say: not deleted,
    /// since they may not be what was judged, and not to be offered again
    /// until they are sorted anew.
    public let changed: Set<String>
    /// How many photos and videos this deletion removed, for
    /// `FreeAllowance.use`.
    public let deletedCount: Int

    public init(gone: Set<String>, favorites: Set<String> = [], changed: Set<String> = [], deletedCount: Int) {
        self.gone = gone
        self.favorites = favorites
        self.changed = changed
        self.deletedCount = deletedCount
    }

    /// What the screens take out, as `onDelete` returns it: the photos gone,
    /// the favourites, and the photos changed.
    public var settled: Set<String> {
        gone.union(favorites).union(changed)
    }
}

/// The person's photo library, for the cleaner: access, the photos and
/// videos to sort, what deleting them frees, and deleting them. They are
/// read on the device only: nothing is downloaded from iCloud, and nothing
/// leaves the phone.
public enum PhotoLibrary {
    /// Read and write: a cleaner deletes.
    public static var access: PhotoAccess {
        PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Asks iOS for access. iOS asks the person once; after that this returns
    /// the answer they gave.
    public static func requestAccess() async -> PhotoAccess {
        PhotoAccess(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    /// The app's page in Settings, where access can be changed.
    @MainActor
    public static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// The library's photos, as `LibraryFindings` takes them: the images of
    /// the person's own library, hidden ones left out, and every shot of a
    /// burst, not only its pick: those are the look-alikes most worth
    /// cleaning. Photos synced from a computer are left out: only that
    /// computer can delete them. A burst shot the person picked in Photos is
    /// kept as a favourite is.
    ///
    /// Lists the whole library, which takes a moment with tens of thousands
    /// of photos: call it off the main actor.
    public static func photos() -> [LibraryPhoto] {
        let options = fetchOptions()
        options.includeAssetSourceTypes = .typeUserLibrary
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var photos: [LibraryPhoto] = []
        photos.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            photos.append(LibraryPhoto(
                id: asset.localIdentifier,
                // A photo with no date sorts first, before any moment.
                date: asset.creationDate ?? .distantPast,
                isFavorite: asset.isKeptByPerson,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                modified: asset.modificationDate
            ))
        }
        return photos
    }

    /// The library's videos, as `LibraryFindings` takes them: those of the
    /// person's own library, hidden ones left out, and those synced from a
    /// computer, which only that computer can delete.
    ///
    /// Lists the whole library: call it off the main actor.
    public static func videos() -> [LibraryVideo] {
        let options = fetchOptions()
        options.includeAssetSourceTypes = .typeUserLibrary
        let assets = PHAsset.fetchAssets(with: .video, options: options)
        var videos: [LibraryVideo] = []
        videos.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            videos.append(LibraryVideo(
                id: asset.localIdentifier,
                // A video with no date sorts last among those of one size.
                date: asset.creationDate ?? .distantPast,
                isFavorite: asset.isKeptByPerson,
                duration: asset.duration,
                modified: asset.modificationDate
            ))
        }
        return videos
    }

    /// Fetches, by id, burst shots too: by default a fetch leaves out a
    /// burst's shots other than its representative and the person's picks.
    static func assets(_ ids: [String]) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: fetchOptions())
    }

    private static func fetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        return options
    }

    /// Deletes photos and videos, never a favourite, nor one changed since
    /// it was listed. iOS asks the person first, then keeps them in "Đã xoá
    /// gần đây" for 30 days.
    ///
    /// A photo made a favourite since it was listed, in Photos say, is kept
    /// and returned in `favorites`. When the person says no, or the deletion
    /// fails, nothing is deleted: `gone` then holds only the photos that were
    /// gone already.
    ///
    /// - Parameter listed: when each photo last changed as it was listed,
    ///   `nil` if it had no date then: `LibraryFindings.modificationDates`.
    ///   One that has changed since, as when it was edited while a review of
    ///   it was open, is kept and returned in `changed`. A photo not in it is
    ///   not checked.
    public static func delete(_ ids: [String], asListed listed: [String: Date?] = [:]) async -> PhotoDeletion {
        let requested = Set(ids)
        let present = Self.present(requested)
        // Nothing to ask about: do not show iOS's dialog for no photos.
        guard !present.isEmpty else { return PhotoDeletion(gone: requested, deletedCount: 0) }
        let deleting = Array(present)
        let outcome = OSAllocatedUnfairLock(initialState: Outcome())
        do {
            try await PHPhotoLibrary.shared().performChanges {
                // Fetched here, as they are now: what is counted is what this
                // change deletes, even if a photo went meanwhile, and a photo
                // made a favourite meanwhile is left alone.
                var deletable: [PHAsset] = []
                var favorites = Set<String>()
                var changed = Set<String>()
                Self.assets(deleting).enumerateObjects { asset, _, _ in
                    let id = asset.localIdentifier
                    if asset.isKeptByPerson {
                        favorites.insert(id)
                    } else if let then = listed[id], asset.modificationDate != then {
                        // `then` is the date as listed, nil included.
                        changed.insert(id)
                    } else {
                        deletable.append(asset)
                    }
                }
                let now = Outcome(deleted: deletable.count, favorites: favorites, changed: changed)
                outcome.withLock { $0 = now }
                if !deletable.isEmpty {
                    PHAssetChangeRequest.deleteAssets(deletable as NSArray)
                }
            }
            let done = outcome.withLock { $0 }
            return PhotoDeletion(
                gone: requested.subtracting(done.favorites).subtracting(done.changed),
                favorites: done.favorites,
                changed: done.changed,
                deletedCount: done.deleted
            )
        } catch {
            let found = outcome.withLock { $0 }
            return PhotoDeletion(
                gone: requested.subtracting(Self.present(requested)),
                favorites: found.favorites,
                changed: found.changed,
                deletedCount: 0
            )
        }
    }

    /// What a deletion's change block found.
    private struct Outcome: Sendable {
        var deleted = 0
        var favorites = Set<String>()
        var changed = Set<String>()
    }

    /// Those of `ids` still in the library, as far as this app may see it.
    private static func present(_ ids: Set<String>) -> Set<String> {
        var present = Set<String>()
        assets(Array(ids)).enumerateObjects { asset, _, _ in
            present.insert(asset.localIdentifier)
        }
        return present
    }

    /// What deleting each photo frees on this device: the bytes of its
    /// resources stored here (the photo, an edit of it, a Live Photo's
    /// video), counted by reading them, as Apple advises; PhotoKit has no
    /// size to ask for before iOS 27. A resource kept only in iCloud, with
    /// "Tối ưu hoá dung lượng iPhone" on, counts nothing: deleting the photo
    /// frees only the smaller copy the phone keeps, whose size PhotoKit does
    /// not give. So a total never promises more than comes back.
    ///
    /// Reads every byte of these photos: ask for the ones the screens show
    /// (`LibraryFindings.sizedIDs`), not the whole library. Photos not in
    /// the library are left out. Once the task is cancelled, what is left
    /// counts nothing.
    public static func localBytes(of ids: [String]) async -> [String: Int64] {
        var found: [PHAsset] = []
        assets(ids).enumerateObjects { asset, _, _ in
            found.append(asset)
        }
        var sizes: [String: Int64] = [:]
        for asset in found {
            var total: Int64 = 0
            for resource in PHAssetResource.assetResources(for: asset) {
                if case let .read(bytes) = await read(resource, checkingOnly: false) {
                    total += bytes
                }
            }
            sizes[asset.localIdentifier] = total
        }
        return sizes
    }

    /// How `localBytes(ofVideos:known:)` sizes videos and names their
    /// resources, kept with the sizes on the device (`VideoSizeStore`):
    /// change it along with them, and the videos are read again.
    public static let videoSizing = "bytes read on the device, network off; resources named by type and original file name"

    /// What deleting each video frees on this device, as `localBytes(of:)`
    /// counts a photo's: the bytes of its resources stored here (the video,
    /// an edit of it, the edit's data), a resource kept only in iCloud
    /// counting nothing.
    ///
    /// Reading a long video takes seconds, so a resource `known` has the
    /// size of is not read again: it is only checked to be here still, from
    /// its first chunk, since iOS takes a video's original off the phone,
    /// or brings it back, without changing the video. The others are read,
    /// every byte.
    ///
    /// - Parameter known: what earlier calls found, by video id. What it
    ///   holds of a video changed since, trimmed say, is not used: an edit
    ///   can leave a new file under the old name.
    /// - Returns: by video id, what it frees here now, and its resources'
    ///   sizes, those read now added, for the next call. Videos not in the
    ///   library are left out, and so is any not done when the task is
    ///   cancelled.
    public static func localBytes(ofVideos ids: [String], known: [String: SizedVideo]) async -> [String: VideoSize] {
        var found: [PHAsset] = []
        assets(ids).enumerateObjects { asset, _, _ in
            found.append(asset)
        }
        var sizes: [String: VideoSize] = [:]
        for asset in found {
            let id = asset.localIdentifier
            let before = known[id].flatMap { $0.modified == asset.modificationDate ? $0.resources : nil } ?? [:]
            var resources: [String: Int64] = [:]
            var here: [String] = []
            var isComplete = true
            var isStopped = false
            for resource in PHAssetResource.assetResources(for: asset) {
                let name = "\(resource.type.rawValue) \(resource.originalFilename)"
                let size = before[name]
                switch await read(resource, checkingOnly: size != nil) {
                case let .read(bytes):
                    resources[name] = bytes
                    here.append(name)
                case .here:
                    resources[name] = size
                    here.append(name)
                case .elsewhere:
                    // Its size is still what was read, if it was: it comes
                    // back as it went, the video unchanged.
                    resources[name] = size
                    isComplete = isComplete && size != nil
                case .stopped:
                    isStopped = true
                }
                if isStopped { break }
            }
            guard !isStopped else { break }
            let sized = SizedVideo(modified: asset.modificationDate, resources: resources, isComplete: isComplete)
            sizes[id] = VideoSize(bytes: sized.bytes(of: here), sized: sized)
        }
        return sizes
    }

    /// What reading a resource found.
    private enum ResourceRead {
        /// On the device, read: its size.
        case read(Int64)
        /// On the device, only checked.
        case here
        /// Not on the device, kept only in iCloud, or not readable.
        case elsewhere
        /// Not done: the task was cancelled.
        case stopped
    }

    /// Reads a resource on the device, never downloading it: every byte, to
    /// count them, or, `checkingOnly`, its first chunk, to know it is here.
    /// Stops once the task is cancelled.
    private static func read(_ resource: PHAssetResource, checkingOnly: Bool) async -> ResourceRead {
        let options = PHAssetResourceRequestOptions()
        // Without it, a resource kept only in iCloud fails at once rather
        // than download.
        options.isNetworkAccessAllowed = false
        // In one lock: the handlers run on a queue of Photos', and the task
        // can be cancelled at any point, even before the request has an id.
        let state = OSAllocatedUnfairLock(initialState: ResourceRequest())
        /// Answers once; `stopping`, stops the request too, now or as soon
        /// as it has an id.
        @Sendable func answer(_ read: ResourceRead, stopping: Bool) {
            let (continuation, id): (CheckedContinuation<ResourceRead, Never>?, PHAssetResourceDataRequestID?) = state.withLock { state in
                guard !state.isAnswered else { return (nil, nil) }
                state.isAnswered = true
                state.isStopping = stopping
                defer { state.continuation = nil }
                return (state.continuation, stopping ? state.id : nil)
            }
            continuation?.resume(returning: read)
            if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let isAnswered = state.withLock { state in
                    state.continuation = continuation
                    return state.isAnswered
                }
                // Cancelled already: nothing to ask Photos.
                guard !isAnswered else {
                    state.withLock { $0.continuation = nil }
                    continuation.resume(returning: .stopped)
                    return
                }
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                    if checkingOnly {
                        answer(.here, stopping: true)
                    } else {
                        state.withLock { $0.bytes += Int64(data.count) }
                    }
                } completionHandler: { error in
                    // After a stop, whatever comes was answered already.
                    let bytes = state.withLock { $0.bytes }
                    answer(error != nil ? .elsewhere : checkingOnly ? .here : .read(bytes), stopping: false)
                }
                let isStopping = state.withLock { state in
                    state.id = id
                    return state.isStopping
                }
                if isStopping { PHAssetResourceManager.default().cancelDataRequest(id) }
            }
        } onCancel: {
            answer(.stopped, stopping: true)
        }
    }

    /// A data request to Photos, as its handlers and the task see it.
    private struct ResourceRequest: Sendable {
        var continuation: CheckedContinuation<ResourceRead, Never>?
        /// Once `requestData` has returned.
        var id: PHAssetResourceDataRequestID?
        var bytes: Int64 = 0
        var isAnswered = false
        /// Answered before Photos was done: the request is to stop.
        var isStopping = false
    }
}

/// What `PhotoLibrary.localBytes(ofVideos:known:)` found of a video.
public struct VideoSize: Hashable, Sendable {
    /// What deleting it frees on this device now.
    public let bytes: Int64
    /// Its resources' sizes as read, for the next call, and for the scan to
    /// keep (`VideoSizeStore`).
    public let sized: SizedVideo

    public init(bytes: Int64, sized: SizedVideo) {
        self.bytes = bytes
        self.sized = sized
    }
}

extension PHAsset {
    /// A favourite, or a burst shot the person picked in Photos: never
    /// offered for deletion, never deleted.
    var isKeptByPerson: Bool {
        isFavorite || burstSelectionTypes.contains(.userPick)
    }
}
#endif
