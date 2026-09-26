#if os(iOS)
import Charts
import IdeaLabCore
import SwiftUI

/// Money in above the axis, money out below it, one pair of bars per day
/// (or per month). A diverging chart answers the shop owner's real question
/// — "which days did I lose money?" — at a glance, where two side-by-side
/// bars make you compare heights.
public struct CashFlowChart: View {
    public struct Bar: Identifiable, Hashable, Sendable {
        public var start: Date
        public var totals: LedgerTotals
        public var id: Date { start }

        public init(start: Date, totals: LedgerTotals) {
            self.start = start
            self.totals = totals
        }
    }

    public enum Unit: Sendable {
        case day
        case month

        var calendarComponent: Calendar.Component { self == .day ? .day : .month }
    }

    private let bars: [Bar]
    private let unit: Unit
    private let calendar: Calendar
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale

    /// - Parameter calendar: the one the bars were bucketed with. Charts bin
    ///   dates and print labels in it; left to the device's calendar, a
    ///   Vietnam-time book viewed in UTC shifts every bar back one day.
    public init(bars: [Bar], unit: Unit, calendar: Calendar = .current) {
        self.bars = bars
        self.unit = unit
        self.calendar = calendar
    }

    public init(days: [DayTotals], calendar: Calendar = .current) {
        self.init(bars: days.map { Bar(start: $0.day, totals: $0.totals) }, unit: .day, calendar: calendar)
    }

    public init(months: [MonthTotals], calendar: Calendar = .current) {
        self.init(bars: months.map { Bar(start: $0.month, totals: $0.totals) }, unit: .month, calendar: calendar)
    }

    public var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Ngày", bar.start, unit: unit.calendarComponent, calendar: calendar),
                    y: .value("Thu", Double(bar.totals.income))
                )
                .foregroundStyle(theme.fill(.positive))
                .cornerRadius(3)
                .accessibilityLabel(Text(bar.start, format: dateFormat))
                .accessibilityValue(Text(verbatim: "Thu \(VND.string(bar.totals.income, style: .spoken))"))

                BarMark(
                    x: .value("Ngày", bar.start, unit: unit.calendarComponent, calendar: calendar),
                    y: .value("Chi", -Double(bar.totals.expense))
                )
                .foregroundStyle(theme.fill(.negative))
                .cornerRadius(3)
                .accessibilityLabel(Text(bar.start, format: dateFormat))
                .accessibilityValue(Text(verbatim: "Chi \(VND.string(bar.totals.expense, style: .spoken))"))
            }
            RuleMark(y: .value("0", 0))
                .foregroundStyle(theme.separator)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.separator.opacity(0.6))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(verbatim: VND.compact(Int64(amount)))
                            .foregroundStyle(theme.secondaryLabel)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisValues) { _ in
                AxisValueLabel(format: xAxisFormat, centered: true)
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .chartLegend(.hidden)
    }

    /// Every 7th day counted from the first bar (1, 8, 15, 22, 29), or every
    /// month. `.stride(by: .day, count: 7)` would align to week starts and
    /// label "31" under a September chart.
    private var xAxisValues: [Date] {
        stride(from: 0, to: bars.count, by: unit == .day ? 7 : 1).map { bars[$0].start }
    }

    private var xAxisFormat: Date.FormatStyle {
        let base = calendar.dateFormat(locale: locale)
        return unit == .day ? base.day() : base.month(.abbreviated)
    }

    private var dateFormat: Date.FormatStyle {
        let base = calendar.dateFormat(locale: locale)
        return unit == .day ? base.day().month(.wide).year() : base.month(.wide).year()
    }
}

/// The chart's legend, as real text with shapes — the colours alone are not
/// enough to tell Thu from Chi.
public struct CashFlowLegend: View {
    @Environment(\.labTheme) private var theme

    public init() {}

    public var body: some View {
        HStack(spacing: LabSpacing.md) {
            item("Thu", systemImage: "arrow.up", tint: .positive)
            item("Chi", systemImage: "arrow.down", tint: .negative)
        }
        .font(.footnote.weight(.semibold))
    }

    private func item(_ title: LocalizedStringKey, systemImage: String, tint: LabTint) -> some View {
        HStack(spacing: LabSpacing.xxs) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.fill(tint))
                .frame(width: 12, height: 12)
            Image(systemName: systemImage)
                .foregroundStyle(theme.text(tint))
            Text(title)
                .foregroundStyle(theme.secondaryLabel)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
