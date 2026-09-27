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

/// What `PhotoLibrary.delete` did.
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
    /// How many photos this deletion removed, for `FreeAllowance.use`.
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

/// The person's photo library, for the cleaner: access, the photos to sort,
/// what deleting them frees, and deleting them. Photos are read on the
/// device only: nothing is downloaded from iCloud, and nothing leaves the
/// phone.
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

    /// Deletes photos, never a favourite, nor a photo changed since it was
    /// listed. iOS asks the person first, then keeps the photos in "Đã xoá
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
    /// the library are left out.
    public static func localBytes(of ids: [String]) async -> [String: Int64] {
        var found: [PHAsset] = []
        assets(ids).enumerateObjects { asset, _, _ in
            found.append(asset)
        }
        var sizes: [String: Int64] = [:]
        for asset in found {
            var total: Int64 = 0
            for resource in PHAssetResource.assetResources(for: asset) {
                total += await localBytes(of: resource)
            }
            sizes[asset.localIdentifier] = total
        }
        return sizes
    }

    /// The resource's size if it is on the device, else 0.
    private static func localBytes(of resource: PHAssetResource) async -> Int64 {
        let options = PHAssetResourceRequestOptions()
        // Without it, a resource kept only in iCloud fails at once rather
        // than download.
        options.isNetworkAccessAllowed = false
        let count = OSAllocatedUnfairLock<Int64>(initialState: 0)
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                count.withLock { $0 += Int64(data.count) }
            } completionHandler: { error in
                continuation.resume(returning: error == nil ? count.withLock { $0 } : 0)
            }
        }
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
