import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// A moment on Vietnam's clock, on 25/09/2026 plus `day` days.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: 9, day: 25 + day, hour: hour, minute: minute))!
}

private let morningEvening = Medication(
    id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000000A")!,
    name: "Thuốc A", dose: "1 viên", instructions: "",
    style: PillStyle(shape: .round, color: .white), times: [TimeOfDay(hour: 8), TimeOfDay(hour: 20)]
)
private let noon = Medication(
    id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000000B")!,
    name: "Thuốc B", dose: "", instructions: "",
    style: PillStyle(shape: .oval, color: .blue), times: [TimeOfDay(hour: 12)]
)
private let medications = [morningEvening, noon]

private func dose(_ medication: Medication, _ hour: Int, day: Int = 0) -> DoseID {
    DoseID(medicationID: medication.id, time: at(hour, day: day))
}

/// Yesterday's doses all taken: yesterday's 20:00 would otherwise still be
/// asked about until this morning's 08:00.
private func answeredYesterday() -> DoseLog {
    var log = DoseLog()
    for (medication, hour) in [(morningEvening, 8), (noon, 12), (morningEvening, 20)] {
        log.record(.taken, for: dose(medication, hour, day: -1), at: at(hour, 5, day: -1))
    }
    return log
}

@Suite("The parent's widget: what it shows, and when it changes")
struct DoseWidgetTests {
    @Test("Before the first dose: the next one, then what comes later today, and the day's count")
    func next() {
        let entry = DoseWidgetTimeline.entry(at: at(7), medications: medications, log: answeredYesterday(), calendar: vietnam)
        #expect(entry.dose?.id == dose(morningEvening, 8))
        guard case .next = entry.headline else {
            Issue.record("expected the next dose, got \(entry.headline)")
            return
        }
        #expect(entry.laterToday.map(\.id) == [dose(noon, 12), dose(morningEvening, 20)])
        #expect(entry.alsoWaiting == 0)
        #expect((entry.taken, entry.total) == (0, 3))
    }

    @Test("A dose waiting: due within its grace, late after; the earliest first, the others counted; yesterday's evening dose until the morning's")
    func waiting() {
        // Yesterday's 20:00 never answered: still asked about at 07:00.
        let early = DoseWidgetTimeline.entry(at: at(7), medications: medications, log: DoseLog(), calendar: vietnam)
        #expect(early.headline == .late(DoseSchedule.doses(of: medications, onDayOf: at(8, day: -1), calendar: vietnam)[2]))
        #expect(DoseWidgetCopy.time(for: early, calendar: vietnam) == "20:00 hôm qua")
        let due = DoseWidgetTimeline.entry(at: at(8, 10), medications: medications, log: DoseLog(), calendar: vietnam)
        #expect(due.headline == .due(DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)[0]))
        let late = DoseWidgetTimeline.entry(at: at(12, 5), medications: medications, log: DoseLog(), calendar: vietnam)
        guard case let .late(first) = late.headline else {
            Issue.record("expected a late dose, got \(late.headline)")
            return
        }
        #expect(first.id == dose(morningEvening, 8))
        #expect(late.alsoWaiting == 1)
        #expect(late.laterToday.map(\.id) == [dose(morningEvening, 20)])
    }

    @Test("Everything answered: how the day went, and tomorrow's first dose")
    func dayOver() {
        var log = answeredYesterday()
        log.record(.taken, for: dose(morningEvening, 8), at: at(8, 5))
        log.record(.taken, for: dose(noon, 12), at: at(12, 1))
        log.record(.taken, for: dose(morningEvening, 20), at: at(20, 2))
        let entry = DoseWidgetTimeline.entry(at: at(21), medications: medications, log: log, calendar: vietnam)
        #expect(entry.headline == .dayOver(tomorrow: DoseSchedule.doses(of: medications, onDayOf: at(8, day: 1), calendar: vietnam)[0]))
        #expect((entry.taken, entry.total) == (3, 3))
        #expect(DoseWidgetCopy.title(for: entry) == "Đã uống đủ hôm nay")
        #expect(DoseWidgetCopy.time(for: entry, calendar: vietnam) == "Mai 08:00")
        // One skipped: the day is over, but not every dose was taken.
        log.record(.skipped, for: dose(noon, 12), at: at(20, 30))
        let skipped = DoseWidgetTimeline.entry(at: at(21), medications: medications, log: log, calendar: vietnam)
        #expect(DoseWidgetCopy.title(for: skipped) == "Hôm nay đã uống 2/3 liều")
        #expect(DoseWidgetCopy.inline(for: skipped, calendar: vietnam) == "Hôm nay 2/3 liều")
    }

    @Test("No medicine: said once, for the whole timeline; a stopped one is still a medicine, with no dose today")
    func noMedicines() {
        let entries = DoseWidgetTimeline.entries(from: at(9), medications: [], log: DoseLog(), calendar: vietnam)
        #expect(entries.count == 1)
        #expect(entries.first?.headline == .noMedicines)
        #expect(entries.first.map(DoseWidgetCopy.title) == "Chưa có thuốc nào")
        var stopped = morningEvening
        stopped.stoppedAt = at(9, day: -3)
        let none = DoseWidgetTimeline.entries(from: at(9), medications: [stopped], log: DoseLog(), calendar: vietnam)
        #expect(none.count == 1)
        #expect(none.first?.headline == .dayOver(tomorrow: nil))
        #expect(none.first.map(DoseWidgetCopy.title) == "Hôm nay không có liều nào")
        #expect(none.first.map { DoseWidgetCopy.inline(for: $0, calendar: vietnam) } == "Hôm nay không có thuốc")
        #expect(none.first.flatMap { DoseWidgetCopy.time(for: $0, calendar: vietnam) } == nil)
        // Starting tomorrow: nothing today, tomorrow's first dose.
        var starting = noon
        starting.startDate = at(0, day: 1)
        let waiting = DoseWidgetTimeline.entry(at: at(9), medications: [starting], log: DoseLog(), calendar: vietnam)
        #expect(waiting.headline == .dayOver(tomorrow: DoseSchedule.doses(of: [starting], onDayOf: at(12, day: 1), calendar: vietnam)[0]))
        #expect(DoseWidgetCopy.time(for: waiting, calendar: vietnam) == "Mai 12:00")
        #expect(DoseWidgetCopy.inline(for: waiting, calendar: vietnam) == "Thuốc mai lúc 12:00")
    }

    @Test("The timeline: an entry at each moment that changes the widget, none for those that do not, until tomorrow ends")
    func timeline() {
        var log = answeredYesterday()
        log.record(.taken, for: dose(morningEvening, 8), at: at(8, 5))
        let entries = DoseWidgetTimeline.entries(from: at(8, 10), medications: medications, log: log, calendar: vietnam)
        let dates = entries.map(\.date)
        #expect(dates.first == at(8, 10))
        #expect(dates == dates.sorted())
        // Until tomorrow ends, when WidgetKit asks for the next ones.
        #expect(DoseWidgetTimeline.end(from: at(8, 10), calendar: vietnam) == at(0, day: 2))
        #expect(DoseWidgetTimeline.end(from: at(23, 59), calendar: vietnam) == at(0, day: 2))
        #expect(dates.last.map { $0 < at(0, day: 2) } == true)
        for (earlier, later) in zip(entries, entries.dropFirst()) {
            #expect(!earlier.showsSame(as: later), "\(later.date) repeats \(earlier.date)")
        }
        // 08:00 answered: its grace ending at 08:30 changes nothing. B falls
        // due at noon and turns late at 12:30; at 20:00 A's evening dose
        // waits too, and its own grace ending changes nothing shown.
        let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
        #expect(dates.filter { $0 < at(0, day: 1) } == [at(8, 10), at(12), at(12, 30), at(20)])
        #expect(entries[0].headline == .next(today[1]))
        #expect(entries[1].headline == .due(today[1]))
        #expect(entries[2].headline == .late(today[1]))
        #expect(entries[3].headline == .late(today[1]))
        #expect(entries[3].alsoWaiting == 1)
        #expect(entries[3].laterToday.isEmpty)
        // Midnight: the count starts over, and yesterday's 20:00 is still asked about.
        let midnight = entries.first { $0.date == at(0, day: 1) }
        #expect(midnight?.taken == 0)
        #expect(midnight?.total == 3)
        #expect(midnight?.dose?.id == dose(morningEvening, 20))
        #expect(midnight.flatMap { DoseWidgetCopy.time(for: $0, calendar: vietnam) } == "20:00 hôm qua")
        // Tomorrow 08:00: yesterday's 20:00 stops waiting as the next dose falls due.
        let tomorrow = DoseSchedule.doses(of: medications, onDayOf: at(8, day: 1), calendar: vietnam)
        #expect(entries.first { $0.date == at(8, day: 1) }?.headline == .due(tomorrow[0]))
    }

    @Test("Once a day in the evening: last night's dose is asked about until 12 hours on, then the widget moves on by itself")
    func eveningOnly() {
        let evening = Medication(
            id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000000C")!,
            name: "Thuốc C", dose: "1 viên", instructions: "",
            style: PillStyle(shape: .oblong, color: .yellow), times: [TimeOfDay(hour: 21)]
        )
        let entries = DoseWidgetTimeline.entries(from: at(7), medications: [evening], log: DoseLog(), calendar: vietnam)
        // No dose of the day falls at 09:00: last night's stops waiting then.
        #expect(entries.map(\.date) == [at(7), at(9), at(21), at(21, 30), at(0, day: 1), at(9, day: 1), at(21, day: 1), at(21, 30, day: 1)])
        #expect(entries.first?.dose?.id == dose(evening, 21, day: -1))
        #expect(entries.dropFirst().first?.headline == .next(DoseSchedule.doses(of: [evening], onDayOf: at(21), calendar: vietnam)[0]))
    }

    @Test("Every dose taken: the widget says so until midnight, then shows the new day's first")
    func midnight() {
        var log = DoseLog()
        log.record(.taken, for: dose(morningEvening, 8), at: at(8, 5))
        log.record(.taken, for: dose(morningEvening, 20), at: at(20, 5))
        let entries = DoseWidgetTimeline.entries(from: at(21), medications: [morningEvening], log: log, calendar: vietnam)
        #expect(entries.map(\.date) == [at(21), at(0, day: 1), at(8, day: 1), at(8, 30, day: 1), at(20, day: 1), at(20, 30, day: 1)])
        #expect(entries.first.map(DoseWidgetCopy.title) == "Đã uống đủ hôm nay")
        let tomorrow = DoseSchedule.doses(of: [morningEvening], onDayOf: at(8, day: 1), calendar: vietnam)
        #expect(entries.dropFirst().first?.headline == .next(tomorrow[0]))
        #expect(entries.dropFirst().first.flatMap { DoseWidgetCopy.progress(for: $0) } == "Hôm nay 0/2 liều")
    }

    @Test("The snapshot the app shares: read back as saved, on the parent's clock, without answers older than yesterday's; saved again only when it changed")
    func store() throws {
        let suite = "DoseWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DoseWidgetStore(defaults: defaults)
        #expect(store.snapshot == nil)
        var log = answeredYesterday()
        log.record(.taken, for: dose(morningEvening, 8), at: at(8, 5))
        let snapshot = DoseWidgetSnapshot(medications: medications, log: log, timeZone: vietnam.timeZone, now: at(9))
        #expect(store.save(snapshot))
        #expect(!store.save(snapshot))
        #expect(DoseWidgetStore(defaults: defaults).snapshot == snapshot)
        #expect(snapshot.calendar.timeZone == vietnam.timeZone)
        #expect(snapshot.log == log)
        #expect(snapshot.entries(from: at(9)) == DoseWidgetTimeline.entries(from: at(9), medications: medications, log: log, calendar: vietnam))
        #expect(snapshot.timelineEnd(from: at(9)) == at(0, day: 2))
        // The day before yesterday's answers are left out, yesterday's kept.
        var older = log
        older.record(.skipped, for: dose(morningEvening, 20, day: -2), at: at(20, 10, day: -2))
        let shared = DoseWidgetSnapshot(medications: medications, log: older, timeZone: vietnam.timeZone, now: at(9))
        #expect(shared == snapshot)
        #expect(shared.log[dose(morningEvening, 20, day: -2)] == nil)
        #expect(shared.log[dose(morningEvening, 20, day: -1)]?.outcome == .taken)
        log.record(.taken, for: dose(noon, 12), at: at(12, 3))
        #expect(store.save(DoseWidgetSnapshot(medications: medications, log: log, timeZone: vietnam.timeZone, now: at(12, 3))))
        // No App Group: nothing is shared.
        #expect(!DoseWidgetStore(defaults: nil).save(snapshot))
        #expect(DoseWidgetStore(defaults: nil).snapshot == nil)
    }

    @Test("The widget's buttons: ĐÃ UỐNG for a dose waiting, none for one not due yet or a day done, Hoàn tác for one just taken on the widget")
    func buttons() {
        let next = DoseWidgetTimeline.entry(at: at(7), medications: medications, log: answeredYesterday(), calendar: vietnam)
        #expect(next.answer == nil)
        let due = DoseWidgetTimeline.entry(at: at(8, 10), medications: medications, log: answeredYesterday(), calendar: vietnam)
        let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
        #expect(due.answer == .take(today[0]))
        #expect(due.answer?.outcome == .taken)
        let late = DoseWidgetTimeline.entry(at: at(9), medications: medications, log: answeredYesterday(), calendar: vietnam)
        #expect(late.answer == .take(today[0]))
        var log = answeredYesterday()
        log.record(.taken, for: today[0].id, at: at(8, 20))
        let answer = log.storedRecord(for: today[0].id)
        let taken = DoseWidgetTimeline.entry(at: at(8, 22), medications: medications, log: log, calendar: vietnam, answered: answer)
        #expect(taken.answered == DoseWidgetEntry.Answered(dose: today[0], at: at(8, 20)))
        #expect(taken.answer == .undo(today[0]))
        #expect(taken.answer?.outcome == .cleared)
        #expect(taken.headline == .next(today[1]))
        // Five minutes on, the widget moves on.
        let later = DoseWidgetTimeline.entry(at: at(8, 25), medications: medications, log: log, calendar: vietnam, answered: answer)
        #expect(later.answered == nil)
        #expect(later.answer == nil)
    }

    @Test("Answered on the widget: kept apart for the app, shown at once for five minutes with Hoàn tác, undone, stamped after the log, dropped after a day")
    func answersOnTheWidget() throws {
        let suite = "DoseWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DoseWidgetStore(defaults: defaults)
        let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
        // Nothing shared yet: nothing to answer.
        #expect(store.record(.taken, for: today[0].id, at: at(8, 20)) == nil)
        #expect(store.answers.isEmpty)
        store.save(DoseWidgetSnapshot(medications: medications, log: answeredYesterday(), timeZone: vietnam.timeZone, now: at(8)))
        let log = try #require(store.record(.taken, for: today[0].id, at: at(8, 20)))
        #expect(log[today[0].id]?.outcome == .taken)
        #expect(store.answers.map(\.dose) == [today[0].id])
        #expect(store.log == log)
        let entries = try #require(store.entries(from: at(8, 20)))
        #expect(entries.first?.answered?.dose == today[0])
        #expect(entries.first?.answer == .undo(today[0]))
        // The answer shows until 08:25, then the widget moves on.
        #expect(entries.map(\.date).prefix(3) == [at(8, 20), at(8, 25), at(12)])
        #expect(entries.dropFirst().first?.answered == nil)
        #expect(entries.dropFirst().first?.headline == .next(today[1]))
        // Hoàn tác: the dose is asked about again.
        store.record(.cleared, for: today[0].id, at: at(8, 21))
        #expect(store.answers.map(\.outcome) == [.cleared])
        let undone = try #require(store.entries(from: at(8, 21))?.first)
        #expect(undone.answered == nil)
        #expect(undone.answer == .take(today[0]))
        // The app took the answer and changed it since: the app's shows.
        var app = answeredYesterday()
        store.answers.forEach { app.merge($0) }
        store.record(.taken, for: today[0].id, at: at(8, 22))
        store.answers.forEach { app.merge($0) }
        app.record(.skipped, for: today[0].id, at: at(8, 23))
        store.save(DoseWidgetSnapshot(medications: medications, log: app, timeZone: vietnam.timeZone, now: at(8, 23)))
        let changed = try #require(store.entries(from: at(8, 23))?.first)
        #expect(changed.answered == nil)
        #expect(store.log?[today[0].id]?.outcome == .skipped)
        // A clock behind the log's answer: the widget's is stamped after it.
        let behind = try #require(store.record(.taken, for: today[0].id, at: at(8, 10)))
        #expect(behind[today[0].id]?.outcome == .taken)
        // A day on, yesterday's answers go; the day before's are dropped.
        let tomorrow = DoseSchedule.doses(of: medications, onDayOf: at(8, day: 2), calendar: vietnam)
        store.record(.taken, for: tomorrow[0].id, at: at(8, 5, day: 2))
        #expect(store.answers.map(\.dose) == [tomorrow[0].id])
        // No App Group: nothing is recorded.
        #expect(DoseWidgetStore(defaults: nil).record(.taken, for: today[0].id, at: at(8)) == nil)
    }

    @Test("Two doses answered on the widget: the latest shows")
    func latestAnswer() throws {
        let suite = "DoseWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DoseWidgetStore(defaults: defaults)
        store.save(DoseWidgetSnapshot(medications: medications, log: answeredYesterday(), timeZone: vietnam.timeZone, now: at(12)))
        let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
        store.record(.taken, for: today[1].id, at: at(12, 10))
        store.record(.taken, for: today[0].id, at: at(12, 11))
        #expect(store.answers.map(\.dose) == [today[0].id, today[1].id])
        #expect(try #require(store.entries(from: at(12, 12))).first?.answered?.dose == today[0])
    }

    @Test("The words: the dose and how much, what waits besides, the day's count, one line for the locked screen, and the sentences VoiceOver reads")
    func copy() {
        let late = DoseWidgetTimeline.entry(at: at(12, 5), medications: medications, log: DoseLog(), calendar: vietnam)
        #expect(DoseWidgetCopy.title(for: late) == "Chưa uống thuốc")
        #expect(DoseWidgetCopy.time(for: late, calendar: vietnam) == "08:00")
        #expect(late.dose.map(DoseWidgetCopy.medicine) == "Thuốc A · 1 viên")
        #expect(DoseWidgetCopy.alsoWaiting(for: late) == "+1 liều khác chưa uống")
        #expect(DoseWidgetCopy.progress(for: late) == "Hôm nay 0/3 liều")
        #expect(DoseWidgetCopy.inline(for: late, calendar: vietnam) == "Chưa uống thuốc 08:00")
        #expect(
            DoseWidgetCopy.spoken(for: late, calendar: vietnam)
                == "Chưa uống thuốc, 08:00: Thuốc A, 1 viên. Còn 1 liều khác chưa uống. Hôm nay đã uống 0 trong 3 liều."
        )
        // No amount written: the name alone.
        let noonDue = DoseWidgetTimeline.entry(at: at(12, 5), medications: [noon], log: DoseLog(), calendar: vietnam)
        #expect(noonDue.dose.map(DoseWidgetCopy.medicine) == "Thuốc B")
        #expect(DoseWidgetCopy.title(for: noonDue) == "Đến giờ uống thuốc")
        #expect(DoseWidgetCopy.inline(for: noonDue, calendar: vietnam) == "Uống thuốc 12:00")
        #expect(DoseWidgetCopy.alsoWaiting(for: noonDue) == nil)
        let next = DoseWidgetTimeline.entry(at: at(7), medications: medications, log: answeredYesterday(), calendar: vietnam)
        #expect(DoseWidgetCopy.title(for: next) == "Liều tiếp theo")
        #expect(DoseWidgetCopy.inline(for: next, calendar: vietnam) == "Thuốc lúc 08:00")
        // The day over, every dose taken.
        var log = DoseLog()
        for (medication, hour) in [(morningEvening, 8), (noon, 12), (morningEvening, 20)] {
            log.record(.taken, for: dose(medication, hour), at: at(hour, 5))
        }
        let over = DoseWidgetTimeline.entry(at: at(21), medications: medications, log: log, calendar: vietnam)
        #expect(DoseWidgetCopy.inline(for: over, calendar: vietnam) == "Đã uống đủ thuốc")
        #expect(DoseWidgetCopy.spoken(for: over, calendar: vietnam) == "Đã uống đủ hôm nay. Ngày mai, 08:00: Thuốc A, 1 viên.")
        #expect(DoseWidgetCopy.progress(for: over) == "Hôm nay 3/3 liều")
        // The buttons, and a dose just taken on the widget.
        let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
        #expect(DoseWidgetCopy.title(for: .take(today[0])) == "ĐÃ UỐNG")
        #expect(DoseWidgetCopy.title(for: .undo(today[0])) == "Hoàn tác")
        #expect(DoseWidgetCopy.spoken(for: .take(today[0]), on: at(8, 20), calendar: vietnam) == "Đã uống Thuốc A, liều 08:00")
        #expect(DoseWidgetCopy.spoken(for: .undo(today[0]), on: at(8, 20), calendar: vietnam) == "Hoàn tác, Thuốc A liều 08:00 chưa uống")
        let yesterdays = DoseSchedule.doses(of: medications, onDayOf: at(20, day: -1), calendar: vietnam)[2]
        #expect(DoseWidgetCopy.spoken(for: .take(yesterdays), on: at(7), calendar: vietnam) == "Đã uống Thuốc A, liều 20:00 hôm qua")
        var widgetLog = answeredYesterday()
        widgetLog.record(.taken, for: today[0].id, at: at(8, 20))
        let taken = DoseWidgetTimeline.entry(
            at: at(8, 21), medications: medications, log: widgetLog, calendar: vietnam, answered: widgetLog.storedRecord(for: today[0].id)
        )
        #expect(DoseWidgetCopy.spoken(for: taken, calendar: vietnam) == "Đã uống Thuốc A, 1 viên, liều 08:00. Hôm nay đã uống 1 trong 3 liều.")
        #expect(
            DoseWidgetCopy.spoken(for: taken, calendar: vietnam, showingAnswered: false)
                == "Liều tiếp theo, 12:00: Thuốc B. Hôm nay đã uống 1 trong 3 liều."
        )
        #expect(DoseWidgetCopy.alsoWaiting(for: taken) == nil)
        // Taken on the widget while another dose waits: that one is counted.
        var twoWaiting = answeredYesterday()
        twoWaiting.record(.taken, for: today[0].id, at: at(12, 5))
        let one = DoseWidgetTimeline.entry(
            at: at(12, 6), medications: medications, log: twoWaiting, calendar: vietnam, answered: twoWaiting.storedRecord(for: today[0].id)
        )
        #expect(one.headline == .due(today[1]))
        #expect(DoseWidgetCopy.alsoWaiting(for: one) == "+1 liều khác chưa uống")
        #expect(
            DoseWidgetCopy.spoken(for: one, calendar: vietnam)
                == "Đã uống Thuốc A, 1 viên, liều 08:00. Còn 1 liều khác chưa uống. Hôm nay đã uống 1 trong 3 liều."
        )
    }
}
