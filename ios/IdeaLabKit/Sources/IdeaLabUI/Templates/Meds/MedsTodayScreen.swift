#if os(iOS)
import IdeaLabCore
import SwiftUI

/// The parent's screen of "Nhắc thuốc cho cha mẹ": one medicine at a time,
/// shown as the pill itself, and one enormous "ĐÃ UỐNG" button.
///
/// Built for `LabTheme.meds` (senior density): the button is at least 96 pt
/// tall — studies with older adults put the easiest targets at 14–17.5 mm —
/// and there is nothing else to press on the way. When no dose is waiting,
/// the screen says so plainly and names the next one, instead of showing an
/// empty list.
///
/// Template: feed it the medicines and the `DoseLog`; record the tap in
/// `onTaken` (and send the "đã uống" to the family from there). Pass
/// `onSkipped` too, so a dose the parent will not take can be answered
/// rather than waited out. Undo belongs to the app: record it with
/// `DoseLog.undo(_:at:)`, and the dose comes back here.
///
/// Each dose is answered once. After a tap the card shows the answer for two
/// seconds before the next medicine comes up, so a double tap — common with
/// shaky hands — cannot mark a second medicine the person never took.
public struct MedsTodayScreen: View {
    private let medications: [Medication]
    private let log: DoseLog
    private let now: Date
    private let calendar: Calendar
    private let onTaken: (ScheduledDose) -> Void
    private let onSkipped: ((ScheduledDose) -> Void)?
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    /// Doses answered here that the log does not show yet (the app may save
    /// them asynchronously). Each leaves once the log has its answer.
    @State private var answered: Set<DoseID> = []
    /// The answer just given, shown in place of the next dose for a moment.
    @State private var confirmation: Confirmation?

    private struct Confirmation: Hashable {
        let dose: ScheduledDose
        let outcome: DoseRecord.Outcome
    }

    /// - Parameters:
    ///   - now: the current time, which the screen follows: drive it from a
    ///     `TimelineView(.everyMinute)`, so a dose turns due and late on its own.
    ///   - calendar: the parent's. Its time zone decides which day a dose is on
    ///     and the times shown, so it must be the same on every family phone.
    public init(
        medications: [Medication],
        log: DoseLog,
        now: Date,
        calendar: Calendar,
        onTaken: @escaping (ScheduledDose) -> Void,
        onSkipped: ((ScheduledDose) -> Void)? = nil
    ) {
        self.medications = medications
        self.log = log
        self.now = now
        self.calendar = calendar
        self.onTaken = onTaken
        self.onSkipped = onSkipped
    }

    public var body: some View {
        let doses = DoseSchedule.doses(of: medications, onDayOf: now, calendar: calendar)
        // Today's, and last night's still waiting: at 00:30 the 21:00 pill is asked about.
        let waiting = DoseSchedule.waiting(of: medications, in: log, now: now, calendar: calendar)
            .filter { !answered.contains($0.id) }
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                header
                if let confirmation {
                    confirmationCard(confirmation.dose, outcome: confirmation.outcome)
                } else if let current = waiting.first {
                    currentCard(current)
                } else {
                    allDoneCard(next: DoseSchedule.next(of: doses, in: log, now: now))
                }
                todayCard(doses)
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
        .onChange(of: log) { _, new in
            // Saved: the log answers for these now.
            answered = answered.filter { new[$0] == nil }
            // Undone within the two seconds: the dose is back, so is the question.
            if let confirmation, !answered.contains(confirmation.dose.id), new[confirmation.dose.id] == nil {
                self.confirmation = nil
            }
        }
        .task(id: confirmation) {
            guard confirmation != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            confirmation = nil
        }
        .sensoryFeedback(trigger: confirmation) { _, new in
            new?.outcome == .taken ? .success : nil
        }
    }

    /// Reports a dose once, and holds the answer on screen before the next.
    private func answer(_ dose: ScheduledDose, _ outcome: DoseRecord.Outcome) {
        guard confirmation == nil, !answered.contains(dose.id) else { return }
        answered.insert(dose.id)
        confirmation = Confirmation(dose: dose, outcome: outcome)
        switch outcome {
        case .taken: onTaken(dose)
        case .skipped: onSkipped?(dose)
        case .cleared: break
        }
        let name = dose.medication.name
        AccessibilityNotification.Announcement(outcome == .taken ? "Đã uống \(name)" : "Đã bỏ qua \(name)").post()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LabSpacing.xxs) {
            Text(verbatim: greeting)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .accessibilityAddTraits(.isHeader)
            Text(now, format: calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits))
                .font(.title3.weight(.medium))
                .foregroundStyle(theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hour: Int { calendar.component(.hour, from: now) }

    private var greeting: String {
        switch hour {
        case 4..<11: "Chào buổi sáng"
        case 11..<14: "Chào buổi trưa"
        case 14..<18: "Chào buổi chiều"
        default: "Chào buổi tối"
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(calendar.dateFormat(locale: locale).hour().minute())
    }

    /// "07:00", or "21:00 hôm qua" for last night's dose still waiting.
    private func scheduledTime(_ dose: ScheduledDose) -> String {
        calendar.isDate(dose.time, inSameDayAs: now) ? clock(dose.time) : "\(clock(dose.time)) hôm qua"
    }

    private func currentCard(_ dose: ScheduledDose) -> some View {
        let status = DoseSchedule.status(of: dose, in: log, now: now)
        return VStack(spacing: LabSpacing.md) {
            DoseStatusBadge(status, scheduledAt: dose.time, calendar: calendar)
            PillView(dose.medication.style, size: 112)
                .padding(.vertical, LabSpacing.xs)
            VStack(spacing: LabSpacing.xxs) {
                Text(verbatim: dose.medication.name)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.label)
                    .multilineTextAlignment(.center)
                Text(verbatim: [dose.medication.dose, dose.medication.instructions].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.title3)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                Text(verbatim: "Uống lúc \(scheduledTime(dose))")
                    .font(.headline)
                    .foregroundStyle(theme.secondaryLabel)
            }
            BigActionButton("ĐÃ UỐNG", subtitle: "Bấm sau khi uống xong", systemImage: "checkmark.circle.fill", tint: .positive) {
                answer(dose, .taken)
            }
            .accessibilityHint(Text(verbatim: "Báo cho gia đình biết bạn đã uống \(dose.medication.name)"))
            if onSkipped != nil {
                // Quiet and set apart, so it is not pressed instead of ĐÃ UỐNG.
                Button {
                    answer(dose, .skipped)
                } label: {
                    Text(verbatim: "Không uống liều này")
                        .font(.headline)
                        .foregroundStyle(theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, LabSpacing.xs)
                .accessibilityHint(Text(verbatim: "Gia đình sẽ thấy liều này là bỏ qua"))
            }
        }
        .frame(maxWidth: .infinity)
        .labCard(padding: LabSpacing.lg)
    }

    private func confirmationCard(_ dose: ScheduledDose, outcome: DoseRecord.Outcome) -> some View {
        let isTaken = outcome == .taken
        return VStack(spacing: LabSpacing.md) {
            Image(systemName: isTaken ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(isTaken ? theme.text(.positive) : theme.secondaryLabel)
                .accessibilityHidden(true)
            Text(verbatim: isTaken ? "Đã uống \(dose.medication.name)" : "Đã bỏ qua \(dose.medication.name)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            Text(verbatim: isTaken ? "Gia đình sẽ thấy bạn đã uống." : "Gia đình sẽ thấy liều này là bỏ qua.")
                .font(.title3)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LabSpacing.xl)
        .labCard(padding: LabSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    private func allDoneCard(next: ScheduledDose?) -> some View {
        VStack(spacing: LabSpacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(theme.text(.positive))
                .symbolEffect(.bounce, value: next?.id)
                .accessibilityHidden(true)
            Text(verbatim: next == nil ? "Hôm nay không còn liều nào" : "Chưa đến giờ uống thuốc")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            Text(verbatim: next.map { "Tiếp theo: \($0.medication.name) lúc \(clock($0.time))" }
                ?? (hour >= 18 || hour < 4 ? "Chúc ngủ ngon!" : "Liều tiếp theo là ngày mai."))
                .font(.title3)
                .foregroundStyle(theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .labCard(padding: LabSpacing.lg)
    }

    private func todayCard(_ doses: [ScheduledDose]) -> some View {
        VStack(alignment: .leading, spacing: LabSpacing.xs) {
            LabSectionHeader("Thuốc hôm nay")
            ForEach(doses) { dose in
                DoseRow(dose, status: DoseSchedule.status(of: dose, in: log, now: now), calendar: calendar)
                if dose.id != doses.last?.id {
                    Divider().overlay(theme.separator)
                }
            }
        }
        .labCard()
    }
}
#endif
