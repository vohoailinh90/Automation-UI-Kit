import Foundation

/// Changing or stopping a medicine without rewriting its past. Each
/// `Medication` is one version of it; the versions of one medicine share a
/// `seriesID`.
///
/// A change to when, how much or how it is taken ends the version in use with
/// today and starts a new one tomorrow, so the days already lived keep their
/// doses and answers. Today stays as it was: a pill taken this morning is
/// never asked for again, and none is dropped. Mapping this morning's doses
/// onto new times would have to guess which of them were taken. A change to
/// only the name, the look or how long it lasts changes the versions in use
/// in place.
public enum MedicationChanges {
    /// What saving the edit form does, for the form to say so.
    public enum Effect: Hashable, Sendable {
        /// Nothing changes.
        case unchanged
        /// The name, the look or how long it lasts changes, from now and for
        /// today's doses too.
        case inPlace
        /// When, how much or how it is taken changes from this moment, the
        /// start of tomorrow in the parent's calendar. Today stays as it was.
        case fromTomorrow(Date)
        /// When, how much or how it is taken changes, but the course ends
        /// today: no day is left to take it the new way. Nothing is saved,
        /// the rest of the form included, until the course runs past today
        /// or the change is undone. Saving only the rest would drop the
        /// change without a word.
        case noDayLeft
        /// The last day the form gives the course went by while the form
        /// stayed open. Nothing is saved until the days are picked again.
        case endPassed
        /// The medicine is no longer in use: its course is over, it was
        /// stopped, or it is not in the list. There is nothing left to
        /// change, so nothing is saved. A form left open past the course's
        /// last day ends up here.
        case notInUse
    }

    /// The versions of the medicine `seriesID`, earliest first.
    public static func versions(of seriesID: UUID, in medications: [Medication]) -> [Medication] {
        medications
            .filter { $0.seriesID == seriesID }
            .sorted { ($0.startDate ?? .distantPast, $0.id.uuidString) < ($1.startDate ?? .distantPast, $1.id.uuidString) }
    }

    /// The version the edit form starts from: the last one, which says how
    /// the medicine is taken from now on. `nil` for an unknown series.
    public static func latest(of seriesID: UUID, in medications: [Medication]) -> Medication? {
        versions(of: seriesID, in: medications).last
    }

    /// Whether the medicine `seriesID` is in use at `now` or starts later:
    /// whether there is anything left to change or to stop.
    public static func isInUse(_ seriesID: UUID, in medications: [Medication], at now: Date) -> Bool {
        medications.contains { $0.seriesID == seriesID && $0.isCurrent(at: now) }
    }

    /// The medicines in use at `now` or starting later, one per series (its
    /// latest version), by name: the ones there is something to change about.
    public static func current(in medications: [Medication], at now: Date) -> [Medication] {
        Set(medications.filter { $0.isCurrent(at: now) }.map(\.seriesID))
            .compactMap { latest(of: $0, in: medications) }
            .sorted { ($0.name, $0.seriesID.uuidString) < ($1.name, $1.seriesID.uuidString) }
    }

    /// What saving `draft` for the medicine `seriesID` would do.
    public static func effect(
        of draft: MedicationDraft, on seriesID: UUID, in medications: [Medication], now: Date, calendar: Calendar
    ) -> Effect {
        let changed: [Medication]
        switch change(draft, to: seriesID, in: medications, now: now, calendar: calendar, newID: UUID()) {
        case let .saves(list): changed = list
        case let .refused(effect): return effect
        }
        guard changed != medications, let latest = latest(of: seriesID, in: medications) else { return .unchanged }
        if let tomorrow = startOfTomorrow(after: now, calendar: calendar),
           changed.contains(where: { $0.seriesID == seriesID && $0.startDate == tomorrow && $0.id != latest.id }) {
            return .fromTomorrow(tomorrow)
        }
        return .inPlace
    }

    /// `medications` with the medicine `seriesID` changed as `draft` says, in
    /// the same order, a new version added last. `nil` while the draft has
    /// problems, for a medicine unknown or no longer in use at `now`, or for a
    /// course ending before `now` (a form kept from days ago): that would
    /// take answered doses out of the history. `effect` says which.
    ///
    /// - A change to times, dose or instructions: the versions in use end
    ///   with today, one due to start later is replaced, and a new version
    ///   (`newID`) starts tomorrow with everything the form says. A course's
    ///   days count from today, as the form says ("tính cả hôm nay"). A
    ///   course that ends today leaves the new version no day: `nil`, and
    ///   the form says why (`Effect.noDayLeft`).
    /// - Otherwise, the versions in use or to come take the new name, look
    ///   and end in place. A version that would start after the new end is
    ///   dropped.
    public static func applying(
        _ draft: MedicationDraft, to seriesID: UUID, in medications: [Medication], now: Date, calendar: Calendar,
        newID: UUID = UUID()
    ) -> [Medication]? {
        if case let .saves(list) = change(draft, to: seriesID, in: medications, now: now, calendar: calendar, newID: newID) {
            return list
        }
        return nil
    }

    /// What saving `draft` comes to: the list to save, or what the form says
    /// instead.
    private enum Change {
        case saves([Medication])
        case refused(Effect)
    }

    private static func change(
        _ draft: MedicationDraft, to seriesID: UUID, in medications: [Medication], now: Date, calendar: Calendar,
        newID: UUID
    ) -> Change {
        guard let latest = latest(of: seriesID, in: medications), isInUse(seriesID, in: medications, at: now)
        else { return .refused(.notInUse) }
        // Incomplete: the form says what is missing, whatever the effect.
        guard let edited = draft.medication(id: newID, startingAt: now, calendar: calendar) else { return .refused(.unchanged) }
        let newEnd = edited.endDate
        if let newEnd, newEnd < now { return .refused(.endPassed) }
        if draft.changesRegimen(of: latest) {
            guard let tomorrow = startOfTomorrow(after: now, calendar: calendar) else { return .refused(.unchanged) }
            if let newEnd, newEnd < tomorrow { return .refused(.noDayLeft) }
            var next = edited
            next.seriesID = seriesID
            next.startDate = tomorrow
            let ended = medications.compactMap { medication -> Medication? in
                guard medication.seriesID == seriesID else { return medication }
                if let start = medication.startDate, start >= tomorrow { return nil }
                var medication = medication
                if medication.endDate.map({ $0 >= tomorrow }) ?? true {
                    medication.endDate = tomorrow.addingTimeInterval(-1)
                }
                return medication
            }
            return .saves(ended + [next])
        }
        return .saves(medications.compactMap { medication -> Medication? in
            guard medication.seriesID == seriesID, medication.isCurrent(at: now) else { return medication }
            if let start = medication.startDate, let newEnd, start > newEnd { return nil }
            var medication = medication
            medication.name = edited.name
            medication.style = edited.style
            // The last version says how long the medicine lasts; the one in
            // use before it already ends where the last one starts.
            if medication.id == latest.id {
                medication.endDate = newEnd
            }
            return medication
        })
    }

    /// `medications` with the medicine `seriesID` stopped at `now`, as a
    /// doctor's "ngừng thuốc" means: no dose from `now` on, and none asked
    /// about. A dose still waiting for an answer stops waiting and counts as
    /// missed, as it was when the medicine was stopped. That includes last
    /// night's 21:00 from a version that ended at midnight, so every version
    /// that has started records the stop, not only the one in use. A version
    /// due to start later is dropped. The past, answers included, stays as
    /// it was.
    ///
    /// A medicine no longer in use (`isInUse`) has nothing to stop: its
    /// course is over, or it was stopped already. The list comes back as it
    /// was, with no stop recorded, and a stop made earlier is never moved.
    public static func stopping(_ seriesID: UUID, in medications: [Medication], now: Date) -> [Medication] {
        guard isInUse(seriesID, in: medications, at: now) else { return medications }
        return medications.compactMap { medication -> Medication? in
            guard medication.seriesID == seriesID else { return medication }
            if let start = medication.startDate, start > now { return nil }
            var medication = medication
            medication.stoppedAt = min(medication.stoppedAt ?? now, now)
            return medication
        }
    }

    private static func startOfTomorrow(after now: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }
}
