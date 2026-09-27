import Foundation

/// A photo of the library as PhotoKit lists it: what sorting it takes, before
/// anything is measured.
public struct LibraryPhoto: Identifiable, Hashable, Sendable {
    /// `PHAsset.localIdentifier`.
    public var id: String
    /// When it was taken: `PHAsset.creationDate`.
    public var date: Date
    /// A favourite, or anything else the person marked to keep, such as a
    /// burst shot picked in Photos: never offered for deletion.
    public var isFavorite: Bool
    /// Taken with the phone's screenshot buttons: `PHAsset.mediaSubtypes`
    /// has `.photoScreenshot`.
    public var isScreenshot: Bool
    /// When the photo or its details last changed: `PHAsset.modificationDate`.
    /// What was measured of it before then, or decided about it, is out of
    /// date.
    public var modified: Date?

    public init(id: String, date: Date, isFavorite: Bool = false, isScreenshot: Bool = false, modified: Date? = nil) {
        self.id = id
        self.date = date
        self.isFavorite = isFavorite
        self.isScreenshot = isScreenshot
        self.modified = modified
    }
}

/// What the device recognised in a photo (Vision, in a real app): what it
/// was taken to keep, for the cleaner's categories.
public struct PhotoContent: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// A QR code: a ticket, a payment, a Wi-Fi password, kept to be read
    /// once.
    public static let qrCode = PhotoContent(rawValue: 1 << 0)
    /// A document: a receipt, a printed page, a note, a whiteboard.
    public static let document = PhotoContent(rawValue: 1 << 1)
}

/// What the device measured of a photo, for `LibraryFindings`.
public struct PhotoMeasurement: Sendable {
    /// `Sharpness.laplacianVariance` of the photo: higher is sharper, NaN
    /// when it could not be measured.
    public var sharpness: Double
    /// Its feature print, `nil` when Vision could not make one, or when it
    /// was not asked for. A photo with no print is in no group.
    public var print: FeaturePrint?
    /// What was recognised in it, `nil` when it was not looked at: a photo
    /// with none is in neither `qrCodes` nor `documents`.
    public var content: PhotoContent?

    public init(sharpness: Double, print: FeaturePrint?, content: PhotoContent? = nil) {
        self.sharpness = sharpness
        self.print = print
        self.content = content
    }
}

/// What the cleaner offers from the photo library: its screenshots; the
/// photos shot several times over, each group with its sharpest shot
/// suggested to keep; and the photos of a QR code or of a document. The
/// screens open on it: `CleanupSession(items: screenshots)`, and the same
/// for `qrCodes` and `documents`, `SimilarReview(groups: similarGroups)`,
/// and `summary` for the home screen.
///
/// A photo is offered once, in one category: a screenshot as such, then a
/// photo of a group in its group, then a QR code, then a document. A
/// repeated id is one photo, as everywhere in the kit: its first record, a
/// favourite if any of its records is.
public struct LibraryFindings: Hashable, Sendable {
    /// The screenshots, newest first. Favourites are left out: they are never
    /// offered for deletion.
    public let screenshots: [CleanupItem]
    /// Photos of one moment that look alike, newest group first: the
    /// `candidates` that have a print, grouped by `SimilarGrouping.groups`,
    /// alike when `FeaturePrint.alike`.
    public let similarGroups: [SimilarGroup]
    /// Photos of a QR code, newest first: `PhotoContent.qrCode`, in no group,
    /// favourites left out.
    public let qrCodes: [CleanupItem]
    /// Photos of a document, newest first: `PhotoContent.document`, not a QR
    /// code, in no group, favourites left out.
    public let documents: [CleanupItem]
    /// How many `candidates` have no print: not measured (kept only in
    /// iCloud, say) or not readable by Vision. They are in no group, and the
    /// app can say that they were not looked at.
    public let unmeasuredCount: Int
    /// How many photos, not screenshots nor favourites, have no content: not
    /// looked at, as when kept only in iCloud. They are in neither `qrCodes`
    /// nor `documents`.
    public let unclassifiedCount: Int
    /// When each photo offered here last changed, as listed: every photo of
    /// every category, `nil` for one listed with no date, which is kept too,
    /// so a date it gets later tells as well. A
    /// photo changed since (edited, say, while a review of it was open) is
    /// not the photo the findings judged; `PhotoLibrary.delete` takes these
    /// to leave such a photo alone.
    public let modificationDates: [LibraryPhoto.ID: Date?]

    /// - Parameters:
    ///   - measurements: by photo id: a print for `candidates`, content for
    ///     every photo that is not a screenshot.
    ///   - bytes: what deleting each photo frees on this device, as
    ///     `CleanupItem.bytes`; a photo not in it counts 0. Only the photos of
    ///     `sizedIDs` need one.
    ///   - window: as in `SimilarGrouping.groups`.
    ///   - threshold: as in `FeaturePrint.alike`.
    public init(
        photos: [LibraryPhoto],
        measurements: [LibraryPhoto.ID: PhotoMeasurement],
        bytes: [LibraryPhoto.ID: Int64] = [:],
        within window: TimeInterval = 120,
        threshold: Float = FeaturePrint.sameMoment
    ) {
        let favorites = Set(photos.lazy.filter(\.isFavorite).map(\.id))
        var seen = Set<LibraryPhoto.ID>()
        let items = photos.filter { seen.insert($0.id).inserted }.map { photo in
            CleanupItem(
                id: photo.id,
                category: photo.isScreenshot ? .screenshots : .similar,
                bytes: bytes[photo.id] ?? 0,
                // As `SimilarPhoto` stores it: a date that is not a finite
                // number would not sort.
                date: photo.date.timeIntervalSinceReferenceDate.isFinite ? photo.date : .distantPast,
                isFavorite: favorites.contains(photo.id)
            )
        }
        screenshots = items.filter { $0.category == .screenshots && !$0.isFavorite }
            .sorted { a, b in a.date != b.date ? a.date > b.date : a.id < b.id }
        let candidates = Set(Self.candidates(in: photos, within: window))
        let photographs = items.filter { candidates.contains($0.id) }
        var prints: [LibraryPhoto.ID: FeaturePrint] = [:]
        var measured: [SimilarPhoto] = []
        for item in photographs {
            guard let measurement = measurements[item.id], let print = measurement.print else { continue }
            prints[item.id] = print
            measured.append(SimilarPhoto(item, sharpness: measurement.sharpness))
        }
        unmeasuredCount = photographs.count - measured.count
        let similarGroups = SimilarGrouping.groups(measured, within: window) { a, b in
            FeaturePrint.alike(prints[a.id], prints[b.id], within: threshold)
        }
        self.similarGroups = similarGroups

        // What was taken to keep something, in no group: each in one
        // category, a QR code before a document.
        let grouped = Set(similarGroups.flatMap { $0.photos.map(\.id) })
        var qrCodes: [CleanupItem] = []
        var documents: [CleanupItem] = []
        var unclassified = 0
        for item in items where item.category != .screenshots && !item.isFavorite {
            guard let content = measurements[item.id]?.content else {
                unclassified += 1
                continue
            }
            guard !grouped.contains(item.id) else { continue }
            var offered = item
            if content.contains(.qrCode) {
                offered.category = .qrCodes
                qrCodes.append(offered)
            } else if content.contains(.document) {
                offered.category = .documents
                documents.append(offered)
            }
        }
        let newestFirst: (CleanupItem, CleanupItem) -> Bool = { a, b in a.date != b.date ? a.date > b.date : a.id < b.id }
        self.qrCodes = qrCodes.sorted(by: newestFirst)
        self.documents = documents.sorted(by: newestFirst)
        unclassifiedCount = unclassified

        // Of each photo's first record, as everything else here.
        let offered = Set(screenshots.map(\.id)).union(grouped).union(qrCodes.map(\.id)).union(documents.map(\.id))
        var firstRecords = Set<LibraryPhoto.ID>()
        var dates: [LibraryPhoto.ID: Date?] = [:]
        for photo in photos where firstRecords.insert(photo.id).inserted && offered.contains(photo.id) {
            // A nil is kept as a value: `updateValue` never removes the key.
            dates.updateValue(photo.modified, forKey: photo.id)
        }
        modificationDates = dates
    }

    /// The photos a group could take, so the only ones worth measuring: those
    /// that are not screenshots, taken within `window` of another such
    /// photo. Oldest first, then by id.
    ///
    /// A group takes photos in the order they were taken, each within
    /// `window` of the one before, so every photo of a group has another
    /// that close. A photo alone in its moment is in no group, whatever it
    /// looks like, and needs neither Vision nor its print kept: in most
    /// libraries, that is most photos.
    public static func candidates(in photos: [LibraryPhoto], within window: TimeInterval = 120) -> [LibraryPhoto.ID] {
        // As `SimilarGrouping.groups` takes them.
        let window = window.isNaN ? 0 : max(window, 0)
        var seen = Set<LibraryPhoto.ID>()
        var shots: [LibraryPhoto] = photos.filter { seen.insert($0.id).inserted && !$0.isScreenshot }
        for index in shots.indices where !shots[index].date.timeIntervalSinceReferenceDate.isFinite {
            shots[index].date = .distantPast
        }
        shots.sort { a, b in a.date != b.date ? a.date < b.date : a.id < b.id }
        func gap(before index: Int) -> TimeInterval {
            shots[index].date.timeIntervalSince(shots[index - 1].date)
        }
        return shots.indices.filter { index in
            (index > 0 && gap(before: index) <= window) || (index + 1 < shots.count && gap(before: index + 1) <= window)
        }.map { shots[$0].id }
    }

    /// For the home screen: the screenshots, the photos the similar groups
    /// suggest deleting, and the photos of QR codes and documents — what
    /// cleaning frees if nothing is changed.
    public var summary: [CategorySummary] {
        CleanupMath.summary(of: screenshots + similarGroups.flatMap { group in
            let keep = group.suggestedKeep
            return group.photos.lazy.filter { !keep.contains($0.id) }.map(\.item)
        } + qrCodes + documents)
    }

    /// The photos whose size the screens show: the screenshots, every photo
    /// of a group, then the QR codes and the documents. Measure theirs for
    /// `bytes`, not the whole library's.
    public var sizedIDs: [LibraryPhoto.ID] {
        screenshots.map(\.id) + similarGroups.flatMap { $0.photos.map(\.id) } + qrCodes.map(\.id) + documents.map(\.id)
    }
}
