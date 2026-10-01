import IdeaLabCore
import IdeaLabUI
import SwiftUI

/// The photo cleaner's sample state: a phone with 9,6 GB left, a deck of
/// screenshots part-way through, a finished swipe waiting for review, and
/// the same for the largest videos.
@Observable
@MainActor
final class DemoCleanerStore {
    let storage = CleanupSamples.storage
    let summaries = CleanupMath.summary(of: CleanupSamples.items())
    let now = LedgerSamples.referenceNow
    let calendar = LedgerSamples.calendar
    /// 88 of the 100 free deletions used, so the review shows the free/unlock split.
    var allowance = FreeAllowance(used: 88)
    var swipe: CleanupSession
    var review: CleanupSession
    /// Every video, the largest first, the first three decided.
    var videos: CleanupSession
    /// The twelve largest videos swiped through, most of them to delete.
    var videosReview: CleanupSession
    /// Six moments shot several times, each keeping its sharpest shot.
    var similar = CleanupSamples.similarReview()
    /// The done screen's sample: the review's photos, as if all were deleted.
    /// Fixed, so deleting in the review demo doesn't change it.
    let deletedCount: Int
    let bytesFreed: Int64

    init() {
        var swipe = CleanupSession(items: CleanupSamples.deck(.screenshots, count: 48))
        for index in 0..<12 {
            swipe.decide(index % 3 == 1 ? .keep : .delete)
        }
        self.swipe = swipe

        var review = CleanupSession(items: CleanupSamples.deck(.screenshots, count: 30))
        for index in 0..<30 {
            review.decide(index % 4 == 2 ? .keep : .delete)
        }
        for item in review.swipedToDelete.dropFirst(4).prefix(2) {
            review.toggleMark(item.id)
        }
        self.review = review
        deletedCount = review.toDelete.count
        bytesFreed = review.bytesToFree

        var videos = CleanupSession(items: CleanupSamples.deck(.largeVideos, count: 24))
        for decision in [CleanupSession.Decision.delete, .keep, .delete] {
            videos.decide(decision)
        }
        self.videos = videos

        var videosReview = CleanupSession(items: CleanupSamples.deck(.largeVideos, count: 12))
        for index in 0..<12 {
            videosReview.decide(index % 3 == 2 ? .keep : .delete)
        }
        if let item = videosReview.swipedToDelete.dropFirst(2).first {
            videosReview.toggleMark(item.id)
        }
        self.videosReview = videosReview
    }
}

struct CleanerSwipeDemo: View {
    @Bindable var store: DemoCleanerStore

    var body: some View {
        CleanupSwipeScreen(session: $store.swipe, calendar: store.calendar) { item in
            DemoPhoto(item: item)
        } onReview: {}
    }
}

struct CleanerReviewDemo: View {
    @Bindable var store: DemoCleanerStore

    var body: some View {
        CleanupReviewScreen(session: $store.review, allowance: store.allowance) { item in
            DemoPhoto(item: item)
        } onDelete: { items in
            // No PhotoKit in the demo: it acts as if iOS deleted them all, and
            // counts them against the free allowance as a real app does.
            store.allowance.use(items.count)
            return Set(items.map(\.id))
        } onUnlock: {}
    }
}

struct CleanerVideosDemo: View {
    @Bindable var store: DemoCleanerStore

    var body: some View {
        CleanupSwipeScreen(session: $store.videos, calendar: store.calendar) { item in
            DemoPhoto(item: item)
        } onReview: {}
    }
}

struct CleanerVideosReviewDemo: View {
    @Bindable var store: DemoCleanerStore

    var body: some View {
        CleanupReviewScreen(session: $store.videosReview, allowance: store.allowance) { item in
            DemoPhoto(item: item)
        } onDelete: { items in
            // As the photos' review: iOS "deleted" them all, and each video
            // counts as one against the free allowance.
            store.allowance.use(items.count)
            return Set(items.map(\.id))
        } onUnlock: {}
    }
}

struct CleanerSimilarDemo: View {
    @Bindable var store: DemoCleanerStore

    var body: some View {
        // The full version: the review demo shows the free allowance's split.
        SimilarPhotosScreen(review: $store.similar, allowance: nil, now: store.now, calendar: store.calendar) { photo in
            DemoSimilarPhoto(photo: photo)
        } onDelete: { items in
            // No PhotoKit in the demo: it acts as if iOS deleted them all.
            Set(items.map(\.id))
        } onUnlock: {}
    }
}

// MARK: - Sample photos

/// Stand-ins for the user's photos, drawn so each category looks like what
/// it is: chat screenshots, a scenic shot (sharp or shaken), a receipt on a
/// table, a QR code on a shop's sign, a birthday filmed at home. A real app
/// shows PhotoKit thumbnails, a video's first frame for a video.
struct DemoPhoto: View {
    let item: CleanupItem

    private var seed: UInt64 {
        UInt64(item.id.split(separator: "-").last.flatMap { Int($0) } ?? 0)
    }

    var body: some View {
        switch item.category {
        case .screenshots: ChatScreenshot(seed: seed)
        case .similar: Landscape(seed: seed / 3)
        case .blurry: Landscape(seed: seed).blur(radius: 7, opaque: true)
        case .documents: Receipt(seed: seed)
        case .qrCodes: QRSign(seed: seed)
        case .largeVideos: HomeVideo(seed: seed)
        }
    }
}

/// A shot of a sample moment ("similar-<moment>-<shot>"): the moment's
/// scene, framed a little differently each time as the camera moved, and as
/// soft as the shot was shaken.
struct DemoSimilarPhoto: View {
    let photo: SimilarPhoto

    var body: some View {
        let parts = photo.id.split(separator: "-")
        let moment = parts.count == 3 ? UInt64(parts[1]) ?? 0 : 0
        let shot = parts.count == 3 ? Int(parts[2]) ?? 0 : 0
        Landscape(seed: moment * 7)
            .scaleEffect(1.1)
            .offset(x: CGFloat(shot % 3 - 1) * 4, y: CGFloat(shot % 2) * 3)
            .blur(radius: min(max(1 - photo.sharpness, 0), 1) * 6, opaque: true)
            .clipped()
    }
}

/// Tiny deterministic generator for the drawings.
private struct DrawingRandom {
    private var state: UInt64

    init(_ seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

struct ChatScreenshot: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var random = DrawingRandom(seed)
            let accents: [Color] = [
                Color(red: 0, green: 0.41, blue: 1),        // Zalo
                Color(red: 0.04, green: 0.52, blue: 1),     // iMessage
                Color(red: 0.48, green: 0.38, blue: 1),     // Messenger
                Color(red: 0.2, green: 0.78, blue: 0.35),   // SMS
            ]
            let accent = accents[Int(seed) % accents.count]
            let unit = size.width / 20
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: unit * 3.4)), with: .color(Color(white: 0.96)))
            context.fill(Path(ellipseIn: CGRect(x: unit, y: unit * 0.8, width: unit * 1.9, height: unit * 1.9)), with: .color(accent.opacity(0.8)))
            context.fill(Path(roundedRect: CGRect(x: unit * 3.5, y: unit * 1.3, width: unit * 7, height: unit * 0.9), cornerRadius: unit * 0.45), with: .color(Color(white: 0.7)))
            var y = unit * 4.6
            while y < size.height - unit * 4.2 {
                let isMine = random.next() < 0.4
                let width = size.width * (0.3 + random.next() * 0.42)
                let height = unit * (1.7 + Double(Int(random.next() * 3)) * 1.1)
                let x = isMine ? size.width - unit - width : unit
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: unit * 0.85),
                             with: .color(isMine ? accent : Color(white: 0.91)))
                y += height + unit * 0.7
            }
            context.fill(Path(roundedRect: CGRect(x: unit, y: size.height - unit * 2.6, width: size.width - unit * 2, height: unit * 1.7), cornerRadius: unit * 0.85),
                         with: .color(Color(white: 0.93)))
        }
    }
}

struct Landscape: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var random = DrawingRandom(seed)
            let skies: [[Color]] = [
                [Color(red: 0.99, green: 0.6, blue: 0.4), Color(red: 0.98, green: 0.84, blue: 0.62)],
                [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.75, green: 0.9, blue: 0.98)],
                [Color(red: 0.36, green: 0.27, blue: 0.62), Color(red: 0.96, green: 0.56, blue: 0.56)],
            ]
            let sky = skies[Int(seed) % skies.count]
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.7)))
            let sun = size.width * 0.16
            context.fill(Path(ellipseIn: CGRect(x: size.width * (0.2 + random.next() * 0.5), y: size.height * 0.2, width: sun, height: sun)),
                         with: .color(.white.opacity(0.85)))
            for (layer, shade) in [(0.62, 0.35), (0.72, 0.22)] {
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: size.height))
                for step in 0...6 {
                    let x = size.width * Double(step) / 6
                    let y = size.height * (layer - random.next() * 0.16)
                    ridge.addLine(to: CGPoint(x: x, y: y))
                }
                ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                ridge.closeSubpath()
                context.fill(ridge, with: .color(Color(red: 0.12, green: 0.22 + shade * 0.3, blue: 0.3).opacity(0.9)))
            }
            context.fill(Path(CGRect(x: 0, y: size.height * 0.82, width: size.width, height: size.height * 0.18)),
                         with: .linearGradient(Gradient(colors: [sky[0].opacity(0.8), Color(red: 0.1, green: 0.2, blue: 0.3)]),
                                               startPoint: CGPoint(x: 0, y: size.height * 0.82), endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}

private struct Receipt: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var random = DrawingRandom(seed)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.3, blue: 0.2), Color(red: 0.32, green: 0.2, blue: 0.13)]),
                                               startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(random.next() * 8 - 4))
            context.translateBy(x: -size.width / 2, y: -size.height / 2)
            let paper = CGRect(x: size.width * 0.17, y: size.height * 0.07, width: size.width * 0.66, height: size.height * 0.86)
            context.fill(Path(paper), with: .color(Color(white: 0.98)))
            let unit = paper.width / 16
            let ink = Color(white: 0.3)
            context.fill(Path(CGRect(x: paper.midX - unit * 4, y: paper.minY + unit * 1.5, width: unit * 8, height: unit)), with: .color(ink))
            var y = paper.minY + unit * 4
            while y < paper.maxY - unit * 7 {
                context.fill(Path(CGRect(x: paper.minX + unit, y: y, width: unit * (4 + random.next() * 5), height: unit * 0.5)), with: .color(ink.opacity(0.55)))
                context.fill(Path(CGRect(x: paper.maxX - unit * 4, y: y, width: unit * 3, height: unit * 0.5)), with: .color(ink.opacity(0.55)))
                y += unit * 1.3
            }
            context.fill(Path(CGRect(x: paper.minX + unit, y: paper.maxY - unit * 5.5, width: paper.width - unit * 2, height: unit * 0.9)), with: .color(ink))
            var x = paper.minX + unit * 2
            while x < paper.maxX - unit * 2 {
                let bar = unit * (0.15 + random.next() * 0.35)
                context.fill(Path(CGRect(x: x, y: paper.maxY - unit * 3.4, width: bar, height: unit * 2.2)), with: .color(.black))
                x += bar + unit * (0.15 + random.next() * 0.25)
            }
        }
    }
}

private struct QRSign: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var random = DrawingRandom(seed)
            let signs: [Color] = [
                Color(red: 0.85, green: 0.12, blue: 0.2), Color(red: 0.0, green: 0.45, blue: 0.85), Color(red: 0.0, green: 0.6, blue: 0.45),
            ]
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(signs[Int(seed) % signs.count]))
            let side = min(size.width, size.height) * 0.7
            let card = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            context.fill(Path(roundedRect: card, cornerRadius: side * 0.06), with: .color(.white))
            let modules = 21
            let cell = side * 0.84 / Double(modules)
            let origin = CGPoint(x: card.minX + side * 0.08, y: card.minY + side * 0.08)
            func fill(_ column: Int, _ row: Int) {
                context.fill(Path(CGRect(x: origin.x + Double(column) * cell, y: origin.y + Double(row) * cell, width: cell, height: cell)), with: .color(.black))
            }
            func isFinder(_ column: Int, _ row: Int) -> Bool {
                (column < 8 && row < 8) || (column >= modules - 8 && row < 8) || (column < 8 && row >= modules - 8)
            }
            for (column, row) in [(0, 0), (modules - 7, 0), (0, modules - 7)] {
                for dx in 0..<7 {
                    for dy in 0..<7 {
                        let ring = max(abs(dx - 3), abs(dy - 3))
                        if ring != 2 { fill(column + dx, row + dy) }
                    }
                }
            }
            for column in 0..<modules {
                for row in 0..<modules where !isFinder(column, row) && random.next() < 0.5 {
                    fill(column, row)
                }
            }
        }
    }
}

/// A frame of a video filmed at home: a birthday cake on the table, its
/// candles lit, balloons against the wall. The wall's colour, the balloons
/// and the candles change with `seed`.
private struct HomeVideo: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var random = DrawingRandom(seed)
            let walls: [[Color]] = [
                [Color(red: 0.98, green: 0.86, blue: 0.7), Color(red: 0.93, green: 0.72, blue: 0.55)],
                [Color(red: 0.8, green: 0.9, blue: 0.96), Color(red: 0.62, green: 0.78, blue: 0.9)],
                [Color(red: 0.94, green: 0.82, blue: 0.9), Color(red: 0.84, green: 0.66, blue: 0.8)],
            ]
            let wall = walls[Int(seed % UInt64(walls.count))]
            let tableTop = size.height * 0.68
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: tableTop)),
                         with: .linearGradient(Gradient(colors: wall), startPoint: .zero, endPoint: CGPoint(x: 0, y: tableTop)))
            context.fill(Path(CGRect(x: 0, y: tableTop, width: size.width, height: size.height - tableTop)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.22), Color(red: 0.36, green: 0.22, blue: 0.14)]),
                                               startPoint: CGPoint(x: 0, y: tableTop), endPoint: CGPoint(x: 0, y: size.height)))
            // Balloons, on their strings.
            let balloons: [Color] = [.red, .yellow, .blue, .pink, .orange, .purple]
            for index in 0..<3 {
                let width = size.width * 0.15
                let x = size.width * (0.12 + Double(index) * 0.32 + random.next() * 0.1)
                let balloon = CGRect(x: x - width / 2, y: size.height * (0.1 + random.next() * 0.12), width: width, height: width * 1.2)
                var string = Path()
                string.move(to: CGPoint(x: balloon.midX, y: balloon.maxY))
                string.addLine(to: CGPoint(x: balloon.midX + width * 0.2, y: tableTop))
                context.stroke(string, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
                let color = balloons[Int(random.next() * Double(balloons.count)) % balloons.count]
                context.fill(Path(ellipseIn: balloon), with: .color(color.opacity(0.85)))
            }
            // The cake, and its candles.
            let cake = CGRect(x: size.width * 0.3, y: tableTop - size.height * 0.16, width: size.width * 0.4, height: size.height * 0.2)
            context.fill(Path(roundedRect: cake, cornerRadius: cake.width * 0.08), with: .color(Color(red: 0.99, green: 0.95, blue: 0.9)))
            context.fill(Path(CGRect(x: cake.minX, y: cake.midY - cake.height * 0.08, width: cake.width, height: cake.height * 0.16)),
                         with: .color(Color(red: 0.93, green: 0.45, blue: 0.55)))
            let candles = 3 + Int(seed % 3)
            for index in 0..<candles {
                let x = cake.minX + cake.width * (Double(index) + 0.5) / Double(candles)
                let candle = CGRect(x: x - cake.width * 0.02, y: cake.minY - cake.height * 0.35, width: cake.width * 0.04, height: cake.height * 0.35)
                context.fill(Path(candle), with: .color(Color(red: 0.4, green: 0.7, blue: 0.95)))
                let flame = CGRect(
                    x: candle.midX - cake.width * 0.025, y: candle.minY - cake.height * 0.16, width: cake.width * 0.05, height: cake.height * 0.14
                )
                context.fill(Path(ellipseIn: flame), with: .color(Color(red: 1, green: 0.8, blue: 0.3)))
            }
        }
    }
}
