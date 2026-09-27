import IdeaLabCore
import IdeaLabPhotos
import IdeaLabUI
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// The cleaner on this phone's own photos, through IdeaLabPhotos: PhotoKit
/// lists and deletes them, Vision and `Sharpness` measure them on the device.
/// The other cleaner screens show samples; this one does what an app does.
@Observable
@MainActor
final class DemoLibraryStore {
    let scan = PhotoLibraryScan()
    private(set) var access = PhotoLibrary.access
    private(set) var storage = StorageStatus.device()
    /// A fresh free tier, as on a new install.
    var allowance = FreeAllowance()
    var session = CleanupSession(items: [])
    var similar = SimilarReview(groups: [])
    var page: LibraryPage?
    private(set) var isAddingSamples = false

    func requestAccess() async {
        access = await PhotoLibrary.requestAccess()
        await refresh()
    }

    /// Reads access and storage again, and sorts the library if it may.
    func refresh() async {
        access = PhotoLibrary.access
        storage = StorageStatus.device()
        await scan.run()
    }

    /// Opens a category from the home screen, on what the scan found.
    func open(_ category: CleanupCategory) {
        guard let findings = scan.findings else { return }
        switch category {
        case .screenshots:
            session = CleanupSession(items: findings.screenshots)
            page = .screenshots
        case .similar:
            similar = SimilarReview(groups: findings.similarGroups)
            page = .similar
        case .blurry, .documents, .qrCodes:
            // Not sorted on the device yet: the home screen does not list them.
            break
        }
    }

    /// Deletes through PhotoKit, iOS asking first, and counts what went
    /// against the free tier before the screen reads it again.
    func delete(_ items: [CleanupItem]) async -> Set<CleanupItem.ID> {
        let deletion = await PhotoLibrary.delete(items.map(\.id))
        allowance.use(deletion.deletedCount)
        return deletion.gone
    }

    /// Adds `DemoPhotoSeed`'s sample photos, then sorts the library again.
    func addSamples() async {
        guard !isAddingSamples else { return }
        isAddingSamples = true
        defer { isAddingSamples = false }
        do {
            try await DemoPhotoSeed.add()
            UserDefaults.standard.set(true, forKey: DemoPhotoSeed.addedKey)
        } catch {
            // Refused, or no access to add: the library stays as it is.
        }
        await refresh()
    }
}

/// Where the library demo goes from its home screen.
enum LibraryPage: Hashable {
    case screenshots
    case similar
}

struct CleanerLibraryDemo: View {
    /// `-screen cleaner-library-similar`: straight to the look-alikes once
    /// the library is sorted.
    var opensSimilar = false
    @State private var store = DemoLibraryStore()
    @State private var reviewing = false
    /// Whether `opensSimilar` has opened them: once, not each time the home
    /// screen is back.
    @State private var openedSimilar = false
    /// Whether the app went to the background since the library was sorted.
    @State private var wasAway = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.access {
            case .notAsked:
                primer
            case .denied, .restricted:
                refused
            case .limited, .full:
                home
            }
        }
        .navigationDestination(item: $store.page) { page in
            switch page {
            case .screenshots:
                CleanupSwipeScreen(session: $store.session) { item in
                    PhotoThumbnail(id: item.id)
                } onReview: {
                    reviewing = true
                }
                .navigationTitle("Ảnh chụp màn hình")
                .navigationDestination(isPresented: $reviewing) {
                    CleanupReviewScreen(session: $store.session, allowance: store.allowance) { item in
                        PhotoThumbnail(id: item.id)
                    } onDelete: { items in
                        await store.delete(items)
                    } onUnlock: {}
                    .navigationTitle("Xem lại")
                }
            case .similar:
                SimilarPhotosScreen(review: $store.similar, allowance: store.allowance) { photo in
                    PhotoThumbnail(id: photo.id)
                } onDelete: { items in
                    await store.delete(items)
                } onUnlock: {}
                .navigationTitle("Ảnh gần giống")
                .onAppear {
                    if opensSimilar { DemoLaunch.markReady() }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from elsewhere, photos may have been taken or deleted
            // meanwhile. Not on launch: the home screen sorts them then.
            if phase == .background {
                wasAway = true
            } else if phase == .active, wasAway {
                wasAway = false
                Task { await store.refresh() }
            }
        }
    }

    private var primer: some View {
        PermissionPrimerScreen(
            systemImage: "photo.on.rectangle.angled",
            title: "Cho phép xem ảnh để dọn",
            message: "Ảnh được xem và phân loại ngay trên máy.",
            reasons: DemoContent.photoReasons,
            allowTitle: "Cho phép xem ảnh",
            onAllow: { Task { await store.requestAccess() } },
            onLater: {}
        )
        .onAppear(perform: DemoLaunch.markReady)
    }

    private var refused: some View {
        VStack(spacing: LabSpacing.md) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text(verbatim: store.access == .restricted
                ? "Máy này không cho ứng dụng xem ảnh, và bạn không đổi được điều đó."
                : "Bạn chưa cho ứng dụng xem ảnh. Có thể đổi trong Cài đặt.")
                .multilineTextAlignment(.center)
            if store.access == .denied {
                Button("Mở Cài đặt") { PhotoLibrary.openSettings() }
                    .buttonStyle(.labFilled)
            }
        }
        .padding(LabSpacing.lg)
        .onAppear(perform: DemoLaunch.markReady)
    }

    private var home: some View {
        CleanerHomeScreen(
            storage: store.storage ?? StorageStatus(capacity: 0, available: 0),
            summaries: store.scan.findings?.summary ?? [],
            scanProgress: store.scan.progress,
            allowance: store.allowance,
            onOpen: { store.open($0) },
            onUpgrade: {}
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let unmeasured = store.scan.findings?.unmeasuredCount, unmeasured > 0, store.scan.progress == nil {
                Text(verbatim: "\(unmeasured) ảnh chụp liền nhau chưa được xét: ảnh chỉ có trên iCloud không được tải về.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(LabSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Thêm ảnh mẫu", systemImage: "photo.badge.plus") {
                    Task { await store.addSamples() }
                }
                .disabled(store.isAddingSamples)
            }
        }
        // Again each time the home screen is back in view: after deleting,
        // its numbers follow.
        .task {
            if DemoLaunch.addsSamplePhotos, !UserDefaults.standard.bool(forKey: DemoPhotoSeed.addedKey) {
                await store.addSamples()
            } else {
                await store.refresh()
            }
            guard !Task.isCancelled else { return }
            if !opensSimilar {
                DemoLaunch.markReady()
            } else if !openedSimilar {
                openedSimilar = true
                store.open(.similar)
            }
        }
    }
}

/// Sample photos for a simulator's library, which starts nearly empty: five
/// moments shot three or four times, a second or two apart, one shot of each
/// shaken; two photos alone in their moment; and two screenshots, marked the
/// way iOS marks its own (EXIF "Screenshot"). Drawn by the demo, so nothing
/// is downloaded.
@MainActor
enum DemoPhotoSeed {
    /// Set once the samples are in, so `-seedPhotos` adds them once.
    static let addedKey = "demo.samplePhotosAdded"

    static func add(now: Date = .now) async throws {
        var photos: [SamplePhoto] = []
        let hour: TimeInterval = 3_600
        for moment in 0 ..< 5 {
            // Hours apart: no two moments share a window.
            let taken = now.addingTimeInterval(-hour * Double(5 * (moment + 1)))
            for shot in 0 ..< 3 + moment % 2 {
                let view = Landscape(seed: UInt64(moment * 7 + 1))
                    .scaleEffect(1.1)
                    .offset(x: CGFloat(shot % 3 - 1) * 8, y: CGFloat(shot % 2) * 5)
                    .blur(radius: shot == 1 ? 5 : 0, opaque: true)
                    .clipped()
                if let data = jpeg(view, width: 1_600, height: 1_200) {
                    photos.append(SamplePhoto(data: data, date: taken.addingTimeInterval(Double(shot) * 2)))
                }
            }
        }
        for lone in 0 ..< 2 {
            if let data = jpeg(Landscape(seed: UInt64(40 + lone)), width: 1_600, height: 1_200) {
                photos.append(SamplePhoto(data: data, date: now.addingTimeInterval(-hour * Double(40 + 30 * lone))))
            }
        }
        for screenshot in 0 ..< 2 {
            if let data = jpeg(ChatScreenshot(seed: UInt64(screenshot + 3)), width: 1_206, height: 2_622, comment: "Screenshot") {
                photos.append(SamplePhoto(data: data, date: now.addingTimeInterval(-hour * Double(2 + screenshot))))
            }
        }
        let samples = photos
        try await PHPhotoLibrary.shared().performChanges {
            for sample in samples {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: sample.data, options: nil)
                request.creationDate = sample.date
            }
        }
    }

    /// The view drawn at `width` × `height` pixels, as a JPEG, with a user
    /// comment in its EXIF if given.
    private static func jpeg(_ view: some View, width: CGFloat, height: CGFloat, comment: String? = nil) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let comment {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: comment]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// A sample photo, and when it was "taken".
private struct SamplePhoto: Sendable {
    let data: Data
    let date: Date
}
