import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// A moment on Vietnam's clock, on 25/09/2026 plus `day` days.
private func at(_ hour: Int, day: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: 9, day: 25 + day, hour: hour))!
}

@Suite("Asking for an App Store rating: after use, never in the first days, not twice for a version, two weeks apart")
struct ReviewPromptTests {
    @Test("Not in the first days, however much the app is used; then after four tasks on two days")
    func firstUse() {
        var prompt = ReviewPrompt(firstUse: at(9))
        for hour in 10...16 {
            prompt.completedTask(at: at(hour), calendar: vietnam)
        }
        // Seven tasks, one day: a busy first day is no habit yet.
        #expect(!prompt.shouldAsk(at: at(17), version: "1.0", calendar: vietnam))
        #expect(!prompt.shouldAsk(at: at(17, day: 5), version: "1.0", calendar: vietnam))
        prompt.completedTask(at: at(9, day: 1), calendar: vietnam)
        // Two days now, but the app is only a day old.
        #expect(!prompt.shouldAsk(at: at(10, day: 1), version: "1.0", calendar: vietnam))
        #expect(!prompt.shouldAsk(at: at(8, day: 3), version: "1.0", calendar: vietnam))
        #expect(prompt.shouldAsk(at: at(9, day: 3), version: "1.0", calendar: vietnam))
        // Three tasks on two days: not yet.
        var few = ReviewPrompt(firstUse: at(9))
        few.completedTask(at: at(10), calendar: vietnam)
        few.completedTask(at: at(10, day: 1), calendar: vietnam)
        few.completedTask(at: at(10, day: 2), calendar: vietnam)
        #expect(!few.shouldAsk(at: at(10, day: 9), version: "1.0", calendar: vietnam))
        few.completedTask(at: at(11, day: 2), calendar: vietnam)
        #expect(few.shouldAsk(at: at(10, day: 9), version: "1.0", calendar: vietnam))
        // A clock set before the first use asks nothing.
        #expect(!few.shouldAsk(at: at(9, day: -1), version: "1.0", calendar: vietnam))
    }

    @Test("Asked: never again for that version; for the next, after two weeks and more use")
    func afterAsking() {
        var prompt = ReviewPrompt(firstUse: at(9))
        for day in 0..<4 {
            prompt.completedTask(at: at(10, day: day), calendar: vietnam)
        }
        #expect(prompt.shouldAsk(at: at(10, day: 4), version: "1.0", calendar: vietnam))
        prompt.asked(at: at(10, day: 4), version: "1.0")
        #expect(prompt.tasks == 0)
        #expect(prompt.days.isEmpty)
        for day in 5..<30 {
            prompt.completedTask(at: at(10, day: day), calendar: vietnam)
        }
        #expect(!prompt.shouldAsk(at: at(10, day: 30), version: "1.0", calendar: vietnam))
        // A new version, but only 13 days on.
        #expect(!prompt.shouldAsk(at: at(9, day: 18), version: "1.1", calendar: vietnam))
        #expect(prompt.shouldAsk(at: at(10, day: 18), version: "1.1", calendar: vietnam))
        // A new version and time enough, but no use since: not yet.
        var idle = prompt
        idle.asked(at: at(10, day: 30), version: "1.1")
        #expect(!idle.shouldAsk(at: at(10, day: 90), version: "1.2", calendar: vietnam))
    }

    @Test("Kept in the app's defaults; a disabled store keeps nothing and never asks")
    func store() throws {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = ReviewPromptStore(suite: suite)
        #expect(store.prompt(at: at(9)) == ReviewPrompt(firstUse: at(9)))
        store.completedTask(at: at(9), calendar: vietnam)
        // The first use is the first kept, not the moment asked about later.
        #expect(store.prompt(at: at(12, day: 4)).firstUse == at(9))
        for day in 1...3 {
            store.completedTask(at: at(10, day: day), calendar: vietnam)
        }
        #expect(store.prompt(at: at(12, day: 4)).tasks == 4)
        #expect(store.shouldAsk(at: at(12, day: 4), version: "1.0", calendar: vietnam))
        store.asked(at: at(12, day: 4), version: "1.0")
        #expect(!store.shouldAsk(at: at(12, day: 4), version: "1.0", calendar: vietnam))
        #expect(ReviewPromptStore(suite: suite).prompt(at: at(12, day: 4)).lastAskedVersion == "1.0")
        let off = ReviewPromptStore(suite: suite, enabled: false)
        for day in 20...30 {
            off.completedTask(at: at(10, day: day), calendar: vietnam)
        }
        #expect(!off.shouldAsk(at: at(10, day: 40), version: "2.0", calendar: vietnam))
        #expect(store.prompt(at: at(10, day: 40)).tasks == 0)
        // Not even under rules that ask for nothing, which the kept prompt meets.
        let anytime = ReviewPrompt.Rules(tasks: 0, days: 0, sinceFirstUse: 0, spacing: 0)
        #expect(store.shouldAsk(at: at(10, day: 40), version: "2.0", calendar: vietnam, rules: anytime))
        #expect(!off.shouldAsk(at: at(10, day: 40), version: "2.0", calendar: vietnam, rules: anytime))
    }

    @Test("Tasks done at once all count, and of screens at rest at once, one asks")
    func atOnce() async {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        await withTaskGroup(of: Void.self) { group in
            for task in 0..<400 {
                group.addTask {
                    // A store each, on the same defaults, as the parts of an app make them.
                    ReviewPromptStore(suite: suite).completedTask(at: at(9, day: task % 4), calendar: vietnam)
                }
            }
        }
        let store = ReviewPromptStore(suite: suite)
        #expect(store.prompt(at: at(9)).tasks == 400)
        let asks = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask { ReviewPromptStore(suite: suite).askIfDue(at: at(12, day: 10), version: "1.0", calendar: vietnam) }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(asks == 1)
        #expect(store.prompt(at: at(9)).lastAskedVersion == "1.0")
        #expect(store.prompt(at: at(9)).tasks == 0)
        #expect(!ReviewPromptStore(suite: suite, enabled: false).askIfDue(at: at(12, day: 40), version: "2.0", calendar: vietnam))
    }

    @Test("A Settings row's link to write a review, for an App Store id")
    func writeReviewLink() {
        #expect(StoreLinks.writeReview(appID: "6450000001")?.absoluteString == "https://apps.apple.com/app/id6450000001?action=write-review")
        #expect(StoreLinks.writeReview(appID: "") == nil)
        #expect(StoreLinks.writeReview(appID: "id6450000001") == nil)
        #expect(StoreLinks.writeReview(appID: "٦٤٥") == nil)
    }
}
