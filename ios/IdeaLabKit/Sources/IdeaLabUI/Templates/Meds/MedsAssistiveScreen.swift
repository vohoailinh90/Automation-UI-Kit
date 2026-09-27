#if os(iOS)
import IdeaLabCore
import SwiftUI

/// The parent's screen in Assistive Access, the simplified iOS mode for people
/// with cognitive disabilities: what the app's `AssistiveAccess` scene (iOS 26)
/// shows, in a `NavigationStack`, in place of `MedsTodayScreen`.
///
/// One step at a time, as Apple asks of apps in this mode. First the medicine
/// to take, drawn as the pill, and one button: "ĐÃ UỐNG". Then what was
/// answered, and the next medicine only when the person asks for it.
///
/// - Nothing changes on a timer: the answer stays on screen until the person
///   moves on, or leaves the app.
/// - There is no second choice to weigh: a dose not taken is simply not
///   answered, and the family sees that. Undo belongs to the family's screen.
/// - Every control has a picture and a word, and the navigation title an
///   icon.
/// - The button to go on is not where "ĐÃ UỐNG" was, so a shaky double tap
///   cannot answer the next medicine.
public struct MedsAssistiveScreen: View {
    private let medications: [Medication]
    private let log: DoseLog
    private let now: Date
    private let calendar: Calendar
    private let onTaken: (ScheduledDose) -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    /// Doses answered here that the log does not show yet — the app may save
    /// them asynchronously — with what the log held for each then. One leaves
    /// once the log's record for it changes, or a minute on if the save never
    /// arrives.
    @State private var pending: [DoseID: PendingAnswer] = [:]
    /// The dose just answered, on screen until the person moves on.
    @State private var answered: ScheduledDose?

    private struct PendingAnswer: Hashable {
        let stored: DoseRecord?
        let since: Date
    }

    /// - Parameters:
    ///   - now: the current time, which the screen follows: drive it from a
    ///     `TimelineView(.everyMinute)`, so a dose comes up when it is due.
    ///   - calendar: the parent's, as on every family phone.
    ///   - onTaken: record the answer, as `MedsTodayScreen`'s `onTaken` does.
    public init(
        medications: [Medication],
        log: DoseLog,
        now: Date,
        calendar: Calendar,
        onTaken: @escaping (ScheduledDose) -> Void
    ) {
        self.medications = medications
        self.log = log
        self.now = now
        self.calendar = calendar
        self.onTaken = onTaken
    }

    public var body: some View {
        // Today's, and last night's still waiting: at 00:30 the 21:00 pill is asked about.
        let waiting = DoseSchedule.waiting(of: medications, in: log, now: now, calendar: calendar)
            .filter { !isPending($0.id) }
        ScrollView {
            Group {
                if let answered {
                    answeredCard(answered, next: waiting.first)
                } else if let dose = waiting.first {
                    doseCard(dose)
                } else {
                    restCard
                }
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "Uống thuốc"))
        .modifier(AssistiveNavigationIcon(systemImage: "pills.fill"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Only with a dose to answer: after an answer the bottom is empty,
            // so a second tap there lands on nothing.
            if answered == nil, let dose = waiting.first {
                BigActionButton("ĐÃ UỐNG", subtitle: "Bấm sau khi uống xong", systemImage: "checkmark.circle.fill", tint: .positive) {
                    take(dose)
                }
                .accessibilityHint(Text(verbatim: "Báo cho gia đình biết bạn đã uống \(dose.medication.name)"))
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.xs)
                .background(theme.canvas)
                .labBottomBar()
            }
        }
        .onChange(of: log) { _, new in
            // Saved, undone or answered on another phone: no longer pending.
            pending = pending.filter { new.storedRecord(for: $0.key) == $0.value.stored }
            // Undone elsewhere: the dose is back, so is the question.
            if let answered, pending[answered.id] == nil, new[answered.id] == nil {
                self.answered = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back in the app, it shows where things stand now.
            if phase == .background { answered = nil }
        }
        .sensoryFeedback(.success, trigger: answered) { _, new in new != nil }
    }

    private func isPending(_ id: DoseID) -> Bool {
        pending[id].map { now.timeIntervalSince($0.since) < 60 } ?? false
    }

    /// Answers a dose once.
    private func take(_ dose: ScheduledDose) {
        guard answered == nil, !isPending(dose.id) else { return }
        pending[dose.id] = PendingAnswer(stored: log.storedRecord(for: dose.id), since: now)
        answered = dose
        onTaken(dose)
        AccessibilityNotification.Announcement("Đã uống \(dose.medication.name)").post()
    }

    private func clock(_ date: Date) -> String {
        date.formatted(calendar.dateFormat(locale: locale).hour().minute())
    }

    /// "07:00", or "21:00 hôm qua" for last night's dose still waiting.
    private func scheduledTime(_ dose: ScheduledDose) -> String {
        calendar.isDate(dose.time, inSameDayAs: now) ? clock(dose.time) : "\(clock(dose.time)) hôm qua"
    }

    /// The pill as it is in the hand, the name, how to take it, and when.
    private func doseCard(_ dose: ScheduledDose) -> some View {
        VStack(spacing: LabSpacing.md) {
            PillView(dose.medication.style, size: 140)
                .padding(.vertical, LabSpacing.sm)
            Text(verbatim: dose.medication.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            let how = [dose.medication.dose, dose.medication.instructions].filter { !$0.isEmpty }.joined(separator: " · ")
            if !how.isEmpty {
                Text(verbatim: how)
                    .font(.title2)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            Label {
                Text(verbatim: "Uống lúc \(scheduledTime(dose))")
            } icon: {
                Image(systemName: "clock.fill")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(theme.label)
        }
        .frame(maxWidth: .infinity)
        .labCard(padding: LabSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    /// The answer, until the person moves on: to the next medicine if one is
    /// waiting, by a button in the card rather than where "ĐÃ UỐNG" was.
    private func answeredCard(_ dose: ScheduledDose, next: ScheduledDose?) -> some View {
        VStack(spacing: LabSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(theme.text(.positive))
                .accessibilityHidden(true)
            Text(verbatim: "Đã uống \(dose.medication.name)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            Text(verbatim: "Gia đình sẽ thấy bạn đã uống.")
                .font(.title3)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
            if let next {
                Button {
                    answered = nil
                } label: {
                    Label {
                        Text(verbatim: "Thuốc tiếp theo")
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                }
                .buttonStyle(.labTonal)
                .accessibilityHint(Text(verbatim: next.medication.name))
                .padding(.top, LabSpacing.sm)
            } else if let line = nextLine {
                Text(verbatim: line)
                    .font(.title3)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LabSpacing.lg)
        .labCard(padding: LabSpacing.lg)
    }

    /// Nothing to answer: says so, and when the next medicine is.
    private var restCard: some View {
        VStack(spacing: LabSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(theme.text(.positive))
                .accessibilityHidden(true)
            Text(verbatim: nextToday == nil ? "Hôm nay không còn liều nào" : "Chưa đến giờ uống thuốc")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            if let line = nextLine {
                Text(verbatim: line)
                    .font(.title3)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LabSpacing.lg)
        .labCard(padding: LabSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    /// Today's next dose not yet due.
    private var nextToday: ScheduledDose? {
        let doses = DoseSchedule.doses(of: medications, onDayOf: now, calendar: calendar)
        return DoseSchedule.next(of: doses, in: log, now: now)
    }

    /// "Tiếp theo: Canxi lúc 12:00", or tomorrow's first dose when today has
    /// none left; `nil` when there is none, as when a course has ended.
    private var nextLine: String? {
        if let next = nextToday {
            return "Tiếp theo: \(next.medication.name) lúc \(clock(next.time))"
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            .flatMap { DoseSchedule.doses(of: medications, onDayOf: $0, calendar: calendar).first }
        return tomorrow.map { "Ngày mai: \($0.medication.name) lúc \(clock($0.time))" }
    }
}

/// The icon Assistive Access shows beside the navigation title, on iOS 26.
private struct AssistiveNavigationIcon: ViewModifier {
    let systemImage: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.assistiveAccessNavigationIcon(systemImage: systemImage)
        } else {
            content
        }
    }
}
#endif
