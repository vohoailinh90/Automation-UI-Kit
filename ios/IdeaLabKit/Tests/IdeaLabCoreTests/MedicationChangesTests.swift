import Foundation
import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

/// 2026, in Vietnam: 25 September is a Friday.
private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 25, month: Int = 9) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private let white = PillStyle(shape: .round, color: .white)

/// "Huyết áp": 07:00 and 21:00 since 1 September, no end.
private let bloodPressure = Medication(
    name: "Huyết áp", dose: "1 viên", instructions: "Sau ăn", style: white,
    times: [TimeOfDay(hour: 7), TimeOfDay(hour: 21)], startDate: at(8, day: 1)
)

private let other = Medication(name: "Tiểu đường", dose: "1 viên", style: white, times: [TimeOfDay(hour: 7)])

private func draft(_ edit: (inout MedicationDraft) -> Void, from medication: Medication = bloodPressure) -> MedicationDraft {
    var draft = MedicationDraft(editing: medication)
    edit(&draft)
    return draft
}

private func doses(_ medications: [Medication], day: Int, month: Int = 9) -> [Date] {
    DoseSchedule.doses(of: medications, onDayOf: at(12, day: day, month: month), calendar: vietnam).map(\.time)
}

@Suite("Medicine versions")
struct MedicationVersionTests {
    @Test("A medicine is its own series unless it continues one, also as stored before versions existed")
    func seriesID() throws {
        #expect(bloodPressure.seriesID == bloodPressure.id)
        let next = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "1 viên", style: white, times: [TimeOfDay(hour: 8)])
        #expect(next.seriesID == bloodPressure.id && next.id != bloodPressure.id)
        let decoded = try JSONDecoder().decode(Medication.self, from: JSONEncoder().encode(next))
        #expect(decoded == next)
        let id = UUID()
        let stored = Data(#"{"id":"\#(id)","name":"A","dose":"1 viên","instructions":"","style":{"shape":"round","color":"white"},"times":[{"hour":7,"minute":0}]}"#.utf8)
        #expect(try JSONDecoder().decode(Medication.self, from: stored).seriesID == id)
    }

    @Test("A dose waits for the next dose of its series, whichever version that is, and only its own series")
    func waitsAcrossVersions() throws {
        var tonight = bloodPressure
        tonight.endDate = at(0, day: 26).addingTimeInterval(-1)
        let tomorrow = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "1 viên", style: white,
                                  times: [TimeOfDay(hour: 8), TimeOfDay(hour: 13)], startDate: at(0, day: 26))
        let evening = try #require(DoseSchedule.doses(of: [tonight, tomorrow], onDayOf: at(12), calendar: vietnam).last)
        #expect(evening.time == at(21))
        #expect(evening.waitsUntil == at(8, day: 26), "the new version's first dose")
        // The new version's own doses wait for the series' next one too.
        let next = DoseSchedule.doses(of: [tonight, tomorrow], onDayOf: at(12, day: 26), calendar: vietnam)
        #expect(next.map(\.waitsUntil) == [at(13, day: 26), at(1, day: 27)])
        // A medicine of another series at the same times changes nothing: 12 hours.
        let unrelated = Medication(name: "Huyết áp", dose: "1 viên", style: white, times: [TimeOfDay(hour: 8)], startDate: at(0, day: 26))
        let alone = try #require(DoseSchedule.doses(of: [tonight, unrelated], onDayOf: at(12), calendar: vietnam).first { $0.medication.id == tonight.id && $0.time == at(21) })
        #expect(alone.waitsUntil == at(9, day: 26))
        // Last night's pill is asked about after midnight until the new morning one is due.
        let log = DoseLog()
        #expect(DoseSchedule.waiting(of: [tonight, tomorrow], in: log, now: at(7, 59, day: 26), calendar: vietnam).map(\.time) == [at(21)])
        #expect(DoseSchedule.waiting(of: [tonight, tomorrow], in: log, now: at(8, day: 26), calendar: vietnam).map(\.time) == [at(8, day: 26)])
    }

    @Test("Versions come earliest first; the latest is the one to edit; current lists one per medicine in use")
    func versionsAndCurrent() {
        var ended = bloodPressure
        ended.endDate = at(0, day: 26).addingTimeInterval(-1)
        let next = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "1 viên", style: white,
                              times: [TimeOfDay(hour: 8)], startDate: at(0, day: 26))
        let stopped = Medication(name: "Kháng sinh", dose: "1 viên", style: white, times: [TimeOfDay(hour: 7)],
                                 startDate: at(8, day: 10), endDate: at(0, day: 17))
        let list = [next, other, stopped, ended]
        #expect(MedicationChanges.versions(of: bloodPressure.id, in: list).map(\.id) == [ended.id, next.id])
        #expect(MedicationChanges.latest(of: bloodPressure.id, in: list)?.id == next.id)
        #expect(MedicationChanges.latest(of: UUID(), in: list) == nil)
        #expect(MedicationChanges.current(in: list, at: at(12)).map(\.id) == [next.id, other.id], "by name; the course that ended is left out")
    }
}

@Suite("Editing a medicine")
struct MedicationEditTests {
    @Test("The form starts from the medicine; a course keeps its end, however long the form stays open")
    func draftFromMedication() throws {
        let form = MedicationDraft(editing: bloodPressure)
        #expect(form == MedicationDraft(name: "Huyết áp", dose: "1 viên", instructions: "Sau ăn", style: white,
                                        times: [TimeOfDay(hour: 7), TimeOfDay(hour: 21)], course: .ongoing))
        var course = bloodPressure
        let thursday = at(0, day: 2, month: 10).addingTimeInterval(-1)
        course.endDate = thursday
        let kept = MedicationDraft(editing: course)
        #expect(kept.course == .until(thursday))
        #expect(kept.isComplete)
        #expect(try #require(kept.medication(startingAt: at(12), calendar: vietnam)).endDate == thursday)
        #expect(try #require(kept.medication(startingAt: at(0, 5, day: 26), calendar: vietnam)).endDate == thursday, "past midnight too")
    }

    @Test("The days left count today, at least one and at most a year")
    func daysLeft() {
        let thursday = at(0, day: 2, month: 10).addingTimeInterval(-1)
        #expect(MedicationDraft.daysLeft(until: thursday, at: at(12), calendar: vietnam) == 7, "Friday 25/9 to Thursday 1/10")
        #expect(MedicationDraft.daysLeft(until: thursday, at: at(0, 5, day: 26), calendar: vietnam) == 6, "a day later")
        #expect(MedicationDraft.daysLeft(until: thursday, at: at(23, 59, day: 1, month: 10), calendar: vietnam) == 1, "its last day")
        #expect(MedicationDraft.daysLeft(until: at(12, day: 20), at: at(12), calendar: vietnam) == 1, "already over: at least today")
        #expect(MedicationDraft.daysLeft(until: at(12).addingTimeInterval(400 * 86_400), at: at(12), calendar: vietnam)
            == MedicationDraft.longestCourse)
    }

    @Test("Times, dose and instructions are the regimen; the name, the look and the course are not")
    func regimen() {
        let form = MedicationDraft(editing: bloodPressure)
        #expect(!form.changesRegimen(of: bloodPressure))
        #expect(!draft { $0.name = "Amlodipin"; $0.style.color = .pink; $0.course = .days(3) }.changesRegimen(of: bloodPressure))
        #expect(!draft { $0.dose = " 1 viên  " }.changesRegimen(of: bloodPressure), "the same once trimmed")
        #expect(draft { $0.dose = "2 viên" }.changesRegimen(of: bloodPressure))
        #expect(draft { $0.instructions = "Trước ăn" }.changesRegimen(of: bloodPressure))
        #expect(draft { $0.add(TimeOfDay(hour: 12)) }.changesRegimen(of: bloodPressure))
        #expect(draft { $0.change(TimeOfDay(hour: 21), to: TimeOfDay(hour: 20)) }.changesRegimen(of: bloodPressure))
    }

    @Test("New times start tomorrow as a new version; today and its answers stay as they were")
    func regimenChangeFromTomorrow() throws {
        var log = DoseLog()
        log.record(.taken, for: DoseID(medicationID: bloodPressure.id, time: at(7)), at: at(7, 5))
        let form = draft {
            $0.change(TimeOfDay(hour: 7), to: TimeOfDay(hour: 8))
            $0.change(TimeOfDay(hour: 21), to: TimeOfDay(hour: 20))
            $0.dose = "2 viên"
            $0.name = "Huyết áp (liều mới)"
        }
        let newID = UUID()
        let list = try #require(MedicationChanges.applying(form, to: bloodPressure.id, in: [other, bloodPressure], now: at(12),
                                                           calendar: vietnam, newID: newID))
        #expect(list.map(\.id) == [other.id, bloodPressure.id, newID], "same order, the new version last")
        #expect(list[0] == other)
        var ended = bloodPressure
        ended.endDate = at(0, day: 26).addingTimeInterval(-1)
        #expect(list[1] == ended, "today's version keeps its name, times and dose")
        let next = list[2]
        #expect(next.seriesID == bloodPressure.id)
        #expect(next.startDate == at(0, day: 26) && next.endDate == nil)
        #expect((next.name, next.dose, next.instructions, next.times) == ("Huyết áp (liều mới)", "2 viên", "Sau ăn", [TimeOfDay(hour: 8), TimeOfDay(hour: 20)]))
        #expect(doses(list, day: 25) == [at(7), at(7), at(21)], "today: both medicines' 07:00, then 21:00")
        #expect(doses(list, day: 26) == [at(7, day: 26), at(8, day: 26), at(20, day: 26)])
        #expect(log[DoseID(medicationID: bloodPressure.id, time: at(7))]?.outcome == .taken, "this morning's answer is still its dose's")
        #expect(MedicationChanges.effect(of: form, on: bloodPressure.id, in: [other, bloodPressure], now: at(12), calendar: vietnam)
            == .fromTomorrow(at(0, day: 26)))
    }

    @Test("A course with new times counts its days from today, as the form says")
    func regimenChangeWithCourse() throws {
        let form = draft { $0.dose = "2 viên"; $0.course = .days(3) }
        let list = try #require(MedicationChanges.applying(form, to: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam))
        #expect(list.last?.startDate == at(0, day: 26))
        #expect(list.last?.endDate == at(0, day: 28).addingTimeInterval(-1), "Friday, Saturday, Sunday")
        #expect(doses(list, day: 27) == [at(7, day: 27), at(21, day: 27)])
        #expect(doses(list, day: 28).isEmpty)
    }

    @Test("New times with a course ending today: no day is left for them, so nothing is saved, and the form says why")
    func regimenChangeEndingToday() throws {
        // A new dose and a new name, the course cut to today: saving only the
        // name would drop the dose without a word.
        let form = draft { $0.dose = "2 viên"; $0.name = "Amlodipin"; $0.course = .days(1) }
        #expect(MedicationChanges.applying(form, to: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == nil)
        #expect(MedicationChanges.effect(of: form, on: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == .noDayLeft)
        // On a course's last day, a new dose alone is no "nothing changed".
        var lastDay = bloodPressure
        lastDay.endDate = at(0, day: 26).addingTimeInterval(-1)
        let dose = draft({ $0.dose = "2 viên" }, from: lastDay)
        #expect(MedicationChanges.effect(of: dose, on: bloodPressure.id, in: [lastDay], now: at(12), calendar: vietnam) == .noDayLeft)
        // A day more, and the new dose has it; today stays as it was.
        let newID = UUID()
        let longer = draft({ $0.dose = "2 viên"; $0.course = .days(2) }, from: lastDay)
        let list = try #require(MedicationChanges.applying(longer, to: bloodPressure.id, in: [lastDay], now: at(12), calendar: vietnam,
                                                           newID: newID))
        #expect(list.map(\.id) == [bloodPressure.id, newID])
        #expect(list[0] == lastDay)
        #expect(list[1].dose == "2 viên" && list[1].startDate == at(0, day: 26) && list[1].endDate == at(0, day: 27).addingTimeInterval(-1))
        #expect(MedicationChanges.effect(of: longer, on: bloodPressure.id, in: [lastDay], now: at(12), calendar: vietnam)
            == .fromTomorrow(at(0, day: 26)))
        // An end is the last moment a dose counts, so a course ending at
        // tomorrow's first instant still has that one for the new version.
        let midnight = draft { $0.dose = "2 viên"; $0.course = .until(at(0, day: 26)) }
        #expect(MedicationChanges.effect(of: midnight, on: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam)
            == .fromTomorrow(at(0, day: 26)))
        // The dose back as it was: the name and the end change in place.
        let renamed = draft { $0.name = "Amlodipin"; $0.course = .days(1) }
        let inPlace = try #require(MedicationChanges.applying(renamed, to: bloodPressure.id, in: [bloodPressure], now: at(12),
                                                              calendar: vietnam))
        #expect(inPlace.map(\.name) == ["Amlodipin"] && inPlace[0].dose == "1 viên" && inPlace[0].endDate == lastDay.endDate)
        #expect(MedicationChanges.effect(of: renamed, on: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == .inPlace)
    }

    @Test("Changing again the same day replaces tomorrow's version; a new name alone renames both in place")
    func changeTwice() throws {
        let first = try #require(MedicationChanges.applying(draft { $0.dose = "2 viên" }, to: bloodPressure.id, in: [bloodPressure],
                                                            now: at(12), calendar: vietnam))
        let tomorrow = try #require(first.last)
        let latest = try #require(MedicationChanges.latest(of: bloodPressure.id, in: first))
        #expect(latest == tomorrow)
        let secondID = UUID()
        let second = try #require(MedicationChanges.applying(draft({ $0.dose = "½ viên" }, from: latest), to: bloodPressure.id,
                                                             in: first, now: at(15), calendar: vietnam, newID: secondID))
        #expect(second.map(\.id) == [bloodPressure.id, secondID])
        #expect(second[0] == first[0], "today's version untouched")
        #expect(second[1].dose == "½ viên" && second[1].startDate == at(0, day: 26))
        let renamed = try #require(MedicationChanges.applying(draft({ $0.name = "Amlodipin" }, from: latest), to: bloodPressure.id,
                                                              in: first, now: at(15), calendar: vietnam))
        #expect(renamed.map(\.id) == first.map(\.id))
        #expect(renamed.map(\.name) == ["Amlodipin", "Amlodipin"])
        #expect(renamed.map(\.dose) == ["1 viên", "2 viên"], "the doses stay as they were")
        #expect(renamed.map(\.endDate) == first.map(\.endDate) && renamed.map(\.startDate) == first.map(\.startDate))
        #expect(MedicationChanges.effect(of: draft({ $0.name = "Amlodipin" }, from: latest), on: bloodPressure.id, in: first,
                                         now: at(15), calendar: vietnam) == .inPlace, "tomorrow's version renamed, not replaced")
    }

    @Test("A new name, look or course changes the version in use in place, today's doses included")
    func inPlace() throws {
        let form = draft { $0.name = "  Amlodipin "; $0.style = PillStyle(shape: .oval, color: .pink); $0.course = .days(5) }
        let list = try #require(MedicationChanges.applying(form, to: bloodPressure.id, in: [bloodPressure, other], now: at(12),
                                                           calendar: vietnam))
        #expect(list.map(\.id) == [bloodPressure.id, other.id], "no new version")
        #expect(list[0].name == "Amlodipin" && list[0].style == PillStyle(shape: .oval, color: .pink))
        #expect(list[0].times == bloodPressure.times && list[0].startDate == bloodPressure.startDate)
        #expect(list[0].endDate == at(0, day: 30).addingTimeInterval(-1), "five days, today counted")
        #expect(list[1] == other)
        #expect(MedicationChanges.effect(of: form, on: bloodPressure.id, in: [bloodPressure, other], now: at(12), calendar: vietnam) == .inPlace)
        // Back to "Lâu dài": no end.
        let ongoing = try #require(MedicationChanges.applying(draft({ $0.course = .ongoing }, from: list[0]), to: bloodPressure.id,
                                                              in: list, now: at(12), calendar: vietnam))
        #expect(ongoing[0].endDate == nil)
    }

    @Test("A version already over keeps its name; one due to start after a shortened course is dropped")
    func inPlaceLeavesThePast() throws {
        var earlier = bloodPressure
        earlier.endDate = at(0, day: 20).addingTimeInterval(-1)
        let now = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "2 viên", style: white,
                             times: [TimeOfDay(hour: 7)], startDate: at(0, day: 20), endDate: at(0, day: 26).addingTimeInterval(-1))
        let tomorrow = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "1 viên", style: white,
                                  times: [TimeOfDay(hour: 8)], startDate: at(0, day: 26))
        let list = [earlier, now, tomorrow]
        let renamed = try #require(MedicationChanges.applying(draft({ $0.name = "Amlodipin" }, from: tomorrow), to: bloodPressure.id,
                                                              in: list, now: at(12), calendar: vietnam))
        #expect(renamed.map(\.name) == ["Huyết áp", "Amlodipin", "Amlodipin"])
        // Only today left: tomorrow's version never starts, today's still ends tonight.
        let shortened = try #require(MedicationChanges.applying(draft({ $0.course = .days(1) }, from: tomorrow), to: bloodPressure.id,
                                                                in: list, now: at(12), calendar: vietnam))
        #expect(shortened == [earlier, now])
        // An end is the last moment a dose counts: a course ending at the
        // moment tomorrow's version starts still has that moment for it.
        let atMidnight = try #require(MedicationChanges.applying(draft({ $0.course = .until(at(0, day: 26)) }, from: tomorrow),
                                                                 to: bloodPressure.id, in: list, now: at(12), calendar: vietnam))
        #expect(atMidnight.map(\.id) == list.map(\.id))
        #expect(atMidnight.last?.endDate == at(0, day: 26))
    }

    @Test("New times end only the version in use: one already over keeps its end, and its days their doses")
    func regimenChangeLeavesThePast() throws {
        var earlier = bloodPressure
        earlier.endDate = at(0, day: 20).addingTimeInterval(-1)
        let current = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "2 viên", style: white,
                                 times: [TimeOfDay(hour: 7)], startDate: at(0, day: 20))
        let newID = UUID()
        let list = try #require(MedicationChanges.applying(draft({ $0.dose = "1 viên" }, from: current), to: bloodPressure.id,
                                                           in: [earlier, current], now: at(12), calendar: vietnam, newID: newID))
        #expect(list.map(\.id) == [bloodPressure.id, current.id, newID])
        #expect(list[0] == earlier, "1 to 19 September stay as they were")
        #expect(list[1].endDate == at(0, day: 26).addingTimeInterval(-1))
        #expect(doses(list, day: 19) == [at(7, day: 19), at(21, day: 19)])
        #expect(doses(list, day: 22) == [at(7, day: 22)], "a day of the version in use: its one dose, no earlier one back")
    }

    @Test("An untouched form changes nothing; an incomplete one or an unknown medicine saves nothing")
    func noChange() {
        let form = MedicationDraft(editing: bloodPressure)
        #expect(MedicationChanges.applying(form, to: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == [bloodPressure])
        #expect(MedicationChanges.effect(of: form, on: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == .unchanged)
        #expect(MedicationChanges.effect(of: draft { $0.name += " " }, on: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == .unchanged)
        #expect(MedicationChanges.applying(draft { $0.name = " " }, to: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == nil)
        #expect(MedicationChanges.applying(form, to: UUID(), in: [bloodPressure], now: at(12), calendar: vietnam) == nil)
        #expect(MedicationChanges.effect(of: form, on: UUID(), in: [bloodPressure], now: at(12), calendar: vietnam) == .notInUse)
        // A form kept from days ago, its course over: saving it would drop answered doses.
        let kept = draft { $0.course = .until(at(20, day: 24)) }
        #expect(MedicationChanges.applying(kept, to: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == nil)
        #expect(MedicationChanges.effect(of: kept, on: bloodPressure.id, in: [bloodPressure], now: at(12), calendar: vietnam) == .endPassed)
        #expect(MedicationChanges.applying(draft { $0.course = .until(at(12)) }, to: bloodPressure.id, in: [bloodPressure],
                                           now: at(12), calendar: vietnam)?.first?.endDate == at(12), "ending now is fine")
    }

    @Test("Left open past the course's last day, the form says why nothing saves, not that nothing changed")
    func formOutlivesTheCourse() {
        var lastDay = bloodPressure
        lastDay.endDate = at(0, day: 26).addingTimeInterval(-1)
        let renamed = draft({ $0.name = "Amlodipin" }, from: lastDay)
        #expect(MedicationChanges.effect(of: renamed, on: bloodPressure.id, in: [lastDay], now: at(23, 59), calendar: vietnam) == .inPlace)
        // Past midnight the medicine is over: nothing left to change.
        #expect(MedicationChanges.effect(of: renamed, on: bloodPressure.id, in: [lastDay], now: at(0, 1, day: 26), calendar: vietnam)
            == .notInUse)
        #expect(MedicationChanges.applying(renamed, to: bloodPressure.id, in: [lastDay], now: at(0, 1, day: 26), calendar: vietnam) == nil)
        // Stopped meanwhile, on another phone: the same.
        let stopped = MedicationChanges.stopping(bloodPressure.id, in: [bloodPressure], now: at(12))
        #expect(MedicationChanges.effect(of: draft { $0.name = "Amlodipin" }, on: bloodPressure.id, in: stopped, now: at(12, 1),
                                         calendar: vietnam) == .notInUse)
        // Still in use, but the last day picked in the form went by: pick the days again.
        let oneDay = draft { $0.course = .until(at(0, day: 26).addingTimeInterval(-1)) }
        #expect(MedicationChanges.effect(of: oneDay, on: bloodPressure.id, in: [bloodPressure], now: at(0, 1, day: 26), calendar: vietnam)
            == .endPassed)
        // Unfinished, the form says what is missing first; the effect stays quiet.
        #expect(MedicationChanges.effect(of: draft { $0.name = "" }, on: bloodPressure.id, in: [bloodPressure], now: at(12),
                                         calendar: vietnam) == .unchanged)
    }
}

@Suite("Stopping a medicine")
struct MedicationStopTests {
    @Test("Stopped: no dose from now on, the answered ones stay, and it is no longer current")
    func stopsNow() {
        var log = DoseLog()
        log.record(.taken, for: DoseID(medicationID: bloodPressure.id, time: at(7)), at: at(7, 5))
        let list = MedicationChanges.stopping(bloodPressure.id, in: [other, bloodPressure], now: at(12, 30, 15))
        #expect(list.map(\.id) == [other.id, bloodPressure.id])
        #expect(list[0] == other)
        #expect(list[1].stoppedAt == at(12, 30, 15))
        #expect(list[1].endDate == nil && list[1].startDate == bloodPressure.startDate, "the plan it had is kept")
        #expect(doses([list[1]], day: 25) == [at(7)])
        #expect(doses([list[1]], day: 26).isEmpty)
        #expect(log[DoseID(medicationID: bloodPressure.id, time: at(7))]?.outcome == .taken)
        #expect(MedicationChanges.current(in: list, at: at(12, 31)).map(\.id) == [other.id])
        #expect(!list[1].isCurrent(at: at(12, 30, 15)) && list[1].isCurrent(at: at(12, 30, 14)))
        // Stopped at 21:00 sharp: that dose is not one any more.
        let atNine = MedicationChanges.stopping(bloodPressure.id, in: [bloodPressure], now: at(21))
        #expect(doses(atNine, day: 25) == [at(7)])
        // A course is current until its last moment.
        var course = bloodPressure
        course.endDate = at(21)
        #expect(course.isCurrent(at: at(21)) && !course.isCurrent(at: at(21, 0, 1)))
    }

    @Test("A medicine already over has nothing to stop: the list comes back as it was, with no stop recorded")
    func nothingToStop() {
        var course = bloodPressure
        course.endDate = at(0, day: 26).addingTimeInterval(-1)
        #expect(MedicationChanges.isInUse(bloodPressure.id, in: [course], at: at(23, 59)))
        #expect(!MedicationChanges.isInUse(bloodPressure.id, in: [course], at: at(0, 1, day: 26)))
        // A form left open past the course's last moment: stopping records nothing.
        #expect(MedicationChanges.stopping(bloodPressure.id, in: [course, other], now: at(0, 1, day: 26)) == [course, other])
        #expect(!MedicationChanges.isInUse(UUID(), in: [course], at: at(12)))
        // One that starts later is in use; stopped, it goes, none of its doses having come.
        let later = Medication(name: "Canxi", dose: "1 viên", style: white, times: [TimeOfDay(hour: 9)], startDate: at(0, day: 28))
        #expect(MedicationChanges.isInUse(later.seriesID, in: [later], at: at(12)))
        #expect(MedicationChanges.stopping(later.seriesID, in: [other, later], now: at(12)) == [other])
    }

    @Test("A dose still waiting stops waiting and counts as missed; the others keep their status")
    func waitingDoseIsMissed() throws {
        let log = DoseLog()
        let list = MedicationChanges.stopping(bloodPressure.id, in: [bloodPressure], now: at(7, 20))
        let morning = try #require(DoseSchedule.doses(of: list, onDayOf: at(7, 20), calendar: vietnam).first)
        #expect(morning.time == at(7) && morning.waitsUntil == at(7, 20))
        #expect(DoseSchedule.status(of: morning, in: log, now: at(7, 20)) == .missed)
        #expect(DoseSchedule.waiting(of: list, in: log, now: at(7, 20), calendar: vietnam).isEmpty)
        // Last night's 21:00 had stopped waiting at 07:00: still missed, not asked about again.
        let evening = try #require(DoseSchedule.doses(of: list, onDayOf: at(12, day: 24), calendar: vietnam).last)
        #expect(evening.time == at(21, day: 24))
        #expect(DoseSchedule.status(of: evening, in: log, now: at(7, 20)) == .missed)
        // Still asked about at 00:30, it stops being asked when stopped then.
        let night = MedicationChanges.stopping(bloodPressure.id, in: [bloodPressure], now: at(0, 30, day: 26))
        #expect(DoseSchedule.waiting(of: [bloodPressure], in: log, now: at(0, 30, day: 26), calendar: vietnam).map(\.time) == [at(21)])
        #expect(DoseSchedule.waiting(of: night, in: log, now: at(0, 30, day: 26), calendar: vietnam).isEmpty)
        #expect(doses(night, day: 25) == [at(7), at(21)], "yesterday's doses stay in the history")
    }

    @Test("A stop reaches the version that ended last night: its 21:00, still waiting after midnight, stops waiting")
    func stopReachesLastNight() {
        // New times from today: yesterday's version ended at midnight.
        var yesterday = bloodPressure
        yesterday.endDate = at(0).addingTimeInterval(-1)
        let today = Medication(seriesID: bloodPressure.id, name: "Huyết áp", dose: "2 viên", style: white,
                               times: [TimeOfDay(hour: 8)], startDate: at(0))
        let log = DoseLog()
        #expect(DoseSchedule.waiting(of: [yesterday, today], in: log, now: at(0, 30), calendar: vietnam).map(\.time) == [at(21, day: 24)])
        let stopped = MedicationChanges.stopping(bloodPressure.id, in: [yesterday, today], now: at(0, 30))
        #expect(stopped.map(\.stoppedAt) == [at(0, 30), at(0, 30)])
        #expect(DoseSchedule.waiting(of: stopped, in: log, now: at(0, 30), calendar: vietnam).isEmpty, "not asked about after the stop")
        #expect(doses(stopped, day: 24) == [at(7, day: 24), at(21, day: 24)], "yesterday's doses stay in the history")
        #expect(stopped[0].endDate == yesterday.endDate && stopped[1].endDate == nil, "the plans are kept")
        // Stopping again later moves nothing: the doses in between stay stopped.
        #expect(MedicationChanges.stopping(bloodPressure.id, in: stopped, now: at(12)) == stopped)
    }

    @Test("A version due to start later is dropped; a stopped medicine can no longer be changed")
    func dropsTomorrow() throws {
        let changed = try #require(MedicationChanges.applying(draft { $0.dose = "2 viên" }, to: bloodPressure.id, in: [bloodPressure],
                                                              now: at(12), calendar: vietnam))
        let list = MedicationChanges.stopping(bloodPressure.id, in: changed, now: at(15))
        #expect(list.map(\.id) == [bloodPressure.id])
        #expect(list[0].stoppedAt == at(15) && list[0].endDate == changed[0].endDate)
        #expect(MedicationChanges.current(in: list, at: at(15)).isEmpty)
        #expect(MedicationChanges.applying(draft { $0.dose = "½ viên" }, to: bloodPressure.id, in: list, now: at(16), calendar: vietnam) == nil)
        #expect(MedicationChanges.stopping(bloodPressure.id, in: list, now: at(16)) == list, "stopped once")
    }

    @Test("Stored and read back, a stop stays a stop; stored before stops existed, a medicine has none")
    func stopRoundTrip() throws {
        let stopped = MedicationChanges.stopping(bloodPressure.id, in: [bloodPressure], now: at(12))[0]
        #expect(try JSONDecoder().decode(Medication.self, from: JSONEncoder().encode(stopped)) == stopped)
        #expect(try JSONDecoder().decode(Medication.self, from: JSONEncoder().encode(bloodPressure)).stoppedAt == nil)
    }
}
