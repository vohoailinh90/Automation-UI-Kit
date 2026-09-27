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
