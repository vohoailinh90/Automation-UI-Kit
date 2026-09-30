import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// A moment on Vietnam's clock, on 25/09/2026 plus `day` days.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: 9, day: 25 + day, hour: hour, minute: minute))!
}

private let morningEvening = Medication(
    id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000001A")!,
    name: "Thuốc huyết áp", dose: "1 viên", instructions: "",
    style: PillStyle(shape: .round, color: .white), times: [TimeOfDay(hour: 8), TimeOfDay(hour: 20)]
)
private let noon = Medication(
    id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000001B")!,
    name: "Thuốc tiểu đường", dose: "", instructions: "",
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

private func entry(at date: Date, log: DoseLog, updatedAt: Date? = nil, medications: [Medication] = medications) -> CaregiverWidgetEntry {
    CaregiverWidgetTimeline.entry(
        at: date, personName: "Mẹ", medications: medications, log: log, updatedAt: updatedAt, calendar: vietnam
    )
}

@Suite("The family's widget: the parent's doses so far, the late ones, and how fresh the news is")
struct CaregiverWidgetTests {
    @Test("Before the first dose, then a dose due (not late yet), then taken: counted as the family's screen counts")
    func soFar() {
        let early = entry(at: at(7), log: answeredYesterday())
        #expect((early.soFar, early.taken, early.late) == (0, 0, []))
        #expect(!early.allTaken)
        #expect(CaregiverWidgetCopy.title(for: early, calendar: vietnam) == "Chưa đến giờ uống thuốc")
        #expect(CaregiverWidgetCopy.inline(for: early, calendar: vietnam) == "Mẹ chưa đến giờ uống thuốc")
        let due = entry(at: at(8, 10), log: answeredYesterday())
        #expect((due.soFar, due.taken, due.late) == (1, 0, []))
        #expect(CaregiverWidgetCopy.title(for: due, calendar: vietnam) == "Đã uống 0/1 liều")
        var log = answeredYesterday()
        log.record(.taken, for: dose(morningEvening, 8), at: at(8, 5))
        let noonDue = entry(at: at(12, 5), log: log)
        #expect((noonDue.soFar, noonDue.taken, noonDue.late) == (2, 1, []))
        #expect(!noonDue.allTaken)
        #expect(CaregiverWidgetCopy.inline(for: noonDue, calendar: vietnam) == "Mẹ đã uống 1/2 liều")
        log.record(.taken, for: dose(noon, 12), at: at(12, 20))
        log.record(.taken, for: dose(morningEvening, 20), at: at(20, 1))
        let evening = entry(at: at(21), log: log)
        #expect((evening.soFar, evening.taken) == (3, 3))
        #expect(evening.allTaken)
        #expect(CaregiverWidgetCopy.title(for: evening, calendar: vietnam) == "Đã uống 3/3 liều")
        #expect(CaregiverWidgetCopy.spoken(for: evening, calendar: vietnam) == "Mẹ đã uống 3 trong 3 liều đến giờ.")
    }

    @Test("Late: the earliest named by its time, the others counted, the medicines only in what VoiceOver reads on the Home Screen")
    func late() {
        let log = answeredYesterday()
        let one = entry(at: at(8, 30), log: log, updatedAt: at(8, 20))
        #expect(one.late.map(\.id) == [dose(morningEvening, 8)])
        #expect(CaregiverWidgetCopy.title(for: one, calendar: vietnam) == "08:00 chưa xác nhận")
        #expect(CaregiverWidgetCopy.moreLate(for: one) == nil)
        #expect(CaregiverWidgetCopy.inline(for: one, calendar: vietnam) == "Mẹ: 08:00 chưa xác nhận")
        #expect(CaregiverWidgetCopy.spoken(for: one, calendar: vietnam)
            == "Mẹ chưa xác nhận Thuốc huyết áp lúc 08:00. Đã uống 0 trong 1 liều đến giờ. Cập nhật lúc 08:20.")
        // The Lock Screen's: no medicine named, even to VoiceOver.
        #expect(CaregiverWidgetCopy.spoken(for: one, calendar: vietnam, namingMedicines: false)
            == "Mẹ chưa xác nhận liều 08:00. Đã uống 0 trong 1 liều đến giờ. Cập nhật lúc 08:20.")
        // A dose within its grace is due, not late.
        #expect(entry(at: at(8, 29), log: log).late.isEmpty)
        let two = entry(at: at(12, 40), log: log)
        #expect(two.late.map(\.id) == [dose(morningEvening, 8), dose(noon, 12)])
        #expect(CaregiverWidgetCopy.moreLate(for: two) == "+1 liều trễ khác")
        #expect(CaregiverWidgetCopy.spoken(for: two, calendar: vietnam)
            == "Mẹ chưa xác nhận Thuốc huyết áp lúc 08:00. Mẹ chưa xác nhận Thuốc tiểu đường lúc 12:00. Đã uống 0 trong 2 liều đến giờ.")
        #expect(CaregiverWidgetCopy.spoken(for: two, calendar: vietnam, namingMedicines: false)
            == "Mẹ chưa xác nhận liều 08:00. Mẹ chưa xác nhận liều 12:00. Đã uống 0 trong 2 liều đến giờ.")
    }

    @Test("Last night's dose, still unanswered after midnight: late, \"hôm qua\", counted, until the morning's is due")
    func lastNight() {
        var log = DoseLog()
        log.record(.taken, for: dose(morningEvening, 8, day: -1), at: at(8, 5, day: -1))
        log.record(.taken, for: dose(noon, 12, day: -1), at: at(12, 5, day: -1))
        let night = entry(at: at(0, 30), log: log)
        #expect(night.late.map(\.id) == [dose(morningEvening, 20, day: -1)])
        #expect((night.soFar, night.taken) == (1, 0))
        #expect(CaregiverWidgetCopy.title(for: night, calendar: vietnam) == "20:00 hôm qua chưa xác nhận")
        // The morning's dose due, last night's is no longer asked about.
        let morning = entry(at: at(8), log: log)
        #expect(morning.late.isEmpty)
        #expect((morning.soFar, morning.taken) == (1, 0))
    }

    @Test("When the parent's phone last sent news: its time, with the day once it is another day's")
    func updated() {
        let log = answeredYesterday()
        #expect(CaregiverWidgetCopy.updated(for: entry(at: at(9), log: log, updatedAt: at(7, 5)), calendar: vietnam) == "Cập nhật 07:05")
        let nextDay = entry(at: at(9, day: 1), log: log, updatedAt: at(7, 5))
        #expect(CaregiverWidgetCopy.updated(for: nextDay, calendar: vietnam) == "Cập nhật 25/9 07:05")
        #expect(CaregiverWidgetCopy.spoken(for: nextDay, calendar: vietnam).hasSuffix("Cập nhật lúc 25/9 07:05."))
        #expect(CaregiverWidgetCopy.updated(for: entry(at: at(9), log: log), calendar: vietnam) == nil)
    }

    @Test("No medicine added yet")
    func noMedicines() {
        let empty = entry(at: at(9), log: DoseLog(), medications: [])
        #expect(!empty.hasMedicines)
        #expect(CaregiverWidgetCopy.title(for: empty, calendar: vietnam) == "Chưa có thuốc nào")
        #expect(CaregiverWidgetCopy.inline(for: empty, calendar: vietnam) == "Mẹ chưa có thuốc nào")
        #expect(CaregiverWidgetCopy.spoken(for: empty, calendar: vietnam) == "Mẹ chưa có thuốc nào.")
    }

    @Test("Nothing known yet: says so, never that the parent has no medicine")
    func awaitingNews() {
        let unknown = CaregiverWidgetEntry.awaitingNews(at: at(9, 30), personName: "Mẹ", calendar: vietnam)
        #expect(unknown.awaitingNews)
        #expect(unknown.day == at(0))
        #expect(CaregiverWidgetCopy.title(for: unknown, calendar: vietnam) == "Chưa có tin")
        #expect(CaregiverWidgetCopy.inline(for: unknown, calendar: vietnam) == "Chưa có tin từ máy của Mẹ")
        #expect(CaregiverWidgetCopy.spoken(for: unknown, calendar: vietnam) == "Chưa có tin từ máy của Mẹ.")
        #expect(CaregiverWidgetCopy.updated(for: unknown, calendar: vietnam) == nil)
        // An entry from a snapshot is news, even with no medicine.
        #expect(!entry(at: at(9), log: DoseLog(), medications: []).awaitingNews)
    }

    @Test("The timeline: each dose due, late and no longer asked about, and midnight; until the end of tomorrow")
    func timeline() {
        let entries = CaregiverWidgetTimeline.entries(
            from: at(7), personName: "Mẹ", medications: medications, log: answeredYesterday(), updatedAt: at(6), calendar: vietnam
        )
        #expect(entries.map(\.date) == [
            at(7), at(8), at(8, 30), at(12), at(12, 30), at(20), at(20, 30),
            at(0, day: 1), at(8, day: 1), at(8, 30, day: 1), at(12, day: 1), at(12, 30, day: 1), at(20, day: 1), at(20, 30, day: 1),
        ])
        // 20:00: the morning's dose no longer asked about (missed), the noon's still late.
        #expect(entries[5].late.map(\.id) == [dose(noon, 12)])
        #expect((entries[5].soFar, entries[5].taken) == (3, 0))
        // Midnight: last night's dose carried, the noon's gone at its twelve hours.
        #expect(entries[7].late.map(\.id) == [dose(morningEvening, 20)])
        #expect(entries[7].soFar == 1)
        #expect(CaregiverWidgetCopy.updated(for: entries[7], calendar: vietnam) == "Cập nhật 25/9 06:00")
        #expect(CaregiverWidgetTimeline.end(from: at(7), calendar: vietnam) == at(0, day: 2))
    }

    @Test("A day that changes nothing but its date still gets its entry: the news reads a day older")
    func midnightOnly() {
        let ended = Medication(
            name: "Thuốc đã hết", dose: "", style: PillStyle(shape: .round, color: .white),
            times: [TimeOfDay(hour: 8)], endDate: at(9, day: -1)
        )
        let entries = CaregiverWidgetTimeline.entries(
            from: at(9), personName: "Mẹ", medications: [ended], log: DoseLog(), updatedAt: at(7, 5), calendar: vietnam
        )
        #expect(entries.map(\.date) == [at(9), at(0, day: 1)])
        #expect(entries.map { CaregiverWidgetCopy.updated(for: $0, calendar: vietnam) } == ["Cập nhật 07:05", "Cập nhật 25/9 07:05"])
        #expect(CaregiverWidgetCopy.title(for: entries[1], calendar: vietnam) == "Chưa đến giờ uống thuốc")
    }

    @Test("A dose stops being late when it stops being asked about: twelve hours on, with no other moment then")
    func stopsWaiting() {
        let once = Medication(
            id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000001C")!,
            name: "Thuốc một lần", dose: "", style: PillStyle(shape: .round, color: .white), times: [TimeOfDay(hour: 8)]
        )
        var log = DoseLog()
        log.record(.taken, for: DoseID(medicationID: once.id, time: at(8, day: -1)), at: at(8, 5, day: -1))
        let entries = CaregiverWidgetTimeline.entries(
            from: at(7), personName: "Mẹ", medications: [once], log: log, updatedAt: nil, calendar: vietnam
        )
        #expect(entries.map(\.date) == [at(7), at(8), at(8, 30), at(20), at(0, day: 1), at(8, day: 1), at(8, 30, day: 1), at(20, day: 1)])
        #expect(entries[2].late.count == 1)
        #expect(entries[3].late.isEmpty)
        #expect((entries[3].soFar, entries[3].taken) == (1, 0))
        // Taken at 08:05: at 09:00 its twelve hours ending changes nothing, and adds no entry.
        log.record(.taken, for: DoseID(medicationID: once.id, time: at(8)), at: at(8, 5))
        let answered = CaregiverWidgetTimeline.entries(
            from: at(9), personName: "Mẹ", medications: [once], log: log, updatedAt: nil, calendar: vietnam
        )
        #expect(answered.map(\.date) == [at(9), at(0, day: 1), at(8, day: 1), at(8, 30, day: 1), at(20, day: 1)])
    }

    @Test("Last night's dose stops waiting in the morning with no dose then: that moment too")
    func lastNightStops() {
        let late = Medication(
            id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000001D")!,
            name: "Thuốc buổi tối", dose: "", style: PillStyle(shape: .round, color: .white), times: [TimeOfDay(hour: 22)]
        )
        let entries = CaregiverWidgetTimeline.entries(
            from: at(0, 30), personName: "Mẹ", medications: [late], log: DoseLog(), updatedAt: nil, calendar: vietnam
        )
        // 22:00 waits twelve hours: until 10:00, when nothing else happens.
        #expect(entries.map(\.date) == [
            at(0, 30), at(10), at(22), at(22, 30), at(0, day: 1), at(10, day: 1), at(22, day: 1), at(22, 30, day: 1),
        ])
        #expect(entries[0].late.map(\.time) == [at(22, day: -1)])
        #expect(entries[1].late.isEmpty)
    }

    @Test("Shared through the App Group: saved only when it changes, days before yesterday left out, the parent's clock")
    func store() throws {
        let suite = "CaregiverWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var log = answeredYesterday()
        log.record(.taken, for: dose(morningEvening, 8, day: -2), at: at(8, 5, day: -2))
        log.record(.taken, for: dose(morningEvening, 8), at: at(8, 5))
        let snapshot = CaregiverWidgetSnapshot(
            personName: "Mẹ", medications: medications, log: log, updatedAt: at(8, 6), timeZone: vietnam.timeZone, now: at(9)
        )
        #expect(!snapshot.records.contains { $0.dose == dose(morningEvening, 8, day: -2) })
        #expect(snapshot.records.count == 4)
        #expect(snapshot.calendar.timeZone == vietnam.timeZone)
        let store = CaregiverWidgetStore(defaults: defaults)
        #expect(store.snapshot == nil)
        #expect(store.save(snapshot))
        #expect(!store.save(snapshot))
        #expect(store.snapshot == snapshot)
        let entries = try #require(store.snapshot).entries(from: at(9))
        #expect(entries.first == entry(at: at(9), log: snapshot.log, updatedAt: at(8, 6)))
        #expect(snapshot.timelineEnd(from: at(9)) == at(0, day: 2))
        #expect(!CaregiverWidgetStore(defaults: nil).save(snapshot))
    }
}
