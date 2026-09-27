import Foundation

/// A photo's measurement, and when the photo last changed as it was
/// measured: what `PhotoLibraryScan` keeps, so a photo is measured again
/// only once it changes.
public struct MeasuredPhoto: Sendable {
    /// `LibraryPhoto.modified` of the photo as it was measured.
    public var modified: Date?
    public var measurement: PhotoMeasurement

    public init(modified: Date?, measurement: PhotoMeasurement) {
        self.modified = modified
        self.measurement = measurement
    }
}

/// Measurements kept in a file between launches, so a library of tens of
/// thousands of photos is not measured again each time the app opens:
/// about 3 KB a photo, most of it the print.
///
/// The file says how its photos were measured, `method`: a file of another
/// method reads as empty, and its photos are measured again, as are those
/// of a file that cannot be read.
public struct MeasurementStore: Hashable, Sendable {
    public let url: URL
    /// How the photos were measured, as `PhotoMeasurer.method` says: photos
    /// measured another way, with prints of another revision say, cannot be
    /// compared with this way's.
    public let method: String

    public init(url: URL, method: String) {
        self.url = url
        self.method = method
    }

    /// What the file holds, by photo id: empty when there is no file, when
    /// it cannot be read, or when it is of another method. A photo whose
    /// print cannot be read is left out, to be measured again.
    public func load() -> [String: MeasuredPhoto] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let archive = try? PropertyListDecoder().decode(Archive.self, from: data),
              archive.format == Archive.currentFormat, archive.method == method
        else { return [:] }
        return archive.photos.compactMapValues(\.measured)
    }

    /// Replaces the file with these measurements, making its folder if need
    /// be. The new file takes the old one's place whole: a read meanwhile
    /// gets the old one or the new, never part of each.
    public func save(_ photos: [String: MeasuredPhoto]) throws {
        let archive = Archive(format: Archive.currentFormat, method: method, photos: photos.mapValues(Entry.init))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(archive)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Deletes the file. Returns whether no file is left: it was deleted, or
    /// there was none.
    @discardableResult
    public func remove() -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return !FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
    }
}

/// The file.
private struct Archive: Codable {
    /// The file's layout: a file of another layout reads as empty.
    static let currentFormat = 1

    var format: Int
    var method: String
    var photos: [String: Entry]
}

/// A photo in the file.
private struct Entry: Codable {
    var modified: Date?
    var sharpness: Double
    /// The print's numbers, 32-bit floats, little-endian; none for a photo
    /// with no print.
    var print: Data?
    /// `PhotoContent.rawValue`; none for a photo not looked at.
    var content: Int?
    /// `PhotoMeasurement.aesthetics`; none for a photo not scored.
    var aesthetics: Float?

    init(_ photo: MeasuredPhoto) {
        modified = photo.modified
        sharpness = photo.measurement.sharpness
        print = photo.measurement.print.map { print in
            print.values.map(\.bitPattern.littleEndian).withUnsafeBytes { Data($0) }
        }
        content = photo.measurement.content?.rawValue
        aesthetics = photo.measurement.aesthetics
    }

    /// The photo, `nil` when its print is not one: not whole floats, or
    /// not a `FeaturePrint`.
    var measured: MeasuredPhoto? {
        var print: FeaturePrint?
        if let data = self.print {
            let size = MemoryLayout<UInt32>.size
            guard data.count % size == 0 else { return nil }
            let values = data.withUnsafeBytes { bytes in
                (0 ..< bytes.count / size).map { index in
                    Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * size, as: UInt32.self)))
                }
            }
            guard let read = FeaturePrint(values) else { return nil }
            print = read
        }
        return MeasuredPhoto(
            modified: modified,
            measurement: PhotoMeasurement(
                sharpness: sharpness, print: print, content: content.map { PhotoContent(rawValue: $0) }, aesthetics: aesthetics
            )
        )
    }
}
