import Foundation
import IdeaLabCore
import Testing

/// A store in a folder of its own, in a folder not made yet, removed after
/// the test.
private func withStore(method: String = "test", _ body: (MeasurementStore) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MeasurementStoreTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(MeasurementStore(url: folder.appendingPathComponent("Scan/Measurements.plist"), method: method))
}

private func photo(modified: Date?, sharpness: Double, print values: [Float]?) -> MeasuredPhoto {
    MeasuredPhoto(modified: modified, measurement: PhotoMeasurement(sharpness: sharpness, print: values.flatMap(FeaturePrint.init)))
}

/// A file as the store writes it, with these photos as they are written.
private func file(format: Int = 1, method: String = "test", photos: [String: [String: Any]]) throws -> Data {
    let archive: [String: Any] = ["format": format, "method": method, "photos": photos]
    return try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
}

/// Floats as the file keeps them: 32 bits each, little-endian.
private func bytes(_ values: [Float]) -> Data {
    Data(values.flatMap { value in
        let bits = value.bitPattern
        return [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
    })
}

struct MeasurementStoreTests {
    @Test func keepsWhatWasMeasured() throws {
        let modified = Date(timeIntervalSinceReferenceDate: 780_000_000.123_456)
        try withStore { store in
            try store.save([
                "a": photo(modified: modified, sharpness: 12.5, print: [0.1, -0.2, 0.3]),
                "b": photo(modified: nil, sharpness: .nan, print: [1]),
                "c": photo(modified: modified, sharpness: 3, print: nil),
            ])
            let kept = store.load()
            #expect(kept.count == 3)
            let a = try #require(kept["a"])
            #expect(a.modified == modified)
            #expect(a.measurement.sharpness == 12.5)
            #expect(a.measurement.print?.values == [0.1, -0.2, 0.3])
            let b = try #require(kept["b"])
            #expect(b.modified == nil)
            #expect(b.measurement.sharpness.isNaN)
            #expect(b.measurement.print?.values == [1])
            let c = try #require(kept["c"])
            #expect(c.measurement.sharpness == 3)
            #expect(c.measurement.print == nil)
        }
    }

    @Test func keepsWhatWasRecognised() throws {
        try withStore { store in
            try store.save([
                "none": photo(modified: nil, sharpness: 1, print: nil),
                "empty": MeasuredPhoto(modified: nil, measurement: PhotoMeasurement(sharpness: 1, print: nil, content: [])),
                "qr": MeasuredPhoto(modified: nil, measurement: PhotoMeasurement(sharpness: 1, print: nil, content: .qrCode)),
                "both": MeasuredPhoto(modified: nil, measurement: PhotoMeasurement(sharpness: 1, print: FeaturePrint([1]), content: [.qrCode, .document])),
            ])
            let kept = store.load()
            #expect(kept["none"]?.measurement.content == nil)
            #expect(kept["empty"]?.measurement.content == [])
            #expect(kept["qr"]?.measurement.content == .qrCode)
            #expect(kept["both"]?.measurement.content == [.qrCode, .document])
            #expect(kept["both"]?.measurement.print?.values == [1])
        }
    }

    @Test func noFileKeepsNothing() throws {
        try withStore { store in
            #expect(store.load().isEmpty)
        }
    }

    @Test func aFileOfAnotherMethodKeepsNothing() throws {
        try withStore(method: "print 1") { old in
            try old.save(["a": photo(modified: nil, sharpness: 1, print: [1])])
            #expect(old.load().count == 1)
            #expect(MeasurementStore(url: old.url, method: "print 2").load().isEmpty)
        }
    }

    @Test func aFileOfAnotherLayoutKeepsNothing() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let photos = ["a": ["sharpness": 1.0, "print": bytes([1])]]
            try file(photos: photos).write(to: store.url)
            #expect(store.load().count == 1)
            try file(format: 2, photos: photos).write(to: store.url)
            #expect(store.load().isEmpty)
        }
    }

    @Test func anUnreadableFileKeepsNothingUntilSavedAgain() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not a list".utf8).write(to: store.url)
            #expect(store.load().isEmpty)
            try store.save(["a": photo(modified: nil, sharpness: 1, print: [1])])
            #expect(store.load().count == 1)
        }
    }

    @Test func aPhotoWhosePrintCannotBeReadIsLeftOut() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file(photos: [
                "whole": ["sharpness": 1.0, "print": bytes([1, -0.5])],
                "noPrint": ["sharpness": 2.0],
                "partFloat": ["sharpness": 3.0, "print": Data([0, 0, 0x80, 0x3F, 0])],
                "empty": ["sharpness": 4.0, "print": Data()],
                "notANumber": ["sharpness": 5.0, "print": bytes([1, .nan])],
            ]).write(to: store.url)
            let kept = store.load()
            #expect(Set(kept.keys) == ["whole", "noPrint"])
            #expect(kept["whole"]?.measurement.print?.values == [1, -0.5])
            #expect(kept["noPrint"]?.measurement.print == nil)
        }
    }

    @Test func savingReplacesTheFile() throws {
        try withStore { store in
            try store.save(["a": photo(modified: nil, sharpness: 1, print: [1]), "b": photo(modified: nil, sharpness: 2, print: [2])])
            try store.save(["c": photo(modified: nil, sharpness: 3, print: [3])])
            #expect(Set(store.load().keys) == ["c"])
        }
    }

    @Test func removeDeletesTheFile() throws {
        try withStore { store in
            try store.save(["a": photo(modified: nil, sharpness: 1, print: [1])])
            #expect(store.remove())
            #expect(!FileManager.default.fileExists(atPath: store.url.path(percentEncoded: false)))
            #expect(store.load().isEmpty)
            // Nothing to delete leaves no file either.
            #expect(store.remove())
        }
    }
}
