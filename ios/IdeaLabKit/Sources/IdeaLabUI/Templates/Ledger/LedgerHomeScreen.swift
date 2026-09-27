#if os(iOS)
import IdeaLabCore
import SwiftUI

/// Home of "Sổ thu chi 10 giây": today's result first, the month at a glance,
/// the latest entries, and two huge buttons that are always in reach.
///
/// The whole screen serves one job — recording money in under ten seconds —
/// so "Thu" and "Chi" live in a bottom tray the thumb can reach, never in a
/// menu or a "+" that first asks which kind.
///
/// Template: put it inside your own `NavigationStack` and feed it your data.
///
/// With `readsBack`, a speaker button in the toolbar turns the readback on
/// and off: the app says each saved entry aloud (`LabSpeaker`,
/// `LedgerEntry.readback`), as a shop's payment speaker does.
public struct LedgerHomeScreen: View {
    private let entries: [LedgerEntry]
    private let now: Date
    private let calendar: Calendar
    private let readsBack: Binding<Bool>?
    private let onAdd: (LedgerEntry.Kind) -> Void
    private let onShowReport: () -> Void
    private let onShowAll: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale

    /// - Parameters:
    ///   - entries: the book, any order.
    ///   - now: injected so previews and screenshots are stable.
    ///   - calendar: decides where "today" and "this month" start.
    ///   - readsBack: whether the app says saved entries aloud; the toolbar
    ///     button that turns it on and off shows only with one.
    public init(
        entries: [LedgerEntry],
        now: Date = .now,
        calendar: Calendar = .current,
        readsBack: Binding<Bool>? = nil,
        onAdd: @escaping (LedgerEntry.Kind) -> Void,
        onShowReport: @escaping () -> Void = {},
        onShowAll: @escaping () -> Void = {}
    ) {
        self.entries = entries
        self.now = now
        self.calendar = calendar
        self.readsBack = readsBack
        self.onAdd = onAdd
        self.onShowReport = onShowReport
        self.onShowAll = onShowAll
    }

    private var today: LedgerTotals {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return LedgerMath.totals(of: entries, in: DateInterval(start: start, end: end))
    }

    private var recent: [LedgerEntry] {
        Array(entries.filter { $0.date <= now }.sorted { $0.date > $1.date }.prefix(5))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                todayCard
                monthCard
                recentCard
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The "Đã lưu · Hoàn tác" toast shows above Thu / Chi, not over them.
            EntryTray(onAdd: onAdd)
                .labBottomBar()
        }
        .toolbar {
            if let readsBack {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: readsBack) {
                        Label {
                            Text(verbatim: "Đọc lại số tiền")
                        } icon: {
                            Image(systemName: readsBack.wrappedValue ? "speaker.wave.2.fill" : "speaker.slash")
                        }
                    }
                    .accessibilityHint(Text(verbatim: "Đọc to số tiền mỗi khi lưu một khoản."))
                }
            }
        }
    }

    private var todayCard: some View {
        let totals = today
        return VStack(alignment: .leading, spacing: LabSpacing.md) {
            VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                Text(now, format: calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondaryLabel)
                Text(totals.net >= 0 ? "Lãi hôm nay" : "Lỗ hôm nay")
                    .font(.headline)
                    .foregroundStyle(theme.label)
                AmountText(totals.net, font: .system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Divider().overlay(theme.separator)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LabSpacing.md) {
                    StatTile("Thu", amount: totals.income, kind: .income)
                    StatTile("Chi", amount: totals.expense, kind: .expense)
                }
                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    StatTile("Thu", amount: totals.income, kind: .income)
                    StatTile("Chi", amount: totals.expense, kind: .expense)
                }
            }
        }
        .labCard()
    }

    private var monthCard: some View {
        let days = LedgerMath.dailyTotals(of: entries, inMonthOf: now, calendar: calendar)
        let month = days.map(\.totals).reduce(LedgerTotals(), +)
        return VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("Tháng này") {
                Button("Báo cáo", action: onShowReport)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    monthNetTitle(month)
                    Spacer()
                    AmountText(month.net, font: .headline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    monthNetTitle(month)
                    AmountText(month.net, font: .headline)
                }
            }
            CashFlowChart(days: days, calendar: calendar)
                .frame(height: 160)
            CashFlowLegend()
        }
        .labCard()
    }

    private func monthNetTitle(_ month: LedgerTotals) -> some View {
        Text(month.net >= 0 ? "Lãi tháng" : "Lỗ tháng")
            .font(.subheadline)
            .foregroundStyle(theme.secondaryLabel)
    }

    private var recentCard: some View {
        let recent = self.recent
        return VStack(alignment: .leading, spacing: LabSpacing.xs) {
            LabSectionHeader("Gần đây") {
                if !recent.isEmpty {
                    Button("Xem tất cả", action: onShowAll)
                }
            }
            if recent.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có khoản nào", systemImage: "book.closed")
                } description: {
                    Text("Bấm Thu hoặc Chi bên dưới để ghi khoản đầu tiên.")
                }
            } else {
                ForEach(recent) { entry in
                    LedgerRow(entry, calendar: calendar)
                    if entry.id != recent.last?.id {
                        Divider().overlay(theme.separator)
                    }
                }
            }
        }
        .labCard()
    }
}

/// The two big buttons, on glass so the list scrolls visibly underneath.
public struct EntryTray: View {
    private let onAdd: (LedgerEntry.Kind) -> Void

    public init(onAdd: @escaping (LedgerEntry.Kind) -> Void) {
        self.onAdd = onAdd
    }

    public var body: some View {
        HStack(spacing: LabSpacing.sm) {
            BigActionButton("Thu", subtitle: "Tiền vào", systemImage: "plus.circle.fill", tint: .positive) {
                onAdd(.income)
            }
            BigActionButton("Chi", subtitle: "Tiền ra", systemImage: "minus.circle.fill", tint: .negative) {
                onAdd(.expense)
            }
        }
        .padding(LabSpacing.sm)
        .labGlass(in: RoundedRectangle(cornerRadius: LabRadius.xl, style: .continuous))
        .padding(.horizontal, LabSpacing.sm)
        .padding(.bottom, LabSpacing.xxs)
    }
}
#endif
