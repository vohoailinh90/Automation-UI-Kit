import Foundation
import IdeaLabCore
import Testing

private let vietnam = LedgerSamples.calendar

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 25, month: Int = 9) -> Date {
    vietnam.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private let white = PillStyle(shape: .round, color: .white)

private let pressure = Medication(
    name: "Thuốc huyết áp", dose: "1 viên", instructions: "Sau ăn sáng", style: white, times: [TimeOfDay(hour: 7)]
)
private let sugar = Medication(
    name: "Thuốc tiểu đường", dose: "1 viên", instructions: "Trong bữa ăn", style: white,
    times: [TimeOfDay(hour: 7), TimeOfDay(hour: 19)]
)
/// Nothing to say but its name.
private let vitamin = Medication(name: "Vitamin D", dose: "", style: white, times: [TimeOfDay(hour: 7, minute: 30)])

private func dose(_ medication: Medication, _ time: Date) -> DoseID {
    DoseID(medicationID: medication.id, time: time)
}

private func plan(
    _ medications: [Medication], for audience: DoseAlerts.Audience = .parent, log: DoseLog = DoseLog(), now: Date,
    updatedAt: Date? = nil, limit: Int = DoseAlerts.systemLimit, scope: String = ""
) -> DoseAlertPlan {
    DoseAlerts.plan(
        for: audience, scope: scope, medications: medications, log: log, now: now, calendar: vietnam,
        updatedAt: updatedAt, limit: limit
    )
}

private let mother = DoseAlerts.Audience.family(personName: "Mẹ")

private func ids(_ alerts: [DoseAlert]) -> Set<String> {
    Set(alerts.map(\.id))
}

/// A log with every dose of the 24th answered, so the family has no news
/// left from the day before the tests' 25th.
private func yesterdayAnswered(_ medications: [Medication]) -> DoseLog {
    var log = DoseLog()
    for scheduled in DoseSchedule.doses(of: medications, onDayOf: at(12, day: 24), calendar: vietnam) {
        log.record(.taken, for: scheduled.id, at: scheduled.time.addingTimeInterval(5 * 60))
    }
    return log
}

@Suite("Dose alerts")
struct DoseAlertsTests {
    @Test("The parent is reminded when doses are due, and again when the grace period ends unanswered: pills due together buzz once")
    func parent() {
        let alerts = plan([pressure, sugar], now: at(6), limit: 4).upcoming
        #expect(alerts.map(\.date) == [at(7), at(7, 30), at(19), at(19, 30)])
        #expect(alerts[0].title == "Đến giờ uống thuốc")
        #expect(alerts[0].body == "Thuốc huyết áp: 1 viên · Sau ăn sáng\nThuốc tiểu đường: 1 viên · Trong bữa ăn")
        #expect(alerts[0].doses == [dose(pressure, at(7)), dose(sugar, at(7))])
        #expect(alerts[1].title == "Nhắc lại: thuốc lúc 07:00")
        #expect(alerts[1].body == "Thuốc huyết áp: 1 viên · Sau ăn sáng\nThuốc tiểu đường: 1 viên · Trong bữa ăn\nUống rồi thì bấm ĐÃ UỐNG.")
        #expect(alerts[1].doses == alerts[0].doses)
        #expect(alerts[2].body == "Thuốc tiểu đường: 1 viên · Trong bữa ăn")
        // A medicine with no dose or instructions is its name alone.
        #expect(plan([vitamin], now: at(6), limit: 1).upcoming.map(\.body) == ["Vitamin D"])
    }

    @Test("A dose due as another turns late shares its alert, which names both")
    func sharedMoment() {
        let alert = plan([pressure, vitamin], now: at(7, 10), limit: 1).upcoming[0]
        #expect(alert.date == at(7, 30))
        #expect(alert.title == "Đến giờ uống thuốc")
        #expect(alert.body == "Vitamin D\nNhắc lại thuốc lúc 07:00: Thuốc huyết áp")
        #expect(alert.doses == [dose(pressure, at(7)), dose(vitamin, at(7, 30))])
    }

    @Test("The family is told when a dose turns late, never when it is due, with how old their news is")
    func family() {
        let alerts = plan([pressure, sugar], for: mother, now: at(6), updatedAt: at(5, 58), limit: 4).upcoming
        #expect(alerts.map(\.date) == [at(7, 30), at(19, 30), at(7, 30, day: 26), at(19, 30, day: 26)])
        #expect(alerts[0].title == "Mẹ chưa xác nhận thuốc lúc 07:00")
        #expect(alerts[0].body == "Thuốc huyết áp, Thuốc tiểu đường\nMáy của Mẹ cập nhật lần cuối lúc 05:58.")
        #expect(alerts[0].doses == [dose(pressure, at(7)), dose(sugar, at(7))])
        #expect(alerts[1].title == "Mẹ chưa xác nhận thuốc lúc 19:00")
        // Scheduled today, shown tomorrow or later: the news shows its age then.
        #expect(alerts[2].body == "Thuốc huyết áp, Thuốc tiểu đường\nMáy của Mẹ cập nhật lần cuối lúc 05:58 hôm qua.")
        let later = plan([pressure], for: mother, now: at(6), updatedAt: at(5, 58), limit: 3).upcoming
        #expect(later[2].body == "Thuốc huyết áp\nMáy của Mẹ cập nhật lần cuối lúc 05:58 ngày 25/9.")
        // Without the time, the medicines alone.
        #expect(plan([pressure], for: mother, now: at(6), limit: 1).upcoming.map(\.body) == ["Thuốc huyết áp"])
    }

    @Test("An answer takes its dose out of the alerts, from any phone; an undo puts it back")
    func answers() {
        let before = plan([pressure, sugar], now: at(6), limit: 2).upcoming
        var log = yesterdayAnswered([pressure, sugar])
        log.record(.taken, for: dose(pressure, at(7)), at: at(7, 5))
        let one = plan([pressure, sugar], log: log, now: at(7, 10), limit: 1)
        #expect(one.upcoming.map(\.id) == [before[1].id], "the same alert, planned again")
        #expect(one.upcoming[0].doses == [dose(sugar, at(7))])
        #expect(one.upcoming[0].body == "Thuốc tiểu đường: 1 viên · Trong bữa ăn\nUống rồi thì bấm ĐÃ UỐNG.")
        #expect(ids(one.current) == [before[0].id], "still true for the other pill")
        #expect(plan([pressure, sugar], for: mother, log: log, now: at(7, 10), limit: 1).upcoming[0].title == "Mẹ chưa xác nhận thuốc lúc 07:00")

        log.record(.skipped, for: dose(sugar, at(7)), at: at(7, 12))
        let both = plan([pressure, sugar], log: log, now: at(7, 15), limit: 1)
        #expect(both.upcoming.map(\.date) == [at(19)])
        #expect(both.current.isEmpty, "nothing shown is still true")
        #expect(plan([pressure, sugar], for: mother, log: log, now: at(7, 15)).current.isEmpty)

        log.undo(dose(sugar, at(7)), at: at(7, 20))
        let undone = plan([pressure, sugar], log: log, now: at(7, 21), limit: 1)
        #expect(undone.upcoming.map(\.doses) == [[dose(sugar, at(7))]])
        #expect(ids(undone.current) == [before[0].id])

        // Answered ahead of time on another phone: nothing to remind.
        var early = DoseLog()
        early.record(.taken, for: dose(vitamin, at(7, 30)), at: at(7, 20))
        #expect(plan([vitamin], log: early, now: at(7), limit: 1).upcoming.map(\.date) == [at(7, 30, day: 26)])
    }

    @Test("A dose whose wait ends first never turns late: no follow-up, and the family is not told")
    func neverLate() {
        // Its medicine's next dose is due exactly as it would turn late.
        let twice = Medication(name: "Kháng sinh", dose: "1 viên", style: white, times: [TimeOfDay(hour: 7), TimeOfDay(hour: 7, minute: 30)])
        let parent = plan([twice], now: at(6), limit: 3)
        #expect(parent.upcoming.map(\.date) == [at(7), at(7, 30), at(8)])
        #expect(parent.upcoming[1].doses == [dose(twice, at(7, 30))], "07:30 is only the next dose")
        #expect(parent.upcoming[1].title == "Đến giờ uống thuốc")
        #expect(plan([twice], for: mother, now: at(6), limit: 1).upcoming.map(\.date) == [at(8)])
        // Waiting at 07:10, it has nothing still to come.
        let waiting = plan([twice], now: at(7, 10), limit: 1)
        #expect(ids(waiting.current) == [parent.upcoming[0].id])
        #expect(plan([twice], for: mother, log: yesterdayAnswered([twice]), now: at(7, 10)).current.isEmpty)
        #expect(plan([twice], for: mother, log: yesterdayAnswered([twice]), now: at(7, 40)).current.isEmpty, "never late, no news to keep")

        // Stopped before it turns late.
        var stopped = pressure
        stopped.stoppedAt = at(7, 10)
        #expect(plan([stopped], now: at(6), limit: 3).upcoming.map(\.date) == [at(7)])
        #expect(plan([stopped], for: mother, now: at(6)).upcoming.isEmpty)
        #expect(plan([stopped], now: at(7, 15)).current.isEmpty, "stopped, it is no longer asked about")
    }

    @Test("Only what is still to come is scheduled: not an alert due this very moment")
    func onlyAhead() {
        let due = plan([pressure], now: at(7), limit: 1)
        #expect(due.upcoming.map(\.date) == [at(7, 30)])
        #expect(ids(due.current).contains(plan([pressure], now: at(6), limit: 1).upcoming[0].id), "iOS shows it now")
        let late = plan([pressure], now: at(7, 30), limit: 1)
        #expect(late.upcoming.map(\.date) == [at(7, day: 26)])
        #expect(plan([pressure], for: mother, now: at(7, 30), limit: 1).upcoming.map(\.date) == [at(7, 30, day: 26)])
    }

    @Test("Last night's dose still waiting turns late after midnight, and is alerted then")
    func lastNight() {
        let night = Medication(name: "Thuốc ngủ", dose: "1 viên", style: white, times: [TimeOfDay(hour: 23, minute: 45)])
        let early = Medication(name: "Thuốc sớm", dose: "1 viên", style: white, times: [TimeOfDay(hour: 0, minute: 10)])
        let alerts = plan([night, early], now: at(0, 5), limit: 2).upcoming
        #expect(alerts.map(\.date) == [at(0, 10), at(0, 15)])
        // Planned yesterday's first, it still comes second.
        #expect(plan([night, early], now: at(0, 5), limit: 1).upcoming.map(\.date) == [at(0, 10)])
        #expect(alerts[1].title == "Nhắc lại: thuốc lúc 23:45")
        #expect(alerts[1].doses == [dose(night, at(23, 45, day: 24))])
        #expect(plan([night], for: mother, now: at(0, 5), limit: 1).upcoming.map(\.title) == ["Mẹ chưa xác nhận thuốc lúc 23:45"])
    }

    @Test("Soonest first, as many as the limit, today and the 30 days after at most")
    func limit() {
        let all = plan([pressure, sugar, vitamin], now: at(6))
        #expect(all.upcoming.count == DoseAlerts.systemLimit)
        #expect(all.upcoming.map(\.date) == all.upcoming.map(\.date).sorted())
        #expect(Set(all.upcoming.map(\.id)).count == all.upcoming.count)
        for limit in [0, 1, 5, 13] {
            #expect(plan([pressure, sugar, vitamin], now: at(6), limit: limit).upcoming == Array(all.upcoming.prefix(limit)))
        }
        #expect(plan([pressure], now: at(6), limit: -1).upcoming.isEmpty)
        // One alert a day: a month of them, then the app plans again.
        let month = plan([pressure], for: mother, now: at(6)).upcoming
        #expect(month.count == 31)
        #expect(month.last?.date == at(7, 30, day: 25, month: 10))
        #expect(plan([], now: at(6)).upcoming.isEmpty)
    }

    @Test("Shown alerts stay while true: the parent's while the dose waits, the family's until it is answered")
    func current() {
        let log = yesterdayAnswered([sugar])
        let morning = plan([sugar], now: at(6), limit: 2).upcoming
        let family = plan([sugar], for: mother, now: at(6), limit: 1).upcoming
        // Due: the reminder has shown; the follow-up is still to come.
        #expect(ids(plan([sugar], log: log, now: at(7, 10)).current) == [morning[0].id])
        #expect(plan([sugar], for: mother, log: log, now: at(7, 10)).current.isEmpty)
        #expect(ids(plan([sugar], log: log, now: at(7, 30)).current) == Set(morning.map(\.id)))
        #expect(ids(plan([sugar], log: log, now: at(18)).current) == Set(morning.map(\.id)))
        #expect(ids(plan([sugar], for: mother, log: log, now: at(7, 30)).current) == [family[0].id])
        #expect(ids(plan([sugar], for: mother, log: log, now: at(18)).current) == [family[0].id])
        // At 19:00 the evening dose is due, and the morning one no longer asked
        // about: the parent's alerts about it go, the family keeps the news.
        let evening = plan([sugar], now: at(18)).upcoming[0].id
        #expect(ids(plan([sugar], log: log, now: at(19, 5)).current) == [evening])
        #expect(ids(plan([sugar], for: mother, log: log, now: at(19, 5)).current) == [family[0].id])
        #expect(ids(plan([sugar], for: mother, now: at(10, day: 26)).current).contains(family[0].id), "until the day after")
        #expect(!ids(plan([sugar], for: mother, now: at(10, day: 27)).current).contains(family[0].id))
        var answered = log
        answered.record(.taken, for: dose(sugar, at(7)), at: at(8))
        #expect(plan([sugar], for: mother, log: answered, now: at(19, 5)).current.isEmpty, "answered late, from the parent's phone")
        // Last night's unanswered news is still there this morning.
        #expect(plan([sugar], for: mother, now: at(7, 10)).current.count == 2)
        #expect(plan([], now: at(7, 10)).current.isEmpty)
        // An alert cut by the limit is not kept for being true soon.
        #expect(ids(plan([sugar], log: log, now: at(7, 10), limit: 0).current) == [morning[0].id])
    }

    @Test("An alert showing this moment says what is still true: an answer since takes its dose out")
    func currentWords() {
        var log = yesterdayAnswered([pressure, sugar])
        log.record(.taken, for: dose(pressure, at(7)), at: at(7))
        let parent = plan([pressure, sugar], log: log, now: at(7)).current
        #expect(parent.map(\.id) == [plan([pressure, sugar], now: at(6), limit: 1).upcoming[0].id])
        #expect(parent.map(\.date) == [at(7)])
        #expect(parent[0].doses == [dose(sugar, at(7))])
        #expect(parent[0].title == "Đến giờ uống thuốc")
        #expect(parent[0].body == "Thuốc tiểu đường: 1 viên · Trong bữa ăn")
        let family = plan([pressure, sugar], for: mother, log: log, now: at(7, 30), updatedAt: at(7, 29)).current
        #expect(family.map(\.date) == [at(7, 30)])
        #expect(family.map(\.body) == ["Thuốc tiểu đường\nMáy của Mẹ cập nhật lần cuối lúc 07:29."])
        // At the follow-up's moment the parent's two alerts are both still true.
        let later = plan([pressure, sugar], log: log, now: at(7, 30)).current
        #expect(later.map(\.date) == [at(7), at(7, 30)])
        #expect(later[1].title == "Nhắc lại: thuốc lúc 07:00")
        #expect(later.allSatisfy { $0.doses == [dose(sugar, at(7))] })
    }

    @Test("An alert's gist is what it says about its doses: the family's news line is not part of it")
    func gist() {
        let early = plan([pressure], for: mother, now: at(6), updatedAt: at(5, 58), limit: 1).upcoming[0]
        let later = plan([pressure], for: mother, now: at(6), updatedAt: at(5, 59), limit: 1).upcoming[0]
        #expect(early.body != later.body)
        #expect(early.gist == later.gist)
        #expect(early.gist == "Mẹ chưa xác nhận thuốc lúc 07:00\nThuốc huyết áp")
        #expect(plan([pressure], for: mother, now: at(6), limit: 1).upcoming[0].gist == early.gist)
        // Renamed in place: the same doses, other words.
        var renamed = pressure
        renamed.name = "Thuốc tim"
        let after = plan([renamed], for: mother, now: at(6), updatedAt: at(5, 58), limit: 1).upcoming[0]
        #expect(after.doses == early.doses)
        #expect(after.gist != early.gist)
        let parent = plan([pressure, sugar], now: at(6), limit: 2).upcoming
        #expect(parent.allSatisfy { $0.gist == $0.title + "\n" + $0.body })
    }

    @Test("Each audience and scope owns its ids, and one thread")
    func ownIDs() {
        let parent = plan([pressure], now: at(6))
        #expect(parent == plan([pressure], now: at(6)), "planned again, the same")
        #expect(parent.upcoming.allSatisfy { $0.id.hasPrefix(parent.prefix) && $0.threadID + "." == parent.prefix })
        let prefixes = [
            parent.prefix,
            plan([pressure], for: mother, now: at(6)).prefix,
            plan([pressure], now: at(6), scope: "a").prefix,
            plan([pressure], now: at(6), scope: "a.parent").prefix,
            plan([pressure], for: mother, now: at(6), scope: "a").prefix,
            plan([pressure], for: .family(personName: "Bố"), now: at(6), scope: "Bố").prefix,
        ]
        for (index, one) in prefixes.enumerated() {
            for other in prefixes[(index + 1)...] {
                #expect(!one.hasPrefix(other) && !other.hasPrefix(one), "\(one) and \(other)")
            }
        }
        let late = plan([pressure], for: mother, now: at(7, 40)).current
        #expect(!late.isEmpty && late.allSatisfy { $0.id.hasPrefix(prefixes[1]) && $0.threadID + "." == prefixes[1] })
    }

    @Test("Days and times are the parent's; the alerts show at that moment wherever the phone is")
    func parentsClock() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let alert = try #require(DoseAlerts.plan(
            for: mother, medications: [pressure], log: DoseLog(), now: at(6), calendar: newYork
        ).upcoming.first)
        // 06:00 in Vietnam is 19:00 the day before in New York.
        let seven = try #require(newYork.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 7, minute: 30)))
        #expect(alert.date == seven)
        #expect(alert.title == "Mẹ chưa xác nhận thuốc lúc 07:00")
    }
}
