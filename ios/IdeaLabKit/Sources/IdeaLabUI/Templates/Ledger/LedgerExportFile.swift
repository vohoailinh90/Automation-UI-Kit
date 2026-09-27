#if os(iOS)
import Foundation
import IdeaLabCore

/// Writes an export of the book to a file, to hand to the share sheet
/// (`LabShareSheet`): what an app's `LedgerReportScreen` `onExport` does.
///
///     LedgerReportScreen(entries: book.entries) { format, interval in
///         do {
///             exported = try LedgerExportFile.write(format, entries: book.entries, in: interval, calendar: calendar)
///         } catch {
///             // Say the export failed.
///         }
///     }
public enum LedgerExportFile {
    /// Writes the report of `interval` as a PDF (`LedgerReportPDF`) or an
    /// Excel workbook (`LedgerSpreadsheet`) into the app's temporary folder,
    /// which iOS empties when it needs the space, and returns the file's
    /// URL. The file is named for the period without accents, such as
    /// "So-thu-chi-thang-9-2026.pdf" (`LedgerExport.fileName`), which every
    /// app and mail server takes; writing the same period again replaces it.
    ///
    /// - Parameters:
    ///   - title: the report's first line; by default
    ///     `LedgerExport.title`, such as "Sổ thu chi tháng 9/2026".
    ///   - made: when the export is made, said under the title.
    @MainActor
    public static func write(
        _ format: LedgerReportScreen.ExportFormat,
        entries: [LedgerEntry],
        in interval: DateInterval,
        calendar: Calendar,
        title: String? = nil,
        made: Date = .now
    ) throws -> URL {
        let title = title ?? LedgerExport.title(for: interval, calendar: calendar)
        let data: Data
        let fileExtension: String
        switch format {
        case .pdf:
            data = try LedgerReportPDF.data(entries: entries, in: interval, calendar: calendar, title: title, made: made)
            fileExtension = "pdf"
        case .spreadsheet:
            data = LedgerSpreadsheet.xlsx(entries: entries, in: interval, calendar: calendar, title: title, made: made)
            fileExtension = "xlsx"
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "LedgerExport", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LedgerExport.fileName(for: interval, calendar: calendar) + "." + fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}
#endif
