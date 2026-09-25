#if os(iOS)
import IdeaLabCore
import SwiftUI

/// One entry in a list: +/− badge, note, time, signed amount. At accessibility
/// text sizes it stacks vertically instead of truncating the note or amount.
public struct LedgerRow: View {
    private let entry: LedgerEntry
    @Environment(\.labTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 40

    public init(_ entry: LedgerEntry) {
        self.entry = entry
    }

    public var body: some View {
        let tint = LabTint(entry.kind)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LabSpacing.sm))

        layout {
            Image(systemName: entry.kind == .income ? "plus" : "minus")
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.text(tint))
                .frame(width: badgeSize, height: badgeSize)
                .background(theme.tonalFill(tint), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.note.isEmpty ? (entry.kind == .income ? "Khoản thu" : "Khoản chi") : entry.note)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.label)
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: LabSpacing.xs)
            }

            AmountText(entry.amount, kind: entry.kind)
        }
        .padding(.vertical, LabSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// A labelled figure: "Thu hôm nay · 1.450.000 ₫".
public struct StatTile: View {
    private let title: LocalizedStringKey
    private let amount: Int64
    private let kind: LedgerEntry.Kind?
    @Environment(\.labTheme) private var theme

    public init(_ title: LocalizedStringKey, amount: Int64, kind: LedgerEntry.Kind? = nil) {
        self.title = title
        self.amount = amount
        self.kind = kind
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LabSpacing.xxs) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.secondaryLabel)
            AmountText(amount, kind: kind, font: .title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
