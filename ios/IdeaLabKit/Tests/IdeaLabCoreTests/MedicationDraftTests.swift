import Foundation
import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 25, month: Int = 9, in calendar: Calendar = vietnam) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Add-medicine form")
struct MedicationDraftTests {
    @Test("Times stay sorted and unique however they are added, moved or removed")
    func times() {
        var draft = MedicationDraft(times: [TimeOfDay(hour: 21), TimeOfDay(hour: 7), TimeOfDay(hour: 21)])
        #expect(draft.times == [TimeOfDay(hour: 7), TimeOfDay(hour: 21)])
        let added = draft.add(TimeOfDay(hour: 12))
        let addedAgain = draft.add(TimeOfDay(hour: 12))
        #expect(added)
        #expect(!addedAgain, "already there")
        #expect(draft.times == [TimeOfDay(hour: 7), TimeOfDay(hour: 12), TimeOfDay(hour: 21)])
        let moved = draft.change(TimeOfDay(hour: 21), to: TimeOfDay(hour: 6, minute: 30))
        #expect(moved)
        #expect(draft.times == [TimeOfDay(hour: 6, minute: 30), TimeOfDay(hour: 7), TimeOfDay(hour: 12)])
        draft.remove(TimeOfDay(hour: 7))
        #expect(draft.times == [TimeOfDay(hour: 6, minute: 30), TimeOfDay(hour: 12)])
    }

    @Test("Moving a time onto another one changes nothing: two rows never become one dose")
    func changeOntoExisting() {
        var draft = MedicationDraft(times: [TimeOfDay(hour: 7), TimeOfDay(hour: 19)])
        let ontoOther = draft.change(TimeOfDay(hour: 19), to: TimeOfDay(hour: 7))
        #expect(!ontoOther)
        #expect(draft.times == [TimeOfDay(hour: 7), TimeOfDay(hour: 19)])
        let notThere = draft.change(TimeOfDay(hour: 8), to: TimeOfDay(hour: 9))
        #expect(!notThere, "not one of the times")
        #expect(draft.times == [TimeOfDay(hour: 7), TimeOfDay(hour: 19)])
        let unchanged = draft.change(TimeOfDay(hour: 7), to: TimeOfDay(hour: 7))
        #expect(unchanged, "unchanged is fine")
    }

    @Test("What is missing is said in form order, and only that")
    func problems() {
        var draft = MedicationDraft(name: "  ", dose: " ", times: [], course: .days(0))
        #expect(draft.problems == [.missingName, .missingDose, .noTimes, .courseLength])
        #expect(!draft.isComplete)
        #expect(draft.medication(startingAt: at(9, 41), calendar: vietnam) == nil)
        draft.name = "Thuốc huyết áp"
        draft.dose = "1 viên"
        draft.add(TimeOfDay(hour: 7))
        draft.course = .days(MedicationDraft.longestCourse + 1)
        #expect(draft.problems == [.courseLength])
        draft.course = .days(MedicationDraft.longestCourse)
        #expect(draft.isComplete)
        #expect(Set(MedicationDraft.Problem.allCases.map(\.message)).count == MedicationDraft.Problem.allCases.count)
    }

    @Test("The medicine starts when it is added, trimmed, with the form's look and times")
    func makesMedication() throws {
        let style = PillStyle(shape: .capsule, color: .orange, secondColor: .cream)
        let draft = MedicationDraft(
            name: "  Thuốc dạ dày ", dose: " 1 viên", instructions: "Trước ăn  ", style: style,
            times: [TimeOfDay(hour: 18), TimeOfDay(hour: 6, minute: 30)]
        )
        let id = UUID()
        let medication = try #require(draft.medication(id: id, startingAt: at(9, 41), calendar: vietnam))
        #expect(medication.id == id)
        #expect(medication.name == "Thuốc dạ dày")
        #expect(medication.dose == "1 viên")
        #expect(medication.instructions == "Trước ăn")
        #expect(medication.style == style)
        #expect(medication.times == [TimeOfDay(hour: 6, minute: 30), TimeOfDay(hour: 18)])
        #expect(medication.startDate == at(9, 41))
        #expect(medication.endDate == nil, "ongoing")
        // Added at 09:41: this morning's 06:30 is not a dose, this evening's 18:00 is.
        let doses = DoseSchedule.doses(of: [medication], onDayOf: at(9, 41), calendar: vietnam)
        #expect(doses.map(\.time) == [at(18)])
    }

    @Test("A course of days ends with its last day in the parent's calendar, the first day being today")
    func courseEnd() throws {
        let draft = MedicationDraft(name: "Kháng sinh", times: [TimeOfDay(hour: 7), TimeOfDay(hour: 19)], course: .days(7))
        let medication = try #require(draft.medication(startingAt: at(9, 41), calendar: vietnam))
        // 25/09 is day 1, so day 7 is 01/10; its 19:00 is the last dose.
        #expect(medication.endDate == at(0, day: 2, month: 10).addingTimeInterval(-1))
        let lastDay = DoseSchedule.doses(of: [medication], onDayOf: at(12, day: 1, month: 10), calendar: vietnam)
        #expect(lastDay.map(\.time) == [at(7, day: 1, month: 10), at(19, day: 1, month: 10)])
        #expect(DoseSchedule.doses(of: [medication], onDayOf: at(12, day: 2, month: 10), calendar: vietnam).isEmpty)
        // A one-day course is today only.
        let today = try #require(MedicationDraft.courseEnd(days: 1, startingAt: at(9, 41), calendar: vietnam))
        #expect(today == at(0, day: 26).addingTimeInterval(-1))
        #expect(MedicationDraft.courseEnd(days: 0, startingAt: at(9, 41), calendar: vietnam) == nil)
        #expect(MedicationDraft.courseEnd(days: MedicationDraft.longestCourse + 1, startingAt: at(9, 41), calendar: vietnam) == nil)
    }

    @Test("A course over a clock change still ends at the end of its last day")
    func courseEndAcrossDST() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // Clocks go back on 1 November 2026: that day has 25 hours.
        let start = at(20, day: 30, month: 10, in: newYork)
        let end = try #require(MedicationDraft.courseEnd(days: 3, startingAt: start, calendar: newYork))
        #expect(end == at(0, day: 2, month: 11, in: newYork).addingTimeInterval(-1))
        #expect(newYork.component(.day, from: end) == 1)
        #expect(newYork.component(.hour, from: end) == 23)
    }

    @Test("One more time is the first usual one free, then an hour after the last, then the first whole hour free")
    func suggestedNewTime() {
        var draft = MedicationDraft(times: [])
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 7))
        draft.add(TimeOfDay(hour: 7))
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 12))
        for suggestion in MedicationDraft.timeSuggestions { draft.add(suggestion.time) }
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 22))
        draft.add(TimeOfDay(hour: 22, minute: 30))
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 23, minute: 30))
        draft.add(TimeOfDay(hour: 23, minute: 30))
        // Nothing after 23:30: the day's first free whole hour, still addable.
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 0))
        draft.add(TimeOfDay(hour: 0))
        draft.add(TimeOfDay(hour: 1))
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 2))
        for hour in 0..<24 { draft.add(TimeOfDay(hour: hour)) }
        #expect(draft.suggestedNewTime == nil, "every whole hour taken")
        draft.remove(TimeOfDay(hour: 23))
        #expect(draft.suggestedNewTime == TimeOfDay(hour: 23), "the last whole hour, freed")
    }

    @Test("The suggestions are what they say: distinct, and times sorted")
    func suggestions() {
        #expect(Set(MedicationDraft.doseSuggestions).count == MedicationDraft.doseSuggestions.count)
        #expect(Set(MedicationDraft.instructionSuggestions).count == MedicationDraft.instructionSuggestions.count)
        let times = MedicationDraft.timeSuggestions.map(\.time)
        #expect(times == times.sorted() && Set(times).count == times.count)
    }
}
