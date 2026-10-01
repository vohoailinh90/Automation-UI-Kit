import Foundation
@testable import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// A moment on Vietnam's clock, on 25/09/2026 plus `day` days.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: 9, day: 25 + day, hour: hour, minute: minute))!
}

private let morningEvening = Medication(
    id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000002A")!,
    name: "Thuốc huyết áp", dose: "1 viên", instructions: "",
    style: PillStyle(shape: .round, color: .white), times: [TimeOfDay(hour: 8), TimeOfDay(hour: 20)]
)
private let noon = Medication(
    id: UUID(uuidString: "0D0E0A00-0000-4000-8000-00000000002B")!,
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

/// A store in defaults of its own, removed after `body`.
private func withStore<Store>(_ make: (UserDefaults) -> Store, _ body: (Store) throws -> Void) throws {
    let suite = "MedsSiriTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(make(defaults))
}

@Suite("Siri: the parent's \"Tôi uống thuốc rồi\" records the dose waiting; the family's \"Mẹ uống thuốc chưa?\" hears their widget")
struct MedsSiriTests {
    @Test("\"Tôi uống thuốc rồi\": the dose waiting, taken as ĐÃ UỐNG takes it on the widget, named; said again, nothing more")
    func tookMedicine() throws {
        try withStore({ DoseWidgetStore(defaults: $0) }) { store in
            let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
            store.save(DoseWidgetSnapshot(medications: medications, log: answeredYesterday(), timeZone: vietnam.timeZone, now: at(8)))
            let reply = store.recordTaken(at: at(8, 10))
            #expect(reply.answer == .take(today[0], over: nil))
            #expect(reply.text == "Đã uống Thuốc huyết áp, 1 viên, liều 08:00. Hôm nay đã uống 1 trong 3 liều.")
            // Kept with the widget's answers, for the app to take in; the
            // widget shows it at once, with Hoàn tác.
            #expect(store.answers.map(\.dose) == [today[0].id])
            #expect(store.answers.map(\.outcome) == [.taken])
            let recorded = try #require(store.answers.first)
            let shown = try #require(store.entries(from: at(8, 10))?.first)
            #expect(shown.answered?.dose == today[0])
            #expect(shown.answer == .undo(today[0], answer: recorded))
            // Said again: no dose waits, so nothing more is recorded.
            let again = store.recordTaken(at: at(8, 11))
            #expect(again.answer == nil)
            #expect(again.text == "Không có liều nào đang chờ. Liều tiếp theo, 12:00: Thuốc tiểu đường. Hôm nay đã uống 1 trong 3 liều.")
            #expect(store.answers.count == 1)
        }
    }

    @Test("Two doses waiting: the earliest first, the other counted; said again, the other")
    func oneAtATime() throws {
        try withStore({ DoseWidgetStore(defaults: $0) }) { store in
            let today = DoseSchedule.doses(of: medications, onDayOf: at(8), calendar: vietnam)
            store.save(DoseWidgetSnapshot(medications: medications, log: answeredYesterday(), timeZone: vietnam.timeZone, now: at(12)))
            let first = store.recordTaken(at: at(12, 5))
            #expect(first.answer == .take(today[0], over: nil))
            #expect(first.text == "Đã uống Thuốc huyết áp, 1 viên, liều 08:00. Còn 1 liều khác chưa uống. Hôm nay đã uống 1 trong 3 liều.")
            let second = store.recordTaken(at: at(12, 6))
            #expect(second.answer == .take(today[1], over: nil))
            #expect(second.text == "Đã uống Thuốc tiểu đường, liều 12:00. Hôm nay đã uống 2 trong 3 liều.")
            #expect(Set(store.answers.map(\.dose)) == [today[0].id, today[1].id])
        }
    }

    @Test("Last night's dose still waits after midnight: that one, \"hôm qua\"; a dose undone on the widget is taken again")
    func lastNightAndUndone() throws {
        try withStore({ DoseWidgetStore(defaults: $0) }) { store in
            var log = DoseLog()
            log.record(.taken, for: dose(morningEvening, 8, day: -1), at: at(8, 5, day: -1))
            log.record(.taken, for: dose(noon, 12, day: -1), at: at(12, 5, day: -1))
            store.save(DoseWidgetSnapshot(medications: medications, log: log, timeZone: vietnam.timeZone, now: at(0, 30)))
            let night = store.recordTaken(at: at(0, 30))
            #expect(night.answer?.dose.id == dose(morningEvening, 20, day: -1))
            #expect(night.text == "Đã uống Thuốc huyết áp, 1 viên, liều 20:00 hôm qua. Hôm nay đã uống 0 trong 3 liều.")
            // Hoàn tác on the widget: the dose waits again, and is taken
            // over the answer undone.
            let undone = try #require(store.answers.first)
            store.record(.cleared, for: undone.dose, at: at(0, 31))
            let cleared = try #require(store.log?.storedRecord(for: undone.dose))
            let again = store.recordTaken(at: at(0, 32))
            #expect(again.answer == .take(try #require(night.answer?.dose), over: cleared))
            #expect(store.log?[undone.dose]?.outcome == .taken)
        }
    }

    @Test("None waiting: what comes next, nothing recorded; no medicine; nothing shared yet, or no App Group: open the app")
    func nothingToRecord() throws {
        try withStore({ DoseWidgetStore(defaults: $0) }) { store in
            #expect(store.recordTaken(at: at(8, 10)) == .openApp)
            #expect(TookMedicineReply.openApp.text == "Mở ứng dụng để xem thuốc.")
            #expect(store.answers.isEmpty)
            store.save(DoseWidgetSnapshot(medications: medications, log: answeredYesterday(), timeZone: vietnam.timeZone, now: at(7)))
            let early = store.recordTaken(at: at(7))
            #expect(early.answer == nil)
            #expect(early.text == "Không có liều nào đang chờ. Liều tiếp theo, 08:00: Thuốc huyết áp, 1 viên. Hôm nay đã uống 0 trong 3 liều.")
            var all = answeredYesterday()
            for (medication, hour) in [(morningEvening, 8), (noon, 12), (morningEvening, 20)] {
                all.record(.taken, for: dose(medication, hour), at: at(hour, 5))
            }
            store.save(DoseWidgetSnapshot(medications: medications, log: all, timeZone: vietnam.timeZone, now: at(21)))
            #expect(store.recordTaken(at: at(21)).text == "Không có liều nào đang chờ. Đã uống đủ hôm nay. Ngày mai, 08:00: Thuốc huyết áp, 1 viên.")
            store.save(DoseWidgetSnapshot(medications: [], log: DoseLog(), timeZone: vietnam.timeZone, now: at(9)))
            #expect(store.recordTaken(at: at(9)) == TookMedicineReply(answer: nil, text: "Chưa có thuốc nào."))
            #expect(store.answers.isEmpty)
        }
        #expect(DoseWidgetStore(defaults: nil).recordTaken(at: at(8, 10)) == .openApp)
    }

    @Test("What would be said, from the log alone, is what the store says and records")
    func sameReply() throws {
        try withStore({ DoseWidgetStore(defaults: $0) }) { store in
            store.save(DoseWidgetSnapshot(medications: medications, log: answeredYesterday(), timeZone: vietnam.timeZone, now: at(8)))
            let preview = TookMedicineReply(at: at(12, 40), medications: medications, log: answeredYesterday(), calendar: vietnam)
            #expect(store.recordTaken(at: at(12, 40)) == preview)
        }
    }

    @Test("\"Mẹ uống thuốc chưa?\": what the family's widget shows, no medicine named; before any news, that there is none")
    func askedByTheFamily() throws {
        try withStore({ CaregiverWidgetStore(defaults: $0) }) { store in
            #expect(store.siriAnswer(at: at(8, 30), personName: "Mẹ") == "Chưa có tin từ máy của Mẹ.")
            store.save(CaregiverWidgetSnapshot(
                personName: "Bà nội", medications: medications, log: answeredYesterday(), updatedAt: at(8, 20),
                timeZone: vietnam.timeZone, now: at(8, 20)
            ))
            #expect(store.siriAnswer(at: at(8, 30), personName: "Mẹ")
                == "Bà nội chưa xác nhận liều 08:00. Đã uống 0 trong 1 liều đến giờ. Cập nhật lúc 08:20.")
            #expect(store.siriAnswer(at: at(12, 40), personName: "Mẹ")
                == "Bà nội chưa xác nhận liều 08:00. Bà nội chưa xác nhận liều 12:00. Đã uống 0 trong 2 liều đến giờ. Cập nhật lúc 08:20.")
            #expect(store.siriAnswer(at: at(7), personName: "Mẹ") == "Bà nội chưa đến giờ uống thuốc. Cập nhật lúc 08:20.")
            var all = answeredYesterday()
            for (medication, hour) in [(morningEvening, 8), (noon, 12), (morningEvening, 20)] {
                all.record(.taken, for: dose(medication, hour), at: at(hour, 5))
            }
            store.save(CaregiverWidgetSnapshot(
                personName: "Bà nội", medications: medications, log: all, updatedAt: at(20, 5), timeZone: vietnam.timeZone, now: at(20, 5)
            ))
            #expect(store.siriAnswer(at: at(21), personName: "Mẹ") == "Bà nội đã uống 3 trong 3 liều đến giờ. Cập nhật lúc 20:05.")
            // The widget's own entry, in the words VoiceOver reads on the Lock Screen.
            let entry = CaregiverWidgetTimeline.entry(
                at: at(21), personName: "Bà nội", medications: medications, log: all, updatedAt: at(20, 5), calendar: vietnam
            )
            #expect(CaregiverWidgetCopy.siri(for: entry, calendar: vietnam) == CaregiverWidgetCopy.spoken(for: entry, calendar: vietnam, namingMedicines: false))
        }
        #expect(CaregiverWidgetStore(defaults: nil).siriAnswer(at: at(9), personName: "Bố") == "Chưa có tin từ máy của Bố.")
    }
}
