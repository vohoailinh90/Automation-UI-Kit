#if os(iOS)
import IdeaLabCore
import SwiftUI

/// Month and quarter report with export. Household businesses declare by
/// quarter, so "Quý này" is one tap away and uses exact quarter boundaries.
///
/// The footnote is not decoration: the app keeps a book, it does not give tax
/// advice, and it should say so where the numbers are.
public struct LedgerReportScreen: View {
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case thisMonth
        case lastMonth
        case thisQuarter

        public var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .thisMonth: "Tháng này"
            case .lastMonth: "Tháng trước"
            case .thisQuarter: "Quý này"
            }
        }
    }

    public enum ExportFormat: Sendable {
        case pdf
        case spreadsheet
    }

    private let entries: [LedgerEntry]
    private let now: Date
    private let calendar: Calendar
    private let onExport: (ExportFormat, DateInterval) -> Void
    @State private var period: Period
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale

    public init(
        entries: [LedgerEntry],
        now: Date = .now,
        calendar: Calendar = .current,
        period: Period = .thisMonth,
        onExport: @escaping (ExportFormat, DateInterval) -> Void
    ) {
        self.entries = entries
        self.now = now
        self.calendar = calendar
        self.onExport = onExport
        _period = State(initialValue: period)
    }

    private var interval: DateInterval? {
        switch period {
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: previous)
        case .thisQuarter:
            return LedgerMath.quarter(containing: now, calendar: calendar)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                Picker("Kỳ báo cáo", selection: $period) {
                    ForEach(Period.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                if let interval {
                    summary(for: interval)
                    chart(for: interval)
                    export(interval)
                }

                Text("Số liệu ghi chép để bạn tham khảo khi kê khai. Ứng dụng không tư vấn thuế.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, LabSpacing.md)
            .padding(.vertical, LabSpacing.sm)
        }
        .background(theme.canvas.ignoresSafeArea())
    }

    private func summary(for interval: DateInterval) -> some View {
        let totals = LedgerMath.totals(of: entries, in: interval)
        return VStack(alignment: .leading, spacing: LabSpacing.md) {
            Text(rangeText(interval))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.secondaryLabel)
            VStack(alignment: .leading, spacing: LabSpacing.xxs) {
                Text(totals.net >= 0 ? "Lãi" : "Lỗ")
                    .font(.headline)
                    .foregroundStyle(theme.label)
                AmountText(totals.net, font: .system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LabSpacing.md) {
                    StatTile("Tổng thu", amount: totals.income, kind: .income)
                    StatTile("Tổng chi", amount: totals.expense, kind: .expense)
                }
                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    StatTile("Tổng thu", amount: totals.income, kind: .income)
                    StatTile("Tổng chi", amount: totals.expense, kind: .expense)
                }
            }
        }
        .labCard()
    }

    private func chart(for interval: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader(period == .thisQuarter ? "Theo tháng" : "Theo ngày")
            Group {
                if period == .thisQuarter {
                    CashFlowChart(months: LedgerMath.monthlyTotals(of: entries, in: interval, calendar: calendar), calendar: calendar)
                } else {
                    CashFlowChart(days: LedgerMath.dailyTotals(of: entries, inMonthOf: interval.start, calendar: calendar), calendar: calendar)
                }
            }
            .frame(height: 200)
            CashFlowLegend()
        }
        .labCard()
    }

    private func export(_ interval: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("Xuất sổ")
            Text("Gửi cho kế toán, in ra, hoặc lưu lại khi cần kê khai.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryLabel)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: LabSpacing.sm) { exportButtons(interval) }
                VStack(spacing: LabSpacing.sm) { exportButtons(interval) }
            }
        }
        .labCard()
    }

    @ViewBuilder
    private func exportButtons(_ interval: DateInterval) -> some View {
        Button {
            onExport(.pdf, interval)
        } label: {
            Label("PDF", systemImage: "doc.richtext")
        }
        .buttonStyle(.labTonal)
        Button {
            onExport(.spreadsheet, interval)
        } label: {
            Label("Excel", systemImage: "tablecells")
        }
        .buttonStyle(.labTonal)
    }

    /// "01/07/2026 – 30/09/2026": the end is exclusive internally, so the
    /// label shows the last day, not the first day of the next period.
    private func rangeText(_ interval: DateInterval) -> String {
        let style = calendar.dateFormat(locale: locale).day().month(.defaultDigits).year()
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(interval.start.formatted(style)) – \(lastDay.formatted(style))"
    }
}
#endif
