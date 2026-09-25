import Foundation
import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 25) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private let pill = PillStyle(shape: .round, color: .white)

@Suite("Time of day")
struct TimeOfDayTests {
    @Test func formatsLikeAMedicineLabel() {
        #expect(TimeOfDay(hour: 7).description == "07:00")
        #expect(TimeOfDay(hour: 19, minute: 5).description == "19:05")
    }

    @Test("A time lands on the given day in the calendar's zone")
    func placesOnDay() throws {
        // 00:30 on 25/09 in Vietnam is still 24/09 in UTC; the day is Vietnam's.
        let date = try #require(TimeOfDay(hour: 7).date(onDayOf: at(0, 30), calendar: vietnam))
        #expect(date == at(7))
    }

    @Test("A stored 25:00 is corrupt, not a time")
    func decodingValidates() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TimeOfDay.self, from: Data(#"{"hour":25,"minute":0}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TimeOfDay.self, from: Data(#"{"hour":7,"minute":60}"#.utf8))
        }
    }

    @Test("Medication times are sorted and unique, also after decoding")
    func medicationTimesNormalised() throws {
        let medication = Medication(name: "A", dose: "1 viên", style: pill,
                                    times: [TimeOfDay(hour: 19), TimeOfDay(hour: 7), TimeOfDay(hour: 19)])
        #expect(medication.times == [TimeOfDay(hour: 7), TimeOfDay(hour: 19)])
        let json = """
        {"id":"8D2B6A4E-1C1F-4A7B-9E4E-2F7B1C3D4E5F","name":"A","dose":"1 viên","instructions":"",
         "style":{"shape":"round","color":"white"},
         "times":[{"hour":19,"minute":0},{"hour":7,"minute":0},{"hour":7,"minute":0}]}
        """
        let decoded = try JSONDecoder().decode(Medication.self, from: Data(json.utf8))
        #expect(decoded.times == [TimeOfDay(hour: 7), TimeOfDay(hour: 19)])
    }
}

@Suite("Dose schedule")
struct DoseScheduleTests {
    let morning = Medication(name: "Huyết áp", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 7)])
    let twice = Medication(name: "Tiểu đường", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 19), TimeOfDay(hour: 7)])

    @Test("A day's doses are in time order, ties by name")
    func doseOrder() {
        let doses = DoseSchedule.doses(of: [twice, morning], onDayOf: at(12), calendar: vietnam)
        #expect(doses.map(\.time) == [at(7), at(7), at(19)])
        #expect(doses.map(\.medication.name) == ["Huyết áp", "Tiểu đường", "Tiểu đường"])
    }

    @Test("Upcoming, then due for 30 minutes, then late")
    func statusFollowsTheClock() {
        let dose = ScheduledDose(medication: morning, time: at(7))
        let log = DoseLog()
        #expect(DoseSchedule.status(of: dose, in: log, now: at(6, 59)) == .upcoming)
        #expect(DoseSchedule.status(of: dose, in: log, now: at(7)) == .due)
        #expect(DoseSchedule.status(of: dose, in: log, now: at(7, 29)) == .due)
        #expect(DoseSchedule.status(of: dose, in: log, now: at(7, 30)) == .late(by: 30 * 60))
        #expect(DoseSchedule.status(of: dose, in: log, now: at(9, 41)) == .late(by: (2 * 60 + 41) * 60))
    }

    @Test("A record wins over the clock, and undo gives the clock back")
    func recordsAndUndo() {
        let dose = ScheduledDose(medication: morning, time: at(7))
        var log = DoseLog()
        log.record(.taken, for: dose.id, at: at(6, 50))
        #expect(DoseSchedule.status(of: dose, in: log, now: at(9)) == .taken(at: at(6, 50)), "taking early is allowed")
        log.remove(dose.id)
        #expect(DoseSchedule.status(of: dose, in: log, now: at(9)) == .late(by: 2 * 3_600))
    }

    @Test("The latest answer for a dose wins, whatever order records arrive in")
    func latestAnswerWins() {
        let id = DoseID(medicationID: morning.id, time: at(7))
        let skip = DoseRecord(dose: id, outcome: .skipped, recordedAt: at(7, 5))
        let take = DoseRecord(dose: id, outcome: .taken, recordedAt: at(7, 10))
        #expect(DoseLog([skip, take])[id]?.outcome == .taken)
        #expect(DoseLog([take, skip])[id]?.outcome == .taken, "an older record synced late must not override")
    }

    @Test("Two answers from the same second resolve the same way in any order")
    func sameSecondTie() {
        let id = DoseID(medicationID: morning.id, time: at(7))
        let skip = DoseRecord(dose: id, outcome: .skipped, recordedAt: at(7, 5))
        let take = DoseRecord(dose: id, outcome: .taken, recordedAt: at(7, 5))
        #expect(DoseLog([skip, take])[id]?.outcome == .taken)
        #expect(DoseLog([take, skip])[id]?.outcome == .taken)
    }

    @Test("Same name and time: the order does not depend on the input's")
    func stableOrderOnTies() {
        let a = Medication(name: "Vitamin", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 8)])
        let b = Medication(name: "Vitamin", dose: "2 viên", style: pill, times: [TimeOfDay(hour: 8)])
        let forward = DoseSchedule.doses(of: [a, b], onDayOf: at(12), calendar: vietnam).map(\.medication.id)
        let backward = DoseSchedule.doses(of: [b, a], onDayOf: at(12), calendar: vietnam).map(\.medication.id)
        #expect(forward == backward)
    }

    @Test("The parent's screen shows the earliest waiting dose, then the next one")
    func currentAndNext() {
        let doses = DoseSchedule.doses(of: [morning, twice], onDayOf: at(12), calendar: vietnam)
        var log = DoseLog()
        log.record(.taken, for: doses[0].id, at: at(7, 12))
        // 07:00 Tiểu đường is late and waiting; 19:00 is next.
        #expect(DoseSchedule.current(of: doses, in: log, now: at(9, 41))?.id == doses[1].id)
        #expect(DoseSchedule.next(of: doses, in: log, now: at(9, 41))?.id == doses[2].id)
        log.record(.taken, for: doses[1].id, at: at(9, 42))
        #expect(DoseSchedule.current(of: doses, in: log, now: at(9, 43)) == nil)
    }

    @Test("Summary and adherence only judge doses whose time has come")
    func summaryAndAdherence() {
        let doses = DoseSchedule.doses(of: [morning, twice], onDayOf: at(12), calendar: vietnam)
        var log = DoseLog()
        #expect(DoseSchedule.adherence(of: doses, in: log, now: at(6)) == nil, "nothing settled yet is not 0%")
        log.record(.taken, for: doses[0].id, at: at(7, 12))
        let summary = DoseSchedule.summary(of: doses, in: log, now: at(7, 40))
        #expect(summary.taken == 1)
        #expect(summary.late == 1)
        #expect(summary.upcoming == 1)
        #expect(summary.soFar == 2)
        #expect(summary.total == 3)
        #expect(DoseSchedule.adherence(of: doses, in: log, now: at(7, 40)) == 0.5)
        // Still within grace, the second dose is not held against anyone.
        #expect(DoseSchedule.adherence(of: doses, in: log, now: at(7, 20)) == 1)
    }
}

@Suite("Sample household")
struct MedicationSamplesTests {
    @Test("At 09:41 every status shows: taken, late, due, upcoming")
    func morningShowsEveryStatus() {
        let now = LedgerSamples.referenceNow
        let log = MedicationSamples.log()
        let doses = DoseSchedule.doses(of: MedicationSamples.medications, onDayOf: now, calendar: vietnam)
        let statuses = doses.map { DoseSchedule.status(of: $0, in: log, now: now) }
        #expect(statuses.contains(.taken(at: at(7, 12))))
        #expect(statuses.contains(.late(by: (2 * 60 + 41) * 60)))
        #expect(statuses.contains(.due))
        #expect(statuses.filter { $0 == .upcoming }.count == 2)
        #expect(DoseSchedule.current(of: doses, in: log, now: now)?.medication.id == MedicationSamples.diabetes.id)
    }

    @Test("The week has exactly the two planted misses")
    func weekHistory() throws {
        let now = LedgerSamples.referenceNow
        let log = MedicationSamples.log()
        var perDay: [Double] = []
        for daysAgo in (1...6).reversed() {
            let day = try #require(vietnam.date(byAdding: .day, value: -daysAgo, to: now))
            let doses = DoseSchedule.doses(of: MedicationSamples.medications, onDayOf: day, calendar: vietnam)
            perDay.append(try #require(DoseSchedule.adherence(of: doses, in: log, now: now)))
        }
        // Six days ago … yesterday: a skip five days ago, a miss three days ago.
        #expect(perDay == [1, 0.8, 1, 0.8, 1, 1])
    }
}

@Suite("Vietnamese durations")
struct VietnameseDurationTests {
    @Test(arguments: [
        (0, "0 phút"), (59, "0 phút"), (29 * 60 + 40, "29 phút"), (30 * 60, "30 phút"),
        (60 * 60, "1 giờ"), ((2 * 60 + 41) * 60, "2 giờ 41 phút"),
        (24 * 3_600, "1 ngày"), (27 * 3_600 + 59 * 60, "1 ngày 3 giờ"), (-5, "0 phút"),
    ] as [(Double, String)])
    func formats(seconds: Double, expected: String) {
        #expect(VietnameseDuration.string(seconds) == expected)
    }
}
