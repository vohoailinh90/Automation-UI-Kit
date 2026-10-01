import Foundation
import IdeaLabCore
import Testing

/// A store in a folder of its own, in a folder not made yet, removed after
/// the test.
private func withStore(method: String = "test", _ body: (VideoSizeStore) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VideoSizeStoreTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(VideoSizeStore(url: folder.appendingPathComponent("Scan/Measurements-videos.plist"), method: method))
}

/// A file as the store writes it, with these videos as they are written.
private func file(format: Int = 1, method: String = "test", videos: [String: [String: Any]]) throws -> Data {
    let archive: [String: Any] = ["format": format, "method": method, "videos": videos]
    return try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
}

@Suite("Video sizes: what a video's resources take here, as read")
struct SizedVideoTests {
    @Test("A size below zero counts as zero")
    func negative() {
        let video = SizedVideo(modified: nil, resources: ["a": -5, "b": 7], isComplete: true)
        #expect(video.resources == ["a": 0, "b": 7])
    }

    @Test("Bytes of the resources named: those read, each once, Int64.max at most")
    func bytes() {
        let video = SizedVideo(modified: nil, resources: ["video": 800, "edit": 300, "data": 2], isComplete: true)
        #expect(video.bytes(of: ["video", "edit", "data"]) == 1_102)
        #expect(video.bytes(of: ["edit"]) == 300)
        #expect(video.bytes(of: ["edit", "edit"]) == 300)
        #expect(video.bytes(of: ["unread", "edit"]) == 300)
        #expect(video.bytes(of: []) == 0)
        let huge = SizedVideo(modified: nil, resources: ["a": .max, "b": .max, "c": 1], isComplete: true)
        #expect(huge.bytes(of: ["a", "b", "c"]) == .max)
    }

    @Test("May take the threshold: unless every resource was read and they come to less")
    func mayTake() {
        let read = SizedVideo(modified: nil, resources: ["video": 15, "edit": 5], isComplete: true)
        #expect(read.mayTake(atLeast: 20))
        #expect(!read.mayTake(atLeast: 21))
        let partly = SizedVideo(modified: nil, resources: ["edit": 5], isComplete: false)
        #expect(partly.mayTake(atLeast: 1_000))
        #expect(SizedVideo(modified: nil, resources: [:], isComplete: false).mayTake(atLeast: 1))
        #expect(!SizedVideo(modified: nil, resources: [:], isComplete: true).mayTake(atLeast: 1))
        #expect(SizedVideo(modified: nil, resources: [:], isComplete: true).mayTake(atLeast: 0))
    }
}

@Suite("Video size store: sizes kept between launches")
struct VideoSizeStoreTests {
    @Test func keepsWhatWasRead() throws {
        let modified = Date(timeIntervalSinceReferenceDate: 780_000_000.123_456)
        try withStore { store in
            try store.save([
                "a": SizedVideo(modified: modified, resources: ["1 IMG_0001.MOV": 872_000_000, "7 FullSizeRender.mov": 3], isComplete: true),
                "b": SizedVideo(modified: nil, resources: [:], isComplete: false),
                "c": SizedVideo(modified: modified, resources: ["1 IMG_0002.MOV": 0], isComplete: false),
            ])
            let kept = store.load()
            #expect(kept.count == 3)
            #expect(kept["a"] == SizedVideo(modified: modified, resources: ["1 IMG_0001.MOV": 872_000_000, "7 FullSizeRender.mov": 3], isComplete: true))
            #expect(kept["b"] == SizedVideo(modified: nil, resources: [:], isComplete: false))
            #expect(kept["c"] == SizedVideo(modified: modified, resources: ["1 IMG_0002.MOV": 0], isComplete: false))
        }
    }

    @Test func noFileKeepsNothing() throws {
        try withStore { store in
            #expect(store.load().isEmpty)
        }
    }

    @Test func aFileOfAnotherMethodKeepsNothing() throws {
        try withStore(method: "read 1") { old in
            try old.save(["a": SizedVideo(modified: nil, resources: ["v": 1], isComplete: true)])
            #expect(old.load().count == 1)
            #expect(VideoSizeStore(url: old.url, method: "read 2").load().isEmpty)
        }
    }

    @Test func aFileOfAnotherLayoutKeepsNothing() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let videos: [String: [String: Any]] = ["a": ["resources": ["v": 5], "isComplete": true]]
            try file(videos: videos).write(to: store.url)
            #expect(store.load() == ["a": SizedVideo(modified: nil, resources: ["v": 5], isComplete: true)])
            try file(format: 2, videos: videos).write(to: store.url)
            #expect(store.load().isEmpty)
        }
    }

    @Test func anUnreadableFileKeepsNothingUntilSavedAgain() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not a list".utf8).write(to: store.url)
            #expect(store.load().isEmpty)
            try store.save(["a": SizedVideo(modified: nil, resources: ["v": 1], isComplete: true)])
            #expect(store.load().count == 1)
        }
    }

    @Test func aVideoWithASizeBelowZeroIsLeftOut() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file(videos: [
                "fine": ["resources": ["v": 5, "e": 0], "isComplete": true],
                "odd": ["resources": ["v": 5, "e": -1], "isComplete": true],
            ]).write(to: store.url)
            #expect(Set(store.load().keys) == ["fine"])
        }
    }

    @Test func savingReplacesTheFile() throws {
        try withStore { store in
            try store.save([
                "a": SizedVideo(modified: nil, resources: ["v": 1], isComplete: true),
                "b": SizedVideo(modified: nil, resources: ["v": 2], isComplete: true),
            ])
            try store.save(["c": SizedVideo(modified: nil, resources: ["v": 3], isComplete: true)])
            #expect(Set(store.load().keys) == ["c"])
        }
    }

    @Test func removeDeletesTheFile() throws {
        try withStore { store in
            try store.save(["a": SizedVideo(modified: nil, resources: ["v": 1], isComplete: true)])
            #expect(store.remove())
            #expect(!FileManager.default.fileExists(atPath: store.url.path(percentEncoded: false)))
            #expect(store.load().isEmpty)
            // Nothing to delete leaves no file either.
            #expect(store.remove())
        }
    }
}
