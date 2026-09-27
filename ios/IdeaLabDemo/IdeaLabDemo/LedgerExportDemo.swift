import IdeaLabCore
import IdeaLabUI
import PDFKit
import QuickLook
import SwiftUI

/// The report screen with its export wired up: the PDF and Excel buttons
/// write the period's file (`LedgerExportFile`) and open the share sheet.
struct LedgerReportDemo: View {
    let store: DemoLedgerStore
    @State private var exported: ExportedFile?
    @State private var toast: LabToastMessage?

    var body: some View {
        LedgerReportScreen(entries: store.entries, now: store.now, calendar: store.calendar) { format, interval in
            do {
                let url = try LedgerExportFile.write(format, entries: store.entries, in: interval, calendar: store.calendar, made: store.now)
                exported = ExportedFile(url: url)
            } catch {
                toast = LabToastMessage(
                    text: "Không xuất được sổ: \(error.localizedDescription)",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
        }
        .sheet(item: $exported) { file in
            LabShareSheet(urls: [file.url]) { exported = nil }
                .presentationDetents([.medium, .large])
        }
        .labToast($toast)
    }
}

/// A written export, for `.sheet(item:)`: each export is a sheet of its own,
/// even for the same file.
private struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The sample book's month, the report's first period.
private extension DemoLedgerStore {
    var thisMonth: DateInterval {
        calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
    }
}

/// This month's PDF export, as `LedgerReportPDF` draws it, in PDFKit's
/// viewer: the first page, with the title and totals, and the top of the
/// next, where the list goes on.
struct LedgerPDFDemo: View {
    let store: DemoLedgerStore
    @State private var file: Result<URL, any Error>?

    var body: some View {
        ExportedFileView(file: file) { url in
            if let document = PDFDocument(url: url) {
                PDFPages(document: document)
                    .fileCaption(url, detail: "\(document.pageCount) trang")
            } else {
                ContentUnavailableView("PDFKit không mở được file", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard file == nil else { return }
            file = Result { try LedgerExportFile.write(.pdf, entries: store.entries, in: store.thisMonth, calendar: store.calendar, made: store.now) }
            DemoLaunch.markReady()
        }
    }
}

/// This month's Excel export, as `LedgerSpreadsheet` writes it, opened by
/// Quick Look, the viewer of Files and Mail: whether Apple's own reader
/// takes the file, with its dates, times, amounts and totals.
struct LedgerSpreadsheetDemo: View {
    let store: DemoLedgerStore
    @State private var file: Result<URL, any Error>?

    var body: some View {
        ExportedFileView(file: file) { url in
            QuickLookFile(url: url)
                .fileCaption(url, detail: nil)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard file == nil else { return }
            file = Result { try LedgerExportFile.write(.spreadsheet, entries: store.entries, in: store.thisMonth, calendar: store.calendar, made: store.now) }
            // Quick Look says nothing when it has drawn the file: give it
            // time, and the screenshots wait for the screen to stand still.
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { DemoLaunch.markReady() }
        }
    }
}

/// An export being written, written, or failed.
private struct ExportedFileView<Content: View>: View {
    let file: Result<URL, any Error>?
    @ViewBuilder let content: (URL) -> Content

    var body: some View {
        switch file {
        case let .success(url):
            content(url)
        case let .failure(error):
            ContentUnavailableView("Không xuất được sổ", systemImage: "exclamationmark.triangle", description: Text(verbatim: error.localizedDescription))
        case nil:
            ProgressView()
        }
    }
}

private extension View {
    /// The file's name and size under the preview: "So-thu-chi-thang-9-2026.pdf · 3 trang · 41,2 KB".
    /// Below the viewer, not over it: Quick Look lays its sheet out in the
    /// whole of its frame, and a bar inset over it hid the last rows.
    func fileCaption(_ url: URL, detail: String?) -> some View {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteSize.string(Int64($0)) }
        let caption = ([url.lastPathComponent, detail, size] as [String?]).compactMap { $0 }.joined(separator: " · ")
        return VStack(spacing: 0) {
            self
            Text(verbatim: caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(LabSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

/// PDFKit's viewer: pages one under the other, as wide as the screen.
private struct PDFPages: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

/// Quick Look's viewer for one file, in place rather than presented.
private struct QuickLookFile: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
