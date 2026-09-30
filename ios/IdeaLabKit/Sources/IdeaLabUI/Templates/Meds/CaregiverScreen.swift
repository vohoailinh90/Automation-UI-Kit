#if os(iOS)
import IdeaLabCore
import IdeaLabNotifications
import SwiftUI

/// The adult child's screen: "has Mẹ taken her medicine?" answered in one
/// look, and one tap to call when the answer is no.
///
/// A late dose is the only thing that turns the screen amber — the idea's
/// promise is that nobody has to call to check; they call when it matters.
/// The week strip shows the pattern without turning care into a score.
///
/// "Nhắc lại" then reads "Đã nhắc lúc 08:42" for ten minutes (by `now`), so a
/// double tap cannot ring the parent's phone twice — nor leaving and opening
/// the screen again, as long as the app passes back `remindedAt`.
///
/// With `onAdd` or `onEdit`, the screen ends with the parent's medicines in
/// use ("Thuốc của Mẹ"), to add one or change one (`AddMedicationScreen`).
///
/// The promise holds only if this phone speaks up when a dose goes late
/// (`DoseAlerts`, `DoseNotifications`): given `alerts`, a card says when it
/// would not — not asked yet, turned off, or held back by a Focus.
public struct CaregiverScreen: View {
    private let personName: String
    private let medications: [Medication]
    private let log: DoseLog
    private let now: Date
    private let calendar: Calendar
    private let updatedAt: Date?
    private let remindedAt: [DoseID: Date]
    private let onCall: () -> Void
    private let onRemind: (ScheduledDose) -> Void
    private let onAdd: (() -> Void)?
    private let onEdit: ((Medication) -> Void)?
    private let alerts: DoseAlertAccess?
    private let onAlerts: (() -> Void)?
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Reminders sent from this screen, by `now`, that `remindedAt` may not
    /// show yet: a second tap can come before the app saves the first.
    @State private var sentHere: [DoseID: Date] = [:]
    private static let remindAgainAfter: TimeInterval = 10 * 60

    /// - Parameters:
    ///   - personName: how the family calls them: "Mẹ", "Bố", "Bà nội".
    ///   - now: the current time, which the screen follows: drive it from a
    ///     `TimelineView(.everyMinute)`, so a dose turns late on its own.
    ///   - calendar: the parent's, not this phone's: a child abroad sees the
    ///     parent's 07:00 as 07:00, on the parent's day.
    ///   - updatedAt: when the log last arrived from the parent's phone, shown
    ///     as "Cập nhật 07:00" so old news does not look fresh. `nil` hides it.
    ///   - remindedAt: when each dose was last reminded, as the app keeps it
    ///     (`onRemind` saves it): the ten-minute rule must outlive the screen.
    ///   - onRemind: send the parent's phone another alarm for this dose, and
    ///     save when, for `remindedAt`.
    ///   - onAdd: open "Thêm thuốc". With it or `onEdit`, the parent's
    ///     medicines are listed at the end of the screen; with neither, the
    ///     screen is only for keeping an eye on them.
    ///   - onEdit: open "Sửa thuốc" for this medicine: its latest version,
    ///     so `AddMedicationScreen(editing: medication.seriesID, in: …)`.
    ///   - alerts: what this phone lets the late-dose alerts do
    ///     (`DoseNotifications.access()`, read again when the app comes back
    ///     to the foreground). Unless they show as they happen, a card under
    ///     the late doses says so. `nil` shows no card.
    ///   - onAlerts: the card's button. Not asked yet: explain, then ask
    ///     (`PermissionPrimerScreen`, then `DoseNotifications.requestAccess()`).
    ///     Off or quiet: `DoseNotifications.openSettings()`.
    public init(
        personName: String,
        medications: [Medication],
        log: DoseLog,
        now: Date,
        calendar: Calendar,
        updatedAt: Date? = nil,
        remindedAt: [DoseID: Date] = [:],
        onCall: @escaping () -> Void,
        onRemind: @escaping (ScheduledDose) -> Void,
        onAdd: (() -> Void)? = nil,
        onEdit: ((Medication) -> Void)? = nil,
        alerts: DoseAlertAccess? = nil,
        onAlerts: (() -> Void)? = nil
    ) {
        self.personName = personName
        self.medications = medications
        self.log = log
        self.now = now
        self.calendar = calendar
        self.updatedAt = updatedAt
        self.remindedAt = remindedAt
        self.onCall = onCall
        self.onRemind = onRemind
        self.onAdd = onAdd
        self.onEdit = onEdit
        self.alerts = alerts
        self.onAlerts = onAlerts
    }

    public var body: some View {
        let doses = DoseSchedule.doses(of: medications, onDayOf: now, calendar: calendar)
        let waiting = DoseSchedule.waiting(of: medications, in: log, now: now, calendar: calendar)
        // Last night's dose still unanswered after midnight counts too: in the
        // late cards, and in the summary above them.
        let carried = waiting.filter { !calendar.isDate($0.time, inSameDayAs: now) }
        let late = waiting.filter {
            if case .late = DoseSchedule.status(of: $0, in: log, now: now) { true } else { false }
        }
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                summaryCard(DoseSchedule.summary(of: carried + doses, in: log, now: now), hasLate: !late.isEmpty)
                ForEach(late) { dose in
                    lateCard(dose)
                }
                if let alerts, let notice = AlertsNotice(alerts, personName: personName) {
                    alertsCard(notice)
                }
                timelineCard(doses)
                weekCard
                if onAdd != nil || onEdit != nil {
                    medicinesCard
                }
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
    }

    private func clock(_ date: Date) -> String {
        date.formatted(calendar.dateFormat(locale: locale).hour().minute())
    }

    /// Amber while a dose is late, green only when every dose so far was
    /// taken; a skipped or missed one leaves it plain, not green.
    private func summaryColor(_ summary: DoseSchedule.DaySummary, hasLate: Bool) -> Color {
        if hasLate { return theme.warning }
        if summary.soFar == 0 { return theme.secondaryLabel }
        return summary.taken == summary.soFar ? theme.text(.positive) : theme.label
    }

    private func summaryCard(_ summary: DoseSchedule.DaySummary, hasLate: Bool) -> some View {
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
                    .foregroundStyle(summaryColor(summary, hasLate: hasLate))
                if let updatedAt {
                    Text(verbatim: "Cập nhật \(updateTime(updatedAt))")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryLabel)
                }
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
                Text(verbatim: "\(personName) chưa xác nhận \(dose.medication.name) lúc \(scheduledTime(dose)) — trễ \(VietnameseDuration.string(lateBy))")
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
            sentHere[dose.id] = now
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

    /// "07:00" today; with the date on an earlier day, so stale news shows.
    private func updateTime(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock(date) }
        return date.formatted(calendar.dateFormat(locale: locale).day().month(.defaultDigits).hour().minute())
    }

    /// "07:00", or "21:00 hôm qua" for last night's dose still waiting.
    private func scheduledTime(_ dose: ScheduledDose) -> String {
        calendar.isDate(dose.time, inSameDayAs: now) ? clock(dose.time) : "\(clock(dose.time)) hôm qua"
    }

    /// When this dose was reminded, if that was under ten minutes ago.
    private func recentReminder(for dose: ScheduledDose) -> Date? {
        let sent = [remindedAt[dose.id], sentHere[dose.id]].compactMap { $0 }.max()
        guard let sent, now.timeIntervalSince(sent) < Self.remindAgainAfter else { return nil }
        return sent
    }

    // MARK: - Alerts

    /// What the alerts card says for each state that needs it.
    private struct AlertsNotice {
        let symbol: String
        let title: String
        let message: String
        let action: String

        init?(_ access: DoseAlertAccess, personName: String) {
            switch access {
            case .on:
                return nil
            case .notAsked:
                symbol = "bell.badge"
                title = "Nhận báo khi \(personName) quên thuốc"
                message = "Liều nào trễ \(VietnameseDuration.string(DoseSchedule.grace)) mà \(personName) chưa xác nhận, "
                    + "máy bạn sẽ báo ngay."
                action = "Bật thông báo"
            case .off:
                symbol = "bell.slash"
                title = "Thông báo đang tắt"
                message = "Bạn sẽ không biết khi \(personName) quên thuốc. Bật lại trong Cài đặt."
                action = "Mở Cài đặt"
            case .quiet:
                symbol = "moon"
                title = "Báo quên thuốc có thể đến muộn"
                message = "Máy bạn có thể giữ báo lại, như khi đang bật Tập trung. "
                    + "Trong Cài đặt, bật Biểu ngữ và “Nhạy cảm thời gian” cho ứng dụng để báo đến ngay."
                action = "Mở Cài đặt"
            }
        }
    }

    /// Not amber: only a late dose turns the screen amber.
    private func alertsCard(_ notice: AlertsNotice) -> some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            Label {
                VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                    Text(verbatim: notice.title)
                        .font(.headline)
                        .foregroundStyle(theme.label)
                    Text(verbatim: notice.message)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: notice.symbol)
                    .font(.headline)
                    .foregroundStyle(theme.accentText)
            }
            if let onAlerts {
                Button(action: onAlerts) {
                    Text(verbatim: notice.action)
                }
                .buttonStyle(.labTonal)
            }
        }
        .labCard()
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

    // MARK: - Medicines

    /// The parent's medicines in use or starting later, each opening "Sửa
    /// thuốc", then "Thêm thuốc".
    private var medicinesCard: some View {
        let current = MedicationChanges.current(in: medications, at: now)
        return VStack(alignment: .leading, spacing: LabSpacing.xs) {
            LabSectionHeader("Thuốc của \(personName)")
            ForEach(current) { medication in
                medicineRow(medication)
                if medication.id != current.last?.id || onAdd != nil {
                    Divider().overlay(theme.separator)
                }
            }
            if let onAdd {
                Button(action: onAdd) {
                    Label("Thêm thuốc", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .labCard()
    }

    /// The pill, the name, "07:00 · 21:00 · 1 viên", and what is coming: a
    /// change from tomorrow, or the course's last day. At accessibility sizes
    /// the pill goes above the words, as in `DoseRow`.
    private func medicineRow(_ medication: Medication) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LabSpacing.sm))
        return Button {
            onEdit?(medication)
        } label: {
            HStack(spacing: LabSpacing.xs) {
                layout {
                    PillView(medication.style, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: medication.name)
                            .font(.headline)
                            .foregroundStyle(theme.label)
                        Text(verbatim: (medication.times.map(\.description) + [medication.dose]).joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryLabel)
                        if let note = medicineNote(medication) {
                            Text(verbatim: note)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.accentText)
                        }
                    }
                }
                Spacer(minLength: 0)
                if onEdit != nil {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryLabel)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, LabSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onEdit == nil)
        .accessibilityHint(Text(verbatim: onEdit == nil ? "" : "Sửa thuốc"))
    }

    /// "Thay đổi từ Thứ Bảy, 26/9" for a change that starts later, "Bắt đầu
    /// từ …" for a medicine that has not started yet, and "đến hết Thứ Năm,
    /// 1/10" for a course; `nil` for one taken every day from now on.
    private func medicineNote(_ medication: Medication) -> String? {
        let end = medication.endDate.map(dayName)
        if let start = medication.startDate, start > now {
            let isChange = MedicationChanges.versions(of: medication.seriesID, in: medications).count > 1
            return (isChange ? "Thay đổi từ " : "Bắt đầu từ ") + dayName(start) + (end.map { ", đến hết \($0)" } ?? "")
        }
        return end.map { "Đến hết \($0)" }
    }

    /// "Thứ Năm, 1/10", in the parent's calendar.
    private func dayName(_ date: Date) -> String {
        date.formatted(calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits))
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
        .accessibilityValue(Text(verbatim: fraction.map { "Uống \(Int(($0 * 100).rounded()))% số liều" } ?? "Chưa có liều nào để tính"))
    }

    private var tint: Color {
        guard let fraction else { return theme.separator }
        return fraction >= 1 ? theme.fill(.positive) : theme.warningFill
    }
}
#endif
