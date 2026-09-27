@testable import IdeaLabCore
import Testing

/// A store whose reads take as long as the test says: each waits until
/// `finishRead()`, then shows what it saw when it started.
@MainActor
private final class SlowStore {
    var truth = 0
    private(set) var shown: Int?
    private(set) var started = 0
    private(set) var underWay = 0
    private(set) var mostAtOnce = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Whether reads wait for `finishRead()`.
    private var holding = true

    func read() async {
        started += 1
        underWay += 1
        mostAtOnce = max(mostAtOnce, underWay)
        let seen = truth
        if holding {
            await withCheckedContinuation { waiting.append($0) }
        }
        shown = seen
        underWay -= 1
    }

    var readWaiting: Bool { !waiting.isEmpty }

    /// Lets the oldest read waiting finish.
    func finishRead() {
        guard !waiting.isEmpty else {
            Issue.record("No read was waiting")
            return
        }
        waiting.removeFirst().resume()
    }

    /// Lets every read finish, waiting or to come, so a test that failed
    /// does not wait forever on a read it did not expect.
    func release() {
        holding = false
        while !waiting.isEmpty {
            waiting.removeFirst().resume()
        }
    }
}

/// Lets the other tasks run until `condition` holds.
@MainActor
private func settle(until condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() {
        await Task.yield()
    }
}

/// Lets the other tasks run for a while.
@MainActor
private func settle() async {
    for _ in 0..<100 {
        await Task.yield()
    }
}

@Suite("One read at a time", .timeLimit(.minutes(1)))
@MainActor
struct SerialRefreshTests {
    @Test("A newer read never lands before an older one, which would leave what the older saw")
    func olderNeverLast() async {
        let refresh = SerialRefresh()
        let store = SlowStore()
        store.truth = 1
        let first = Task { await refresh.run(store.read) }
        await settle { store.readWaiting }
        store.truth = 2
        let second = Task { await refresh.run(store.read) }
        await settle()
        // The second waits for the first read to finish before it starts its own.
        #expect(store.started == 1)
        store.finishRead()
        await first.value
        #expect(store.shown == 1)
        await settle { store.readWaiting }
        #expect(store.started == 2)
        store.finishRead()
        await settle()
        #expect(store.shown == 2)
        #expect(store.mostAtOnce == 1)
        store.release()
        await second.value
    }

    @Test("A call returns only after a read that started after it")
    func returnsAfterItsOwnRead() async {
        let refresh = SerialRefresh()
        let store = SlowStore()
        let first = Task { await refresh.run(store.read) }
        await settle { store.readWaiting }
        var secondReturned = false
        let second = Task {
            await refresh.run(store.read)
            secondReturned = true
        }
        await settle()
        store.finishRead()
        await first.value
        await settle { store.readWaiting }
        // The read it was waiting on is over, but it started before the call.
        #expect(store.started == 2)
        #expect(!secondReturned)
        store.release()
        await second.value
        #expect(secondReturned)
    }

    @Test("Calls made during a read share the next one")
    func callsShareTheNextRead() async {
        let refresh = SerialRefresh()
        let store = SlowStore()
        let first = Task { await refresh.run(store.read) }
        await settle { store.readWaiting }
        let others = (0..<3).map { _ in Task { await refresh.run(store.read) } }
        await settle()
        store.finishRead()
        await first.value
        await settle { store.readWaiting }
        store.finishRead()
        await settle()
        #expect(store.started == 2)
        #expect(store.mostAtOnce == 1)
        store.release()
        for other in others {
            await other.value
        }
    }

    @Test("With no read under way, a call reads at once")
    func readsAtOnce() async {
        let refresh = SerialRefresh()
        let store = SlowStore()
        store.truth = 7
        let call = Task { await refresh.run(store.read) }
        await settle { store.readWaiting }
        #expect(store.started == 1)
        store.finishRead()
        await call.value
        #expect(store.shown == 7)
        // And again, later: a read of its own.
        store.truth = 8
        let again = Task { await refresh.run(store.read) }
        await settle { store.readWaiting }
        store.finishRead()
        await again.value
        #expect(store.started == 2)
        #expect(store.shown == 8)
    }
}
