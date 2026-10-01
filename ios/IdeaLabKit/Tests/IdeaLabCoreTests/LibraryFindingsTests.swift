import Foundation
import IdeaLabCore
import Testing

private let start = LedgerSamples.referenceNow

/// A photo taken `seconds` after `start`.
private func photo(_ id: String, at seconds: TimeInterval = 0, favorite: Bool = false, screenshot: Bool = false) -> LibraryPhoto {
    LibraryPhoto(id: id, date: start.addingTimeInterval(seconds), isFavorite: favorite, isScreenshot: screenshot)
}

/// A measurement whose print is a point on a line: prints `x` and `y` are
/// `|x - y|` apart.
private func measured(_ x: Float, sharpness: Double = 1) -> PhotoMeasurement {
    PhotoMeasurement(sharpness: sharpness, print: FeaturePrint([x, 0]))
}

private func ids(_ groups: [SimilarGroup]) -> [[String]] {
    groups.map { $0.photos.map(\.id) }
}

@Suite("Library findings: screenshots and look-alikes from PhotoKit and Vision")
struct LibraryFindingsTests {
    @Test("Screenshots: newest first, then by id; favourites left out; sizes as measured, else 0")
    func screenshots() {
        let findings = LibraryFindings(
            photos: [
                photo("s1", at: 10, screenshot: true),
                photo("s3", at: 30, screenshot: true),
                photo("s2", at: 30, screenshot: true),
                photo("loved", at: 40, favorite: true, screenshot: true),
                photo("camera", at: 50),
            ],
            measurements: [:],
            bytes: ["s1": 1_000, "s2": 2_000, "loved": 9_000]
        )
        #expect(findings.screenshots.map(\.id) == ["s2", "s3", "s1"])
        #expect(findings.screenshots.map(\.bytes) == [2_000, 0, 1_000])
        #expect(findings.screenshots.allSatisfy { $0.category == .screenshots })
        #expect(findings.screenshots[0].date == start.addingTimeInterval(30))
        #expect(findings.similarGroups.isEmpty)
    }

    @Test("Shots of one moment that look alike make a group, the sharpest suggested to keep")
    func groups() {
        let findings = LibraryFindings(
            photos: [photo("a1"), photo("a2", at: 5), photo("a3", at: 9), photo("b1", at: 20), photo("b2", at: 25)],
            measurements: [
                "a1": measured(0.0, sharpness: 5), "a2": measured(0.1, sharpness: 9), "a3": measured(0.2, sharpness: 1),
                "b1": measured(3.0), "b2": measured(3.3),
            ]
        )
        #expect(ids(findings.similarGroups) == [["b1", "b2"], ["a1", "a2", "a3"]])
        #expect(findings.similarGroups[1].sharpest.id == "a2")
        #expect(findings.similarGroups.flatMap(\.photos).allSatisfy { $0.item.category == .similar })
        #expect(findings.unmeasuredCount == 0)
    }

    @Test("Alike means every pair within the threshold, and within the window")
    func rules() {
        let photos = [photo("a"), photo("b", at: 60), photo("c", at: 200)]
        let measurements = ["a": measured(0), "b": measured(0.3), "c": measured(0.3)]
        // "c" is alike, but taken 140 s after "b": past the 120 s window.
        #expect(ids(LibraryFindings(photos: photos, measurements: measurements).similarGroups) == [["a", "b"]])
        #expect(ids(LibraryFindings(photos: photos, measurements: measurements, within: 300).similarGroups) == [["a", "b", "c"]])
        #expect(LibraryFindings(photos: photos, measurements: measurements, threshold: 0.2).similarGroups.isEmpty)
        // 0.4 apart: past 0.35, the threshold unless said.
        let far = ["a": measured(0), "b": measured(0.4)]
        #expect(LibraryFindings(photos: photos, measurements: far).similarGroups.isEmpty)
    }

    @Test("A screenshot is never in a group, however alike it looks")
    func screenshotsStayOut() {
        let findings = LibraryFindings(
            photos: [photo("shot", screenshot: true), photo("a", at: 1), photo("b", at: 2)],
            measurements: ["shot": measured(0), "a": measured(0), "b": measured(0)]
        )
        #expect(ids(findings.similarGroups) == [["a", "b"]])
        #expect(findings.screenshots.map(\.id) == ["shot"])
    }

    @Test("Photos with no print are in no group, and counted")
    func unmeasured() {
        let findings = LibraryFindings(
            photos: [photo("a"), photo("b", at: 1), photo("icloud", at: 2), photo("unread", at: 3), photo("shot", at: 4, screenshot: true)],
            measurements: ["a": measured(0), "b": measured(0), "unread": PhotoMeasurement(sharpness: 7, print: nil)]
        )
        #expect(ids(findings.similarGroups) == [["a", "b"]])
        #expect(findings.unmeasuredCount == 2)
    }

    @Test("A repeated id is one photo: its first record, a favourite if any record is")
    func repeated() {
        let findings = LibraryFindings(
            photos: [
                photo("s", screenshot: true), photo("s", at: 99, favorite: true, screenshot: true),
                photo("a"), photo("b", at: 1), photo("a", at: 50, favorite: true), photo("a", at: 51, screenshot: true),
            ],
            measurements: ["a": measured(0, sharpness: 1), "b": measured(0, sharpness: 9)]
        )
        #expect(findings.screenshots.isEmpty)
        #expect(ids(findings.similarGroups) == [["a", "b"]])
        let group = findings.similarGroups[0]
        #expect(group.photos[0].item.isFavorite)
        #expect(group.photos[0].item.date == start)
        // The sharper "b" is kept, and so is the favourite "a".
        #expect(group.suggestedKeep == ["a", "b"])

        // Listed once, counted once.
        let twice = LibraryFindings(
            photos: [photo("s", at: 5, screenshot: true), photo("s", at: 9, screenshot: true), photo("x", at: 100), photo("x", at: 100), photo("y", at: 101)],
            measurements: [:],
            bytes: ["s": 700]
        )
        #expect(twice.screenshots.map(\.id) == ["s"])
        #expect(twice.screenshots[0].date == start.addingTimeInterval(5))
        #expect(twice.summary == [CategorySummary(category: .screenshots, count: 1, bytes: 700)])
        #expect(twice.unmeasuredCount == 2)
    }

    @Test("The summary: screenshots, and the photos the groups suggest deleting")
    func summary() {
        let findings = LibraryFindings(
            photos: [
                photo("s1", screenshot: true), photo("s2", at: 1, screenshot: true),
                photo("a1", at: 10), photo("a2", at: 11), photo("a3", at: 12),
                photo("b1", at: 20), photo("b2", at: 21, favorite: true),
            ],
            measurements: [
                "a1": measured(0, sharpness: 1), "a2": measured(0, sharpness: 2), "a3": measured(0, sharpness: 3),
                "b1": measured(5, sharpness: 9), "b2": measured(5, sharpness: 1),
            ],
            bytes: ["s1": 100, "s2": 200, "a1": 1_000, "a2": 2_000, "a3": 3_000, "b1": 10_000, "b2": 20_000]
        )
        // a3 is kept, the sharpest; so are b1, the sharpest, and b2, a favourite.
        #expect(findings.summary == [
            CategorySummary(category: .screenshots, count: 2, bytes: 300),
            CategorySummary(category: .similar, count: 2, bytes: 3_000),
        ])
        #expect(findings.sizedIDs == ["s2", "s1", "b1", "b2", "a1", "a2", "a3"])
    }

    @Test("Only photos taken within the window of another are candidates: one alone is in no group")
    func candidates() {
        let photos = [
            photo("alone", at: 0),
            photo("a", at: 1_000), photo("b", at: 1_120), photo("c", at: 1_240),
            photo("late", at: 1_361),
            photo("shot", at: 1_400, screenshot: true), photo("near shot", at: 1_500),
        ]
        // "late" is 121 s after "c"; the screenshot makes no photo a candidate.
        #expect(LibraryFindings.candidates(in: photos) == ["a", "b", "c"])
        #expect(LibraryFindings.candidates(in: photos, within: 121) == ["a", "b", "c", "late"])
        #expect(LibraryFindings.candidates(in: photos, within: 1_000) == ["alone", "a", "b", "c", "late", "near shot"])
        // A window that is negative or not a number is zero: only photos of
        // one instant are candidates.
        let instant = [photo("x", at: 5), photo("y", at: 5), photo("z", at: 6)]
        #expect(LibraryFindings.candidates(in: instant, within: -1) == ["x", "y"])
        #expect(LibraryFindings.candidates(in: instant, within: .nan) == ["x", "y"])
        #expect(LibraryFindings.candidates(in: [photo("only")]).isEmpty)
        #expect(LibraryFindings.candidates(in: []).isEmpty)
    }

    @Test("Candidates: a repeated id is its first record, and the order is by date, then id")
    func candidateOrder() {
        let photos = [photo("b", at: 10), photo("a", at: 10), photo("b", at: 900), photo("s", at: 11, screenshot: true), photo("s", at: 12)]
        #expect(LibraryFindings.candidates(in: photos) == ["a", "b"])
    }

    @Test("Candidates: dates that are not finite numbers are the distant past, as the groups take them")
    func candidateBadDates() {
        let nan = Date(timeIntervalSinceReferenceDate: .nan)
        let photos = [
            LibraryPhoto(id: "n2", date: nan), LibraryPhoto(id: "n1", date: nan),
            LibraryPhoto(id: "past", date: .distantPast), photo("now"),
        ]
        #expect(LibraryFindings.candidates(in: photos) == ["n1", "n2", "past"])
        let findings = LibraryFindings(photos: photos, measurements: ["n1": measured(0), "n2": measured(0), "past": measured(0)])
        #expect(ids(findings.similarGroups) == [["n1", "n2", "past"]])
    }

    @Test("A photo alone in its moment is not measured, and not counted as unmeasured")
    func aloneNotCounted() {
        let findings = LibraryFindings(
            photos: [photo("alone"), photo("a", at: 500), photo("b", at: 501)],
            measurements: ["alone": measured(0), "a": measured(0), "b": measured(0)]
        )
        #expect(ids(findings.similarGroups) == [["a", "b"]])
        #expect(findings.unmeasuredCount == 0)
        #expect(LibraryFindings(photos: [photo("alone"), photo("a", at: 500), photo("b", at: 501)], measurements: [:]).unmeasuredCount == 2)
    }

    @Test("Modification dates: of the photos offered, as first listed; none listed is kept as none")
    func modificationDates() {
        let first = start.addingTimeInterval(1_000)
        let later = start.addingTimeInterval(2_000)
        let findings = LibraryFindings(
            photos: [
                LibraryPhoto(id: "s", date: start, isScreenshot: true, modified: first),
                LibraryPhoto(id: "a", date: start, modified: first),
                LibraryPhoto(id: "b", date: start.addingTimeInterval(1)),
                LibraryPhoto(id: "a", date: start, modified: later),
                LibraryPhoto(id: "alone", date: start.addingTimeInterval(9_000), modified: first),
                LibraryPhoto(id: "loved", date: start, isFavorite: true, isScreenshot: true, modified: first),
            ],
            measurements: ["a": measured(0), "b": measured(0)]
        )
        #expect(ids(findings.similarGroups) == [["a", "b"]])
        // "alone" is in no group, and "loved" is a favourite. "b" was listed
        // with no date: kept as such, so a date it gets later tells.
        #expect(findings.modificationDates == ["s": first, "a": first, "b": nil])
        #expect(Set(findings.modificationDates.keys) == ["s", "a", "b"])
    }

    @Test("Nothing found: no summary, nothing to size")
    func empty() {
        let findings = LibraryFindings(photos: [photo("a"), photo("b", at: 1000)], measurements: ["a": measured(0), "b": measured(0)])
        #expect(findings.summary.isEmpty)
        #expect(findings.sizedIDs.isEmpty)
        #expect(findings.unmeasuredCount == 0)
        #expect(LibraryFindings(photos: [], measurements: [:]).summary.isEmpty)
    }

    @Test("A date that is not a finite number sorts as the distant past")
    func badDate() {
        let findings = LibraryFindings(
            photos: [
                LibraryPhoto(id: "nan", date: Date(timeIntervalSinceReferenceDate: .nan), isScreenshot: true),
                photo("s", screenshot: true),
            ],
            measurements: [:]
        )
        #expect(findings.screenshots.map(\.id) == ["s", "nan"])
        #expect(findings.screenshots[1].date == .distantPast)
    }

    @Test("QR codes and documents: newest first, each photo in one category, a QR code first")
    func content() {
        let findings = LibraryFindings(
            photos: [
                photo("wifi", at: 100), photo("ticket", at: 300), photo("both", at: 200),
                photo("receipt", at: 400), photo("page", at: 400), photo("view", at: 500), photo("unread", at: 600),
            ],
            measurements: [
                "wifi": PhotoMeasurement(sharpness: 1, print: nil, content: .qrCode),
                "ticket": PhotoMeasurement(sharpness: 1, print: nil, content: .qrCode),
                "both": PhotoMeasurement(sharpness: 1, print: nil, content: [.qrCode, .document]),
                "receipt": PhotoMeasurement(sharpness: 1, print: nil, content: .document),
                "page": PhotoMeasurement(sharpness: 1, print: nil, content: .document),
                "view": PhotoMeasurement(sharpness: 1, print: nil, content: []),
            ],
            bytes: ["wifi": 10, "ticket": 20, "both": 40, "receipt": 100, "page": 200, "view": 1_000]
        )
        #expect(findings.qrCodes.map(\.id) == ["ticket", "both", "wifi"])
        #expect(findings.qrCodes.allSatisfy { $0.category == .qrCodes })
        #expect(findings.documents.map(\.id) == ["page", "receipt"])
        #expect(findings.documents.allSatisfy { $0.category == .documents })
        #expect(findings.unclassifiedCount == 1)
        #expect(findings.summary == [
            CategorySummary(category: .documents, count: 2, bytes: 300),
            CategorySummary(category: .qrCodes, count: 3, bytes: 70),
        ])
        #expect(findings.sizedIDs == ["ticket", "both", "wifi", "page", "receipt"])
        #expect(Set(findings.modificationDates.keys) == ["ticket", "both", "wifi", "page", "receipt"])
    }

    @Test("Never a QR code or a document: a screenshot, a favourite, a photo of a group")
    func contentLeftOut() {
        let qr = PhotoContent.qrCode
        let findings = LibraryFindings(
            photos: [
                photo("shot", at: 0, screenshot: true), photo("loved", at: 1_000, favorite: true),
                photo("twice", at: 2_000), photo("twice", at: 2_000, favorite: true),
                photo("g1", at: 3_000), photo("g2", at: 3_001), photo("alone", at: 4_000),
            ],
            measurements: [
                "shot": PhotoMeasurement(sharpness: 1, print: nil, content: qr),
                "loved": PhotoMeasurement(sharpness: 1, print: nil, content: qr),
                "twice": PhotoMeasurement(sharpness: 1, print: nil, content: qr),
                "g1": PhotoMeasurement(sharpness: 1, print: FeaturePrint([0, 0]), content: qr),
                "g2": PhotoMeasurement(sharpness: 2, print: FeaturePrint([0, 0]), content: .document),
                "alone": PhotoMeasurement(sharpness: 1, print: nil, content: .document),
            ]
        )
        #expect(findings.screenshots.map(\.id) == ["shot"])
        #expect(ids(findings.similarGroups) == [["g1", "g2"]])
        #expect(findings.qrCodes.isEmpty)
        #expect(findings.documents.map(\.id) == ["alone"])
        // Screenshots are never looked at, nor favourites counted.
        #expect(findings.unclassifiedCount == 0)
        #expect(LibraryFindings(photos: [photo("a"), photo("b", favorite: true), photo("c", screenshot: true)], measurements: [:])
            .unclassifiedCount == 1)
    }

    @Test("Taken badly: below the threshold, worst first, then newest; never a utility photo; a QR code or a document first")
    func blurry() {
        func scored(_ aesthetics: Float?, _ content: PhotoContent = []) -> PhotoMeasurement {
            PhotoMeasurement(sharpness: 1, print: nil, content: content, aesthetics: aesthetics)
        }
        let findings = LibraryFindings(
            photos: [
                photo("dark", at: 100), photo("shaken", at: 200), photo("tilted", at: 100), photo("edge", at: 300),
                photo("fine", at: 400), photo("label", at: 500), photo("qr", at: 600), photo("page", at: 700),
                photo("unscored", at: 800), photo("odd", at: 900), photo("unread", at: 1_000), photo("pocket", at: 1_100),
            ],
            measurements: [
                "dark": scored(-0.9),
                "shaken": scored(-0.7),
                "tilted": scored(-0.7),
                "edge": scored(LibraryFindings.blurryBelow),
                "fine": scored(0.3),
                // Low for what it shows: a utility photo.
                "label": scored(-0.95, .utility),
                "qr": scored(-0.9, .qrCode),
                "page": scored(-0.9, [.document, .utility]),
                "unscored": scored(nil),
                "odd": scored(.nan),
                "pocket": scored(-.infinity),
            ],
            bytes: ["dark": 1, "shaken": 2, "tilted": 4, "edge": 8, "qr": 16, "page": 32, "pocket": 64]
        )
        #expect(findings.blurry.map(\.id) == ["pocket", "dark", "shaken", "tilted"])
        #expect(findings.blurry.allSatisfy { $0.category == .blurry })
        #expect(findings.qrCodes.map(\.id) == ["qr"])
        #expect(findings.documents.map(\.id) == ["page"])
        #expect(findings.unclassifiedCount == 1)
        #expect(findings.summary == [
            CategorySummary(category: .blurry, count: 4, bytes: 71),
            CategorySummary(category: .documents, count: 1, bytes: 32),
            CategorySummary(category: .qrCodes, count: 1, bytes: 16),
        ])
        #expect(findings.sizedIDs == ["qr", "page", "pocket", "dark", "shaken", "tilted"])
        #expect(Set(findings.modificationDates.keys) == ["qr", "page", "pocket", "dark", "shaken", "tilted"])
    }

    @Test("Taken badly is up to the threshold passed, strictly below it")
    func blurryThreshold() {
        let photos = [photo("a", at: 0), photo("b", at: 1_000), photo("c", at: 2_000)]
        let measurements = [
            "a": PhotoMeasurement(sharpness: 1, print: nil, content: [], aesthetics: -0.2),
            "b": PhotoMeasurement(sharpness: 1, print: nil, content: [], aesthetics: 0),
            "c": PhotoMeasurement(sharpness: 1, print: nil, content: [], aesthetics: -0.6),
        ]
        #expect(LibraryFindings.blurryBelow == -0.5)
        #expect(LibraryFindings(photos: photos, measurements: measurements).blurry.map(\.id) == ["c"])
        #expect(LibraryFindings(photos: photos, measurements: measurements, blurryBelow: 0).blurry.map(\.id) == ["c", "a"])
        #expect(LibraryFindings(photos: photos, measurements: measurements, blurryBelow: -1).blurry.isEmpty)
        #expect(LibraryFindings(photos: photos, measurements: measurements, blurryBelow: .nan).blurry.isEmpty)
    }

    @Test("Never offered as taken badly: a screenshot, a favourite, a photo of a group")
    func blurryLeftOut() {
        let low = PhotoMeasurement(sharpness: 1, print: nil, content: [], aesthetics: -0.9)
        let findings = LibraryFindings(
            photos: [
                photo("shot", at: 0, screenshot: true), photo("loved", at: 1_000, favorite: true),
                photo("twice", at: 2_000), photo("twice", at: 2_000, favorite: true),
                photo("g1", at: 3_000), photo("g2", at: 3_001), photo("alone", at: 4_000),
            ],
            measurements: [
                "shot": low, "loved": low, "twice": low,
                "g1": PhotoMeasurement(sharpness: 1, print: FeaturePrint([0, 0]), content: [], aesthetics: -0.9),
                "g2": PhotoMeasurement(sharpness: 2, print: FeaturePrint([0, 0]), content: [], aesthetics: -0.9),
                "alone": low,
            ]
        )
        #expect(findings.screenshots.map(\.id) == ["shot"])
        #expect(ids(findings.similarGroups) == [["g1", "g2"]])
        #expect(findings.blurry.map(\.id) == ["alone"])
    }

    @Test("Keeping what was not asked: the print when none, the look when none, both from before; the sharpness is new")
    func keeping() {
        let before = PhotoMeasurement(sharpness: 1, print: FeaturePrint([1, 0]), content: [.document, .utility], aesthetics: -0.25)
        let unchanged = PhotoMeasurement(sharpness: 2, print: nil, content: nil).keeping(nil)
        #expect(unchanged.sharpness == 2)
        #expect(unchanged.print == nil)
        #expect(unchanged.content == nil)
        #expect(unchanged.aesthetics == nil)

        // Only the print asked for: what the photo shows, and how well it
        // was taken, are the earlier look's.
        let printed = PhotoMeasurement(sharpness: 3, print: FeaturePrint([0, 1]), content: nil).keeping(before)
        #expect(printed.sharpness == 3)
        #expect(printed.print?.values == [0, 1])
        #expect(printed.content == [.document, .utility])
        #expect(printed.aesthetics == -0.25)

        // Only a look asked for: its content, and its score even if none.
        let looked = PhotoMeasurement(sharpness: 4, print: nil, content: .qrCode).keeping(before)
        #expect(looked.print?.values == [1, 0])
        #expect(looked.content == .qrCode)
        #expect(looked.aesthetics == nil)

        // A score without a look is not one: the earlier look's is kept.
        let stray = PhotoMeasurement(sharpness: 5, print: nil, content: nil, aesthetics: 0.5).keeping(before)
        #expect(stray.content == [.document, .utility])
        #expect(stray.aesthetics == -0.25)
    }

    @Test("Not fully looked at: a photo counted once, whatever it lacks")
    func unexamined() {
        let findings = LibraryFindings(
            photos: [
                // Candidates: looked at but no print; neither; both.
                photo("noPrint", at: 0), photo("nothing", at: 1), photo("done", at: 2),
                // Alone, so needs no print: not looked at; looked at.
                photo("unread", at: 1_000), photo("read", at: 2_000),
                // A favourite not looked at is not counted, unless a group lacks its print.
                photo("loved", at: 3_000, favorite: true),
            ],
            measurements: [
                "noPrint": PhotoMeasurement(sharpness: 1, print: nil, content: []),
                "done": PhotoMeasurement(sharpness: 1, print: FeaturePrint([0, 0]), content: []),
                "read": PhotoMeasurement(sharpness: 1, print: nil, content: []),
            ]
        )
        #expect(findings.unmeasuredCount == 2)
        #expect(findings.unclassifiedCount == 2)
        #expect(findings.unexaminedCount == 3)
    }
}

/// A video filmed `seconds` after `start`.
private func video(
    _ id: String, at seconds: TimeInterval = 0, favorite: Bool = false, duration: TimeInterval = 30, modified: Date? = nil
) -> LibraryVideo {
    LibraryVideo(id: id, date: start.addingTimeInterval(seconds), isFavorite: favorite, duration: duration, modified: modified)
}

private let megabyte: Int64 = 1_000_000

@Suite("Library findings: the videos that take the most room")
struct LibraryVideoFindingsTests {
    @Test("Largest first, then newest, then by id; from the threshold on; favourites and videos not here left out")
    func largest() {
        let findings = LibraryFindings(
            photos: [],
            videos: [
                video("a", at: 0, duration: 75), video("b", at: 10, duration: 312), video("c", at: 20), video("d", at: 20),
                video("under", at: 30), video("at", at: 40), video("elsewhere", at: 50), video("loved", at: 60, favorite: true),
            ],
            measurements: [:],
            bytes: [
                "a": 30 * megabyte, "b": 900 * megabyte, "c": 30 * megabyte, "d": 30 * megabyte,
                "under": 20 * megabyte - 1, "at": 20 * megabyte, "loved": 900 * megabyte,
            ]
        )
        #expect(findings.largeVideos.map(\.id) == ["b", "c", "d", "a", "at"])
        #expect(findings.largeVideos.map(\.bytes) == [900 * megabyte, 30 * megabyte, 30 * megabyte, 30 * megabyte, 20 * megabyte])
        #expect(findings.largeVideos.allSatisfy { $0.category == .largeVideos && !$0.isFavorite })
        #expect(findings.largeVideos[0].duration == 312)
        #expect(findings.largeVideos[3].duration == 75)
        #expect(findings.largeVideos[0].date == start.addingTimeInterval(10))
        #expect(LibraryFindings.largeVideoAtLeast == 20 * megabyte)
    }

    @Test("The threshold is the one passed; a video that takes nothing here is never offered")
    func threshold() {
        let videos = [video("big"), video("small", at: 1), video("elsewhere", at: 2), video("empty", at: 3)]
        let bytes: [String: Int64] = ["big": 500 * megabyte, "small": 1, "empty": 0]
        #expect(LibraryFindings(photos: [], videos: videos, measurements: [:], bytes: bytes, largeVideoAtLeast: 100 * megabyte)
            .largeVideos.map(\.id) == ["big"])
        #expect(LibraryFindings(photos: [], videos: videos, measurements: [:], bytes: bytes, largeVideoAtLeast: 0)
            .largeVideos.map(\.id) == ["big", "small"])
        #expect(LibraryFindings(photos: [], videos: videos, measurements: [:], bytes: bytes, largeVideoAtLeast: -5)
            .largeVideos.map(\.id) == ["big", "small"])
    }

    @Test("A repeated id is one video: its first record, a favourite if any record is; a photo's id is a photo")
    func repeated() {
        let findings = LibraryFindings(
            photos: [photo("shared", screenshot: true)],
            videos: [
                video("v", at: 5, duration: 10), video("v", at: 9, duration: 99),
                video("w", at: 1), video("w", at: 2, favorite: true),
                video("shared", at: 3),
            ],
            measurements: [:],
            bytes: ["v": 50 * megabyte, "w": 60 * megabyte, "shared": 70 * megabyte]
        )
        #expect(findings.largeVideos.map(\.id) == ["v"])
        #expect(findings.largeVideos[0].duration == 10)
        #expect(findings.largeVideos[0].date == start.addingTimeInterval(5))
        // The photo stays what it is: a screenshot, with the size given.
        #expect(findings.screenshots.map(\.id) == ["shared"])
        #expect(findings.screenshots[0].bytes == 70 * megabyte)
    }

    @Test("The summary counts the videos; none is sized with the photos")
    func summary() {
        let findings = LibraryFindings(
            photos: [photo("s", screenshot: true)],
            videos: [video("v1"), video("v2", at: 1), video("small", at: 2)],
            measurements: [:],
            bytes: ["s": 2 * megabyte, "v1": 40 * megabyte, "v2": 60 * megabyte, "small": megabyte]
        )
        let videos = findings.summary.first { $0.category == .largeVideos }
        #expect(videos?.count == 2)
        #expect(videos?.bytes == 100 * megabyte)
        #expect(findings.summary.map(\.category) == [.screenshots, .largeVideos])
        #expect(findings.sizedIDs == ["s"])
    }

    @Test("Modification dates: of the videos offered, as first listed; none listed is kept as none")
    func modificationDates() {
        let first = start.addingTimeInterval(1_000)
        let later = start.addingTimeInterval(2_000)
        let findings = LibraryFindings(
            photos: [],
            videos: [
                video("dated", modified: first), video("undated", at: 1), video("dated", at: 2, modified: later),
                video("small", at: 3, modified: first), video("loved", at: 4, favorite: true, modified: first),
            ],
            measurements: [:],
            bytes: ["dated": 30 * megabyte, "undated": 30 * megabyte, "small": megabyte, "loved": 30 * megabyte]
        )
        #expect(findings.modificationDates == ["dated": first, "undated": nil])
        #expect(Set(findings.modificationDates.keys) == ["dated", "undated"])
    }

    @Test("A date that is not a finite number sorts as the distant past; a length that is not one is unknown")
    func oddValues() {
        let findings = LibraryFindings(
            photos: [],
            videos: [
                LibraryVideo(id: "nan", date: Date(timeIntervalSinceReferenceDate: .nan), duration: .nan),
                LibraryVideo(id: "dated", date: start, duration: -3),
                LibraryVideo(id: "endless", date: start, duration: .infinity),
            ],
            measurements: [:],
            bytes: ["nan": 30 * megabyte, "dated": 30 * megabyte, "endless": 30 * megabyte]
        )
        #expect(findings.largeVideos.map(\.id) == ["dated", "endless", "nan"])
        #expect(findings.largeVideos[2].date == .distantPast)
        #expect(findings.largeVideos[2].duration == nil)
        #expect(findings.largeVideos[0].duration == 0)
        #expect(findings.largeVideos[1].duration == nil)
    }
}
