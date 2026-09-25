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
/// `onTaken` (and send the "đã uống" to the family from there).
public struct MedsTodayScreen: View {
    private let medications: [Medication]
    private let log: DoseLog
    private let now: Date
    private let calendar: Calendar
    private let onTaken: (ScheduledDose) -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale

    public init(
        medications: [Medication],
        log: DoseLog,
        now: Date = .now,
        calendar: Calendar = .current,
        onTaken: @escaping (ScheduledDose) -> Void
    ) {
        self.medications = medications
        self.log = log
        self.now = now
        self.calendar = calendar
        self.onTaken = onTaken
    }

    public var body: some View {
        let doses = DoseSchedule.doses(of: medications, onDayOf: now, calendar: calendar)
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                header
                if let current = DoseSchedule.current(of: doses, in: log, now: now) {
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

    private var greeting: String {
        switch calendar.component(.hour, from: now) {
        case 4..<11: "Chào buổi sáng"
        case 11..<14: "Chào buổi trưa"
        case 14..<18: "Chào buổi chiều"
        default: "Chào buổi tối"
        }
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
                Text(verbatim: "Uống lúc \(dose.time.formatted(calendar.dateFormat(locale: locale).hour().minute()))")
                    .font(.headline)
                    .foregroundStyle(theme.secondaryLabel)
            }
            BigActionButton("ĐÃ UỐNG", subtitle: "Bấm sau khi uống xong", systemImage: "checkmark.circle.fill", tint: .positive) {
                onTaken(dose)
            }
            .accessibilityHint(Text(verbatim: "Báo cho gia đình biết bạn đã uống \(dose.medication.name)"))
        }
        .frame(maxWidth: .infinity)
        .labCard(padding: LabSpacing.lg)
    }

    private func allDoneCard(next: ScheduledDose?) -> some View {
        VStack(spacing: LabSpacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(theme.text(.positive))
                .symbolEffect(.bounce, value: next?.id)
                .accessibilityHidden(true)
            Text(verbatim: "Chưa đến giờ uống thuốc")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(theme.label)
                .multilineTextAlignment(.center)
            if let next {
                Text(verbatim: "Tiếp theo: \(next.medication.name) lúc \(next.time.formatted(calendar.dateFormat(locale: locale).hour().minute()))")
                    .font(.title3)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            } else {
                Text(verbatim: "Hôm nay đã xong hết. Chúc ngủ ngon!")
                    .font(.title3)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
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
