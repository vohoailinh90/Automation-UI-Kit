import Foundation

/// What Siri does and says when the parent says "Tôi uống thuốc rồi"
/// (`DoseWidgetStore.recordTaken(at:)`): the dose that "ĐÃ UỐNG" on their
/// widget answers is recorded as taken, one dose each time, as the button
/// and the parent's screen record them, and Siri names it.
///
/// Naming it is what makes the answer safe to trust: at 07:00 with two
/// medicines, the parent hears which one was recorded, and says it again
/// for the other once taken. The app's intent asks for the phone to be
/// unlocked first (`IntentAuthenticationPolicy.requiresAuthentication`),
/// as the Home Screen's widget names medicines and the Lock Screen's do
/// not: an answer also decides whether the family hears of a missed dose.
public struct TookMedicineReply: Hashable, Sendable {
    /// The "ĐÃ UỐNG" recorded; `nil` when no dose was waiting, or before
    /// the app shared anything.
    public var answer: DoseWidgetAnswer?
    /// What Siri says: "Đã uống Thuốc huyết áp, 1 viên, liều 07:00. Còn 1
    /// liều khác chưa uống. Hôm nay đã uống 1 trong 4 liều."
    public var text: String

    public init(answer: DoseWidgetAnswer?, text: String) {
        self.answer = answer
        self.text = text
    }

    /// What "Tôi uống thuốc rồi" does at `now`, on `calendar`'s clock, the
    /// parent's. The dose the widget offers "ĐÃ UỐNG" for (the earliest
    /// waiting, the day before's included) is taken, and Siri says so as
    /// VoiceOver reads the widget after the button: the dose, the others
    /// still waiting, the day's count. With none waiting, nothing is taken
    /// and Siri says what comes next: "Không có liều nào đang chờ. Liều
    /// tiếp theo, 12:00: Thuốc tiểu đường."
    public init(at now: Date, medications: [Medication], log: DoseLog, calendar: Calendar) {
        let before = DoseWidgetTimeline.entry(at: now, medications: medications, log: log, calendar: calendar)
        guard case let .take(dose, _)? = before.answer else {
            let spoken = DoseWidgetCopy.spoken(for: before, calendar: calendar)
            switch before.headline {
            case .noMedicines, .openApp: self.init(answer: nil, text: spoken)
            case .due, .late, .next, .dayOver: self.init(answer: nil, text: "\(Self.nothingWaiting) \(spoken)")
            }
            return
        }
        var after = log
        after.record(.taken, for: dose.id, at: now)
        let tap = after.storedRecord(for: dose.id).map { DoseWidgetTap(record: $0, at: now) }
        let shown = DoseWidgetTimeline.entry(at: now, medications: medications, log: after, calendar: calendar, answered: tap)
        self.init(answer: before.answer, text: DoseWidgetCopy.spoken(for: shown, calendar: calendar))
    }

    /// Before the app shared anything with its widget, or when what it
    /// shared cannot be read: nothing recorded, and the widget's words.
    public static let openApp = TookMedicineReply(answer: nil, text: "Mở ứng dụng để xem thuốc.")

    /// Said first when no dose is waiting.
    static let nothingWaiting = "Không có liều nào đang chờ."
}

extension DoseWidgetStore {
    /// "Tôi uống thuốc rồi", said to Siri at `now`: records the dose
    /// waiting (`TookMedicineReply`) as the widget's "ĐÃ UỐNG" records it,
    /// with the answers given on the widget, where the widget shows it at
    /// once, with "Hoàn tác", and the app takes it into its log when it
    /// next becomes active. Nothing is recorded when no dose waits, before
    /// the app shared anything, or without an App Group.
    @discardableResult
    public func recordTaken(at now: Date) -> TookMedicineReply {
        guard let snapshot, let log else { return .openApp }
        let reply = TookMedicineReply(at: now, medications: snapshot.medications, log: log, calendar: snapshot.calendar)
        guard let answer = reply.answer else { return reply }
        return record(answer.action, at: now) == nil ? .openApp : reply
    }
}

extension CaregiverWidgetCopy {
    /// What Siri answers the family's "Mẹ uống thuốc chưa?": what their
    /// widget shows (`spoken`), with no medicine named, as Siri may say it
    /// aloud, to anyone near, and on a locked phone. "Mẹ chưa xác nhận liều
    /// 07:00. Đã uống 1 trong 3 liều đến giờ. Cập nhật lúc 07:05."
    public static func siri(for entry: CaregiverWidgetEntry, calendar: Calendar) -> String {
        spoken(for: entry, calendar: calendar, namingMedicines: false)
    }
}

extension CaregiverWidgetStore {
    /// What Siri answers the family's "Mẹ uống thuốc chưa?" at `now`
    /// (`CaregiverWidgetCopy.siri`), from what the app last shared with
    /// their widget: the same news, so Siri and the widget never disagree.
    /// "Chưa có tin từ máy của Mẹ." before the app shared anything.
    ///
    /// - Parameter personName: how the family calls the parent, for before
    ///   the app shared anything; after, the name it shared.
    public func siriAnswer(at now: Date, personName: String) -> String {
        guard let snapshot else {
            let calendar = Calendar(identifier: .gregorian)
            return CaregiverWidgetCopy.siri(for: .awaitingNews(at: now, personName: personName, calendar: calendar), calendar: calendar)
        }
        let entry = CaregiverWidgetTimeline.entry(
            at: now, personName: snapshot.personName, medications: snapshot.medications, log: snapshot.log,
            updatedAt: snapshot.updatedAt, calendar: snapshot.calendar
        )
        return CaregiverWidgetCopy.siri(for: entry, calendar: snapshot.calendar)
    }
}
