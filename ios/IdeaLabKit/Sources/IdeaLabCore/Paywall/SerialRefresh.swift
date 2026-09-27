import Foundation

/// Reads of state kept somewhere slow, one at a time: `LabStore` asks
/// StoreKit what the customer owns and has after each purchase, restore,
/// transaction and change of subscription, and each read waits on StoreKit
/// several times. Two reads under way together could finish in any order,
/// the older one last, leaving what it saw.
///
/// `run(_:)` returns once a read that started after the call has finished,
/// so what the caller sees is at least as new as the call. Calls made while
/// a read is under way share the next one.
@MainActor
public final class SerialRefresh {
    /// Reads asked for, and how many of them the reads finished so far
    /// cover: a read covers the calls made before it started.
    private var asked = 0
    private var done = 0
    /// The read under way, if any.
    private var reading: Task<Void, Never>?

    public nonisolated init() {}

    /// Runs `read`, after the read under way if there is one, and returns
    /// once a read that started after this call has finished: this one, or
    /// that of another call made at the same time.
    public func run(_ read: @escaping @MainActor () async -> Void) async {
        asked += 1
        let call = asked
        while done < call {
            if let reading {
                await reading.value
                continue
            }
            let covers = asked
            let next = Task { @MainActor in
                await read()
                self.done = covers
                self.reading = nil
            }
            reading = next
            await next.value
        }
    }
}
