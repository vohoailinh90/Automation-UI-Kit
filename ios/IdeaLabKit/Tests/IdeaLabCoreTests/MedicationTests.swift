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
        #expect(decoded.startDate == nil && decoded.endDate == nil, "stored before start and end dates existed")
    }

    @Test("Start and end dates survive a round trip")
    func medicationDatesRoundTrip() throws {
        let medication = Medication(name: "A", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 7)],
                                    startDate: at(9, 41), endDate: at(12, day: 30))
        let decoded = try JSONDecoder().decode(Medication.self, from: JSONEncoder().encode(medication))
        #expect(decoded == medication)
    }
}

@Suite("Dose schedule")
struct DoseScheduleTests {
    let morning = Medication(name: "Huyết áp", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 7)])
    let twice = Medication(name: "Tiểu đường", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 19), TimeOfDay(hour: 7)])
    let thrice = Medication(name: "Kháng sinh", dose: "1 viên", style: pill,
                            times: [TimeOfDay(hour: 7), TimeOfDay(hour: 12), TimeOfDay(hour: 19)])

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
        log.undo(dose.id, at: at(8, 55))
        #expect(DoseSchedule.status(of: dose, in: log, now: at(9)) == .late(by: 2 * 3_600))
    }

    @Test("A dose stops waiting when the same medicine's next dose is due")
    func missedAtNextDose() {
        let doses = DoseSchedule.doses(of: [thrice], onDayOf: at(12), calendar: vietnam)
        let log = DoseLog()
        #expect(doses.map(\.waitsUntil) == [at(12), at(19), at(7, day: 26)])
        #expect(DoseSchedule.status(of: doses[0], in: log, now: at(11, 59)) == .late(by: (4 * 60 + 59) * 60))
        #expect(DoseSchedule.status(of: doses[0], in: log, now: at(12)) == .missed)
        // "ĐÃ UỐNG" at noon is for the noon pill, not the morning one.
        #expect(DoseSchedule.current(of: doses, in: log, now: at(12))?.id == doses[1].id)
    }

    @Test("A dose waits for an answer 12 hours at most")
    func missedAfterTwelveHours() throws {
        let dose = try #require(DoseSchedule.doses(of: [morning], onDayOf: at(12), calendar: vietnam).first)
        #expect(dose.waitsUntil == at(19))
        #expect(ScheduledDose(medication: morning, time: at(7)).waitsUntil == at(19))
        #expect(DoseSchedule.status(of: dose, in: DoseLog(), now: at(18, 59)) == .late(by: (11 * 60 + 59) * 60))
        #expect(DoseSchedule.status(of: dose, in: DoseLog(), now: at(19)) == .missed)
        #expect(!DoseStatus.missed.isWaiting)
    }

    @Test("An evening dose is still asked about after midnight, until it stops waiting")
    func waitingCarriesPastMidnight() {
        let evening = Medication(name: "Thuốc ngủ", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 21)])
        let log = DoseLog()
        let carried = DoseSchedule.waiting(of: [evening], in: log, now: at(0, 30, day: 26), calendar: vietnam)
        #expect(carried.map(\.time) == [at(21)])
        #expect(DoseSchedule.waiting(of: [evening], in: log, now: at(8, 59, day: 26), calendar: vietnam).map(\.time) == [at(21)])
        #expect(DoseSchedule.waiting(of: [evening], in: log, now: at(9, day: 26), calendar: vietnam).isEmpty, "12 hours on")
        // With a morning dose too, last night's stops waiting once the morning one is due.
        let both = Medication(name: "Tiểu đường", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 7), TimeOfDay(hour: 21)])
        #expect(DoseSchedule.waiting(of: [both], in: log, now: at(6, 59, day: 26), calendar: vietnam).map(\.time) == [at(21)])
        #expect(DoseSchedule.waiting(of: [both], in: log, now: at(7, 10, day: 26), calendar: vietnam).map(\.time) == [at(7, day: 26)])
        // An answered dose does not wait.
        var answered = DoseLog()
        answered.record(.taken, for: carried[0].id, at: at(23))
        #expect(DoseSchedule.waiting(of: [evening], in: answered, now: at(0, 30, day: 26), calendar: vietnam).isEmpty)
    }

    @Test("Doses before a medicine's start or after its end do not count")
    func startAndEnd() {
        let added = Medication(name: "Mới", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 7), TimeOfDay(hour: 19)],
                               startDate: at(9, 41))
        #expect(DoseSchedule.doses(of: [added], onDayOf: at(12), calendar: vietnam).map(\.time) == [at(19)],
                "added at 09:41: this morning's 07:00 is not missed")
        let fromSeven = Medication(name: "Mới", dose: "1 viên", style: pill, times: [TimeOfDay(hour: 7)], startDate: at(7))
        #expect(DoseSchedule.doses(of: [fromSeven], onDayOf: at(12), calendar: vietnam).map(\.time) == [at(7)])
        let course = Medication(name: "Kháng sinh", dose: "1 viên", style: pill,
                                times: [TimeOfDay(hour: 7), TimeOfDay(hour: 12), TimeOfDay(hour: 19)], endDate: at(12))
        let doses = DoseSchedule.doses(of: [course], onDayOf: at(12), calendar: vietnam)
        #expect(doses.map(\.time) == [at(7), at(12)])
        #expect(doses.map(\.waitsUntil) == [at(12), at(0, day: 26)], "no 19:00 dose after the end: noon's waits 12 hours")
        #expect(DoseSchedule.doses(of: [course], onDayOf: at(12, day: 26), calendar: vietnam).isEmpty)
    }

    @Test("A time a daylight-saving jump skips stays on its own day, or has no dose that day")
    func daylightSavingDayBounds() throws {
        var nuuk = Calendar(identifier: .gregorian)
        nuuk.timeZone = try #require(TimeZone(identifier: "America/Nuuk"))
        // 28 March 2026: clocks jump from 23:00 to 00:00, so 23:00 and 23:30 do not exist that day.
        let day = try #require(nuuk.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12)))
        #expect(TimeOfDay(hour: 23).date(onDayOf: day, calendar: nuuk) == nil)
        let late = Medication(name: "A", dose: "1 viên", style: pill,
                              times: [TimeOfDay(hour: 22, minute: 30), TimeOfDay(hour: 23, minute: 30)])
        let doses = DoseSchedule.doses(of: [late], onDayOf: day, calendar: nuuk)
        #expect(doses.count == 1)
        #expect(doses.allSatisfy { nuuk.isDate($0.time, inSameDayAs: day) && $0.waitsUntil > $0.time })

        var lordHowe = Calendar(identifier: .gregorian)
        lordHowe.timeZone = try #require(TimeZone(identifier: "Australia/Lord_Howe"))
        // 4 October 2026: clocks jump from 02:00 to 02:30.
        let jumpDay = try #require(lordHowe.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12)))
        let two = try #require(TimeOfDay(hour: 2).date(onDayOf: jumpDay, calendar: lordHowe))
        #expect(two == lordHowe.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 2, minute: 30)))
    }

    @Test("A daylight-saving change cannot give a medicine two doses at one instant")
    func daylightSaving() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // 8 March 2026: clocks jump from 02:00 to 03:00, so 02:30 lands on 03:00.
        let medication = Medication(name: "A", dose: "1 viên", style: pill,
                                    times: [TimeOfDay(hour: 2, minute: 30), TimeOfDay(hour: 3), TimeOfDay(hour: 8)])
        let day = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let doses = DoseSchedule.doses(of: [medication], onDayOf: day, calendar: newYork)
        #expect(doses.count == 2)
        #expect(Set(doses.map(\.id)).count == doses.count)
        #expect(doses[0].waitsUntil == doses[1].time)
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
        let clear = DoseRecord(dose: id, outcome: .cleared, recordedAt: at(7, 5))
        #expect(DoseLog([skip, clear])[id]?.outcome == .skipped)
        #expect(DoseLog([clear, skip])[id]?.outcome == .skipped)
    }

    @Test("Records compare by the whole second, so precision lost in a store cannot split devices")
    func wholeSeconds() {
        let id = DoseID(medicationID: morning.id, time: at(7))
        let skip = DoseRecord(dose: id, outcome: .skipped, recordedAt: at(7, 5).addingTimeInterval(0.7))
        let take = DoseRecord(dose: id, outcome: .taken, recordedAt: at(7, 5).addingTimeInterval(0.3))
        #expect(DoseLog([skip, take])[id]?.outcome == .taken)
        #expect(DoseLog([take, skip])[id]?.outcome == .taken)
        let laterSkip = DoseRecord(dose: id, outcome: .skipped, recordedAt: at(7, 5).addingTimeInterval(1.1))
        #expect(DoseLog([take, laterSkip])[id]?.outcome == .skipped)
        #expect(DoseLog([laterSkip, take])[id]?.outcome == .skipped)
    }

    @Test("A record whose date is not a number or infinite is dropped, in the dose or when it was recorded")
    func nonFiniteDates() {
        let id = DoseID(medicationID: morning.id, time: at(7))
        let take = DoseRecord(dose: id, outcome: .taken, recordedAt: at(7, 5))
        for bad in [Double.nan, .infinity, -.infinity] {
            let badStamp = DoseRecord(dose: id, outcome: .skipped, recordedAt: Date(timeIntervalSinceReferenceDate: bad))
            #expect(DoseLog([take, badStamp])[id]?.outcome == .taken, "\(bad)")
            #expect(DoseLog([badStamp]).records.isEmpty, "\(bad)")
            // A dose id that is not a number could never be found or replaced again.
            let badDose = DoseRecord(dose: DoseID(medicationID: morning.id, time: Date(timeIntervalSinceReferenceDate: bad)),
                                     outcome: .taken, recordedAt: at(7, 5))
            #expect(DoseLog([badDose, badDose]).records.isEmpty, "\(bad)")
            var log = DoseLog()
            log.record(.taken, for: badDose.dose, at: at(7, 5))
            #expect(log.records.isEmpty, "\(bad)")
        }
    }

    @Test("An undo is stored and synced like an answer: an older answer cannot bring the dose back")
    func durableUndo() {
        let dose = ScheduledDose(medication: morning, time: at(7))
        var log = DoseLog()
        log.record(.taken, for: dose.id, at: at(7, 10))
        let taken = log.records
        log.undo(dose.id, at: at(7, 20))
        #expect(log[dose.id] == nil)
        #expect(DoseSchedule.status(of: dose, in: log, now: at(7, 25)) == .due)
        #expect(log.records.map(\.outcome) == [.cleared])
        // Another phone still holds the earlier answer and syncs it back.
        var synced = DoseLog(log.records)
        synced.merge(taken[0])
        #expect(synced[dose.id] == nil)
        #expect(synced == log)
        synced.merge(DoseRecord(dose: dose.id, outcome: .taken, recordedAt: at(7, 30)))
        #expect(synced[dose.id]?.outcome == .taken, "a newer answer after the undo counts")
    }

    @Test("Answers on one phone replace the last, even in the same second or with a clock behind")
    func localAnswersInOrder() {
        let id = DoseID(medicationID: morning.id, time: at(7))
        var log = DoseLog()
        var history: [DoseRecord] = []
        // After each step, another device that got every record so far, in
        // either order, agrees with this phone.
        func step(_ change: (inout DoseLog) -> Void) {
            change(&log)
            history += log.records
            #expect(DoseLog(history) == log)
            #expect(DoseLog(history.reversed()) == log)
        }
        step { $0.record(.taken, for: id, at: at(9, 41)) }
        step { $0.undo(id, at: at(9, 41)) }
        #expect(log[id] == nil, "a frozen clock: the undo comes in the same second")
        step { $0.record(.skipped, for: id, at: at(9, 41)) }
        #expect(log[id]?.outcome == .skipped)
        step { $0.record(.taken, for: id, at: at(9, 30)) }
        #expect(log[id]?.outcome == .taken, "a clock that went back")
    }

    @Test("A local answer stays later than the one it replaces, whether a store cuts or rounds seconds")
    func stampSurvivesRounding() {
        let id = DoseID(medicationID: morning.id, time: at(7))
        var log = DoseLog()
        log.record(.taken, for: id, at: at(7, 5).addingTimeInterval(10.6))
        let taken = log.records[0]
        log.undo(id, at: at(7, 5).addingTimeInterval(11.3))
        let cleared = log.records[0]
        #expect(cleared.recordedAt.timeIntervalSince(taken.recordedAt) >= 1)
        #expect(log.storedRecord(for: id)?.outcome == .cleared)
        #expect(log[id] == nil)
        for rule in [FloatingPointRoundingRule.down, .toNearestOrAwayFromZero] {
            func stored(_ record: DoseRecord) -> DoseRecord {
                var copy = record
                copy.recordedAt = Date(timeIntervalSinceReferenceDate: record.recordedAt.timeIntervalSinceReferenceDate.rounded(rule))
                return copy
            }
            #expect(DoseLog([stored(taken), stored(cleared)])[id] == nil, "\(rule)")
            #expect(DoseLog([stored(cleared), stored(taken)])[id] == nil, "\(rule)")
        }
    }

    @Test("An answer here beats one from a phone whose clock is far ahead, on every phone")
    func clockAhead() throws {
        let id = DoseID(medicationID: morning.id, time: at(7))
        let year2099 = try #require(vietnam.date(from: DateComponents(year: 2099, month: 1, day: 1)))
        // However far ahead, even past where a Double counts single seconds.
        let aheads = [year2099] + [1e12, 1e13, 1e300, Double.greatestFiniteMagnitude / 2].map(Date.init(timeIntervalSinceReferenceDate:))
        for ahead in aheads {
            let wrongClock = DoseRecord(dose: id, outcome: .taken, recordedAt: ahead)
            var log = DoseLog([wrongClock])
            #expect(log[id]?.outcome == .taken, "a clock that is merely wrong still counts")
            log.record(.skipped, for: id, at: at(7, 5))
            #expect(log[id]?.outcome == .skipped)
            #expect(DoseLog([wrongClock] + log.records)[id]?.outcome == .skipped)
            #expect(DoseLog(log.records + [wrongClock])[id]?.outcome == .skipped)
        }
        // Nothing comes after the largest finite Double. There the same-second
        // rule decides here as on every other phone: the undo cannot beat
        // "taken", and this phone does not pretend it did.
        let atMax = DoseRecord(dose: id, outcome: .taken, recordedAt: Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude))
        var log = DoseLog([atMax])
        log.undo(id, at: at(7, 5))
        #expect(log[id]?.outcome == .taken)
        #expect(log.records.allSatisfy { $0.recordedAt.timeIntervalSinceReferenceDate.isFinite })
        #expect(DoseLog([atMax] + log.records) == log)
        // A "taken" does beat a "cleared" there, on every phone alike.
        let clearedAtMax = DoseRecord(dose: id, outcome: .cleared, recordedAt: atMax.recordedAt)
        var retaken = DoseLog([clearedAtMax])
        retaken.record(.taken, for: id, at: at(7, 5))
        #expect(retaken[id]?.outcome == .taken)
        #expect(DoseLog([clearedAtMax] + retaken.records) == retaken)
        // A clock on this phone that is not a number still gives a record every phone accepts.
        var nanClock = DoseLog()
        nanClock.record(.taken, for: id, at: Date(timeIntervalSinceReferenceDate: .nan))
        #expect(DoseLog(nanClock.records)[id]?.outcome == .taken)
    }

    @Test("Stored records come out in one order, whatever order they were made in")
    func recordOrder() {
        let records = (1...12).map { index in
            DoseRecord(
                dose: DoseID(medicationID: UUID(uuidString: "00000000-0000-4000-8000-0000000000\(10 + index)")!, time: at(7)),
                outcome: .taken, recordedAt: at(7, 5)
            )
        }
        #expect(DoseLog(records).records == records)
        #expect(DoseLog(records.reversed()).records == records)
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

    @Test("A missed dose counts as come and not taken")
    func summaryWithMissed() {
        let doses = DoseSchedule.doses(of: [thrice], onDayOf: at(12), calendar: vietnam)
        let summary = DoseSchedule.summary(of: doses, in: DoseLog(), now: at(12, 10))
        #expect(summary.missed == 1)
        #expect(summary.due == 1)
        #expect(summary.upcoming == 1)
        #expect(summary.soFar == 2)
        #expect(summary.total == 3)
        #expect(DoseSchedule.adherence(of: doses, in: DoseLog(), now: at(12, 10)) == 0)
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
