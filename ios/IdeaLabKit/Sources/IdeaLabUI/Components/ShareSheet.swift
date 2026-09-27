#if os(iOS)
import SwiftUI
import UIKit

/// The system share sheet for files: Save to Files, AirDrop, Mail, Zalo,
/// Print. Show it with `.sheet(item:)` once the file is written, as the
/// demo's report does with `LedgerExportFile`:
///
///     .sheet(item: $exported) { file in
///         LabShareSheet(urls: [file.url]) { exported = nil }
///             .presentationDetents([.medium, .large])
///     }
///
/// `onComplete` runs when the person has shared the files, or closed the
/// sheet without sharing: clear the item there, so the sheet goes with it.
public struct LabShareSheet: UIViewControllerRepresentable {
    private let urls: [URL]
    private let onComplete: @MainActor () -> Void

    public init(urls: [URL], onComplete: @escaping @MainActor () -> Void = {}) {
        self.urls = urls
        self.onComplete = onComplete
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        let onComplete = onComplete
        controller.completionWithItemsHandler = { _, _, _, _ in
            // UIKit calls this on the main thread.
            MainActor.assumeIsolated { onComplete() }
        }
        return controller
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
