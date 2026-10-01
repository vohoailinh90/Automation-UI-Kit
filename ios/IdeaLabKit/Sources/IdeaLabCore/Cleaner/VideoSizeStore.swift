import Foundation

/// What a video's resources take on the device, as read, and when the video
/// last changed as they were read: what `PhotoLibraryScan` keeps, so a video
/// is read again only once it changes. Before iOS 27, PhotoKit gives no size
/// to ask for: a resource is sized by reading it, every byte, which for a
/// long video takes seconds.
public struct SizedVideo: Hashable, Sendable {
    /// `LibraryVideo.modified` of the video as it was read.
    public var modified: Date?
    /// The bytes of each of its resources found on the device (the video,
    /// an edit of it, the edit's data), by name, as `PhotoLibrary` names
    /// them. A resource that was not on the device, kept only in iCloud, is
    /// not in it: its size is not known.
    public var resources: [String: Int64]
    /// Whether every resource the video had was read: then `resources` is
    /// all of it.
    public var isComplete: Bool

    /// - Parameter resources: a size below zero counts as zero.
    public init(modified: Date?, resources: [String: Int64], isComplete: Bool) {
        self.modified = modified
        self.resources = resources.mapValues { max($0, 0) }
        self.isComplete = isComplete
    }

    /// What the resources of these names take, of those read: what deleting
    /// the video frees when they are the ones on the device. `Int64.max` at
    /// most, whatever a file held.
    public func bytes(of names: some Sequence<String>) -> Int64 {
        Set(names).reduce(0) { total, name in
            let (sum, overflow) = total.addingReportingOverflow(resources[name] ?? 0)
            return overflow ? .max : sum
        }
    }

    /// Whether the video may take `bytes` or more on the device, as far as
    /// this knows: not once every resource was read and they come to less.
    /// What an unchanged video takes here only shrinks, as iCloud takes its
    /// resources off the phone, and grows back only to what was read; so
    /// such a video need not be looked at again.
    public func mayTake(atLeast bytes: Int64) -> Bool {
        !isComplete || self.bytes(of: resources.keys) >= bytes
    }
}

/// Video sizes kept in a file between launches, so the videos of a library
/// are not read again, every byte, each time the app opens: a few dozen
/// bytes a video.
///
/// The file says how its videos were sized, `method`: a file of another
/// method reads as empty, and its videos are read again, as are those of a
/// file that cannot be read.
public struct VideoSizeStore: Hashable, Sendable {
    public let url: URL
    /// How the sizes were found, as `PhotoLibrary.videoSizing` says: sizes
    /// found another way, with resources named otherwise say, cannot be
    /// compared with this way's.
    public let method: String

    public init(url: URL, method: String) {
        self.url = url
        self.method = method
    }

    /// What the file holds, by video id: empty when there is no file, when
    /// it cannot be read, or when it is of another method. A video with a
    /// size below zero, which no read gives, is left out, to be read again.
    public func load() -> [String: SizedVideo] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let archive = try? PropertyListDecoder().decode(VideoArchive.self, from: data),
              archive.format == VideoArchive.currentFormat, archive.method == method
        else { return [:] }
        return archive.videos.compactMapValues { entry in
            guard entry.resources.values.allSatisfy({ $0 >= 0 }) else { return nil }
            return SizedVideo(modified: entry.modified, resources: entry.resources, isComplete: entry.isComplete)
        }
    }

    /// Replaces the file with these sizes, making its folder if need be. The
    /// new file takes the old one's place whole: a read meanwhile gets the
    /// old one or the new, never part of each.
    public func save(_ videos: [String: SizedVideo]) throws {
        let archive = VideoArchive(
            format: VideoArchive.currentFormat,
            method: method,
            videos: videos.mapValues { VideoEntry(modified: $0.modified, resources: $0.resources, isComplete: $0.isComplete) }
        )
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
private struct VideoArchive: Codable {
    /// The file's layout: a file of another layout reads as empty.
    static let currentFormat = 1

    var format: Int
    var method: String
    var videos: [String: VideoEntry]
}

/// A video in the file.
private struct VideoEntry: Codable {
    var modified: Date?
    var resources: [String: Int64]
    var isComplete: Bool
}
