#if os(iOS)
import IdeaLabCore
import SwiftUI

/// The adult child's screen: "has Mẹ taken her medicine?" answered in one
/// look, and one tap to call when the answer is no.
///
/// A late dose is the only thing that turns the screen amber — the idea's
/// promise is that nobody has to call to check; they call when it matters.
/// The week strip shows the pattern without turning care into a score.
///
/// "Nhắc lại" then reads "Đã nhắc lúc 8:42" for ten minutes (by `now`), so a
/// double tap cannot ring the parent's phone twice.
public struct CaregiverScreen: View {
    private let personName: String
    private let medications: [Medication]
    private let log: DoseLog
    private let now: Date
    private let calendar: Calendar
    private let onCall: () -> Void
    private let onRemind: (ScheduledDose) -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    /// When each late dose was last reminded from this screen, by `now`.
    @State private var remindedAt: [DoseID: Date] = [:]
    private static let remindAgainAfter: TimeInterval = 10 * 60

    /// - Parameters:
    ///   - personName: how the family calls them: "Mẹ", "Bố", "Bà nội".
    ///   - onRemind: send the parent's phone another alarm for this dose.
    public init(
        personName: String,
        medications: [Medication],
        log: DoseLog,
        now: Date = .now,
        calendar: Calendar = .current,
        onCall: @escaping () -> Void,
        onRemind: @escaping (ScheduledDose) -> Void
    ) {
        self.personName = personName
        self.medications = medications
        self.log = log
        self.now = now
        self.calendar = calendar
        self.onCall = onCall
        self.onRemind = onRemind
    }

    public var body: some View {
        let doses = DoseSchedule.doses(of: medications, onDayOf: now, calendar: calendar)
        let late = doses.filter {
            if case .late = DoseSchedule.status(of: $0, in: log, now: now) { true } else { false }
        }
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                summaryCard(DoseSchedule.summary(of: doses, in: log, now: now))
                ForEach(late) { dose in
                    lateCard(dose)
                }
                timelineCard(doses)
                weekCard
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
    }

    private func clock(_ date: Date) -> String {
        date.formatted(calendar.dateFormat(locale: locale).hour().minute())
    }

    private func summaryCard(_ summary: DoseSchedule.DaySummary) -> some View {
        HStack(spacing: LabSpacing.md) {
            Text(verbatim: String(personName.prefix(1)))
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(theme.accentText)
                .frame(width: 64, height: 64)
                .background(theme.tonalFill(.accent), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                Text(verbatim: personName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.label)
                Text(verbatim: summary.soFar == 0
                    ? "Chưa đến giờ uống liều nào"
                    : "Đã uống \(summary.taken)/\(summary.soFar) liều đến giờ")
                    .font(.headline)
                    .foregroundStyle(summary.late > 0 ? theme.warning : theme.text(.positive))
                Text(verbatim: "Cập nhật \(clock(now))")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .labCard()
        .accessibilityElement(children: .combine)
    }

    private func lateCard(_ dose: ScheduledDose) -> some View {
        let lateBy: TimeInterval = if case .late(let by) = DoseSchedule.status(of: dose, in: log, now: now) { by } else { 0 }
        return VStack(alignment: .leading, spacing: LabSpacing.sm) {
            Label {
                Text(verbatim: "\(personName) chưa xác nhận \(dose.medication.name) lúc \(clock(dose.time)) — trễ \(VietnameseDuration.string(lateBy))")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(theme.onWarningFill)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LabSpacing.sm) { lateActions(dose) }
                VStack(spacing: LabSpacing.sm) { lateActions(dose) }
            }
        }
        .padding(LabSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warningFill, in: RoundedRectangle(cornerRadius: LabRadius.lg, style: .continuous))
    }

    /// Dark-on-amber, like a caution sign: a solid "Gọi" and an outlined
    /// "Nhắc lại". Brand-blue on amber would clash and read as a different app.
    @ViewBuilder
    private func lateActions(_ dose: ScheduledDose) -> some View {
        let shape = RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous)
        Button {
            onCall()
        } label: {
            Label { Text(verbatim: "Gọi \(personName)") } icon: { Image(systemName: "phone.fill") }
                .font(.headline)
                .foregroundStyle(theme.warningFill)
                .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
                .background(theme.onWarningFill, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        let sentAt = recentReminder(for: dose)
        Button {
            // Read again here: a second tap can come before the view updates.
            guard recentReminder(for: dose) == nil else { return }
            remindedAt[dose.id] = now
            onRemind(dose)
        } label: {
            Label {
                Text(verbatim: sentAt.map { "Đã nhắc lúc \(clock($0))" } ?? "Nhắc lại")
            } icon: {
                Image(systemName: sentAt == nil ? "bell.badge.fill" : "checkmark")
            }
            .font(.headline)
            .foregroundStyle(theme.onWarningFill)
            .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
            .overlay { shape.strokeBorder(theme.onWarningFill, lineWidth: 2) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(sentAt != nil)
        .sensoryFeedback(trigger: sentAt) { _, new in new == nil ? nil : .success }
    }

    /// When this dose was reminded, if that was under ten minutes ago.
    private func recentReminder(for dose: ScheduledDose) -> Date? {
        guard let sent = remindedAt[dose.id], now.timeIntervalSince(sent) < Self.remindAgainAfter else { return nil }
        return sent
    }

    private func timelineCard(_ doses: [ScheduledDose]) -> some View {
        VStack(alignment: .leading, spacing: LabSpacing.xs) {
            LabSectionHeader("Hôm nay")
            ForEach(doses) { dose in
                DoseRow(dose, status: DoseSchedule.status(of: dose, in: log, now: now), calendar: calendar)
                if dose.id != doses.last?.id {
                    Divider().overlay(theme.separator)
                }
            }
        }
        .labCard()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("7 ngày qua")
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let doses = DoseSchedule.doses(of: medications, onDayOf: day, calendar: calendar)
                    DayAdherence(
                        label: day.formatted(calendar.dateFormat(locale: locale).weekday(.short)),
                        fraction: DoseSchedule.adherence(of: doses, in: log, now: now),
                        isToday: calendar.isDate(day, inSameDayAs: now)
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .labCard()
    }

    /// Today and the six days before it, oldest first.
    private var weekDays: [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

/// One day of the week strip: a ring filled to the share of doses taken.
private struct DayAdherence: View {
    let label: String
    let fraction: Double?
    let isToday: Bool
    @Environment(\.labTheme) private var theme

    var body: some View {
        VStack(spacing: LabSpacing.xxs) {
            ZStack {
                Circle().stroke(theme.surfaceSecondary, lineWidth: 5)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if fraction == 1 {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.text(.positive))
                }
            }
            .frame(width: 34, height: 34)
            Text(verbatim: label)
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? theme.label : theme.secondaryLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: fraction.map { "Uống \(Int(($0 * 100).rounded()))% số liều" } ?? "Chưa có liều nào đến giờ"))
    }

    private var tint: Color {
        guard let fraction else { return theme.separator }
        return fraction >= 1 ? theme.fill(.positive) : theme.warningFill
    }
}
#endif
