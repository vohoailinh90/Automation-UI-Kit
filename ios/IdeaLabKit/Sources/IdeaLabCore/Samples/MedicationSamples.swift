import Foundation

/// A deterministic household for previews and screenshots: four medicines,
/// a week of history, and a morning (09:41, 25/09/2026) where every status
/// shows at once — one dose taken, one late, one due, two still to come.
public enum MedicationSamples {
    public static let bloodPressure = Medication(
        id: UUID(uuidString: "5A1F0C3E-0000-4000-8000-000000000001")!,
        name: "Thuốc huyết áp", dose: "1 viên", instructions: "Sau ăn sáng",
        style: PillStyle(shape: .round, color: .white), times: [TimeOfDay(hour: 7)]
    )
    public static let diabetes = Medication(
        id: UUID(uuidString: "5A1F0C3E-0000-4000-8000-000000000002")!,
        name: "Thuốc tiểu đường", dose: "1 viên", instructions: "Trong bữa ăn",
        style: PillStyle(shape: .oblong, color: .yellow), times: [TimeOfDay(hour: 7), TimeOfDay(hour: 19)]
    )
    public static let vitaminD = Medication(
        id: UUID(uuidString: "5A1F0C3E-0000-4000-8000-000000000003")!,
        name: "Vitamin D", dose: "1 viên", instructions: "",
        style: PillStyle(shape: .capsule, color: .orange, secondColor: .cream), times: [TimeOfDay(hour: 9, minute: 30)]
    )
    public static let calcium = Medication(
        id: UUID(uuidString: "5A1F0C3E-0000-4000-8000-000000000004")!,
        name: "Canxi", dose: "1 viên", instructions: "Sau ăn trưa",
        style: PillStyle(shape: .oval, color: .lightBlue), times: [TimeOfDay(hour: 12)]
    )

    public static let medications = [bloodPressure, diabetes, vitaminD, calcium]

    /// Six days of history plus this morning, relative to `now`.
    /// Two misses in the week: an evening dose three days ago nobody
    /// confirmed, and a vitamin skipped five days ago.
    public static func log(now: Date = LedgerSamples.referenceNow, calendar: Calendar = LedgerSamples.calendar) -> DoseLog {
        var log = DoseLog()
        let today = calendar.startOfDay(for: now)
        for daysAgo in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            for (index, dose) in DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar).enumerated() {
                if daysAgo == 3 && dose.medication.id == diabetes.id && calendar.component(.hour, from: dose.time) == 19 {
                    continue  // never confirmed
                }
                let outcome: DoseRecord.Outcome = daysAgo == 5 && dose.medication.id == vitaminD.id ? .skipped : .taken
                let delay = TimeInterval((5 + (index * 7 + daysAgo * 3) % 20) * 60)
                log.record(outcome, for: dose.id, at: dose.time.addingTimeInterval(delay))
            }
        }
        // This morning: the blood-pressure pill at 07:12; the 07:00 diabetes
        // pill never confirmed (late); vitamin D at 09:30 is due right now.
        if let seven = TimeOfDay(hour: 7).date(onDayOf: today, calendar: calendar) {
            log.record(.taken, for: DoseID(medicationID: bloodPressure.id, time: seven), at: seven.addingTimeInterval(12 * 60))
        }
        return log
    }
}
