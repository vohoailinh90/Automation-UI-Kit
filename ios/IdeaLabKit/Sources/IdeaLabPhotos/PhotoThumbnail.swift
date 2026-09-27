#if os(iOS)
import os
import Photos
import SwiftUI

/// A photo of the library, filling the frame it is given, as the cleaner's
/// screens ask of a `thumbnail`: a copy from the phone at the frame's size in
/// pixels. A photo with no such copy on the phone, kept only in iCloud,
/// shows a plain tile: it is not downloaded.
///
/// Hidden from VoiceOver: the screens say what each photo is, and when it
/// was taken, around it.
public struct PhotoThumbnail: View {
    private let id: String
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: Loaded?

    private struct Loaded {
        let request: Request
        let image: UIImage
    }

    /// What was asked for: the photo, at whole pixels.
    private struct Request: Hashable {
        let id: String
        let width: Int
        let height: Int
    }

    /// - Parameter id: the photo's `PHAsset.localIdentifier`, as
    ///   `CleanupItem.id`.
    public init(id: String) {
        self.id = id
    }

    public var body: some View {
        GeometryReader { proxy in
            let request = Request(
                id: id,
                width: Int((proxy.size.width * displayScale).rounded(.up)),
                height: Int((proxy.size.height * displayScale).rounded(.up))
            )
            ZStack {
                Rectangle().fill(.quaternary)
                // The last image of this photo, while one at a new size loads;
                // never another photo's.
                if let loaded, loaded.request.id == id {
                    Image(uiImage: loaded.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .task(id: request) {
                guard let image = await Self.image(for: request) else { return }
                loaded = Loaded(request: request, image: image)
            }
        }
        .accessibilityHidden(true)
    }

    /// The photo at the request's size, from the phone; `nil` when it has no
    /// copy, or the task was cancelled. Not on the main actor, as a view's
    /// methods are: Photos calls back on a queue of its own.
    private nonisolated static func image(for request: Request) async -> UIImage? {
        guard request.width > 0, request.height > 0,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [request.id], options: nil).firstObject
        else { return nil }
        let options = PHImageRequestOptions()
        // One answer, the best the phone has: a continuation resumes once.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let requestID = OSAllocatedUnfairLock<PHImageRequestID?>(initialState: nil)
        let answered = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let id = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: request.width, height: request.height),
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    // Photos answers once, even when cancelled; the lock
                    // makes sure the continuation is resumed once.
                    let isFirst = answered.withLock { answered in
                        defer { answered = true }
                        return !answered
                    }
                    if isFirst { continuation.resume(returning: image) }
                }
                requestID.withLock { $0 = id }
            }
        } onCancel: {
            if let id = requestID.withLock({ $0 }) {
                PHImageManager.default().cancelImageRequest(id)
            }
        }
    }
}
#endif
