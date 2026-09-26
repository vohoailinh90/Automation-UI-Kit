#if os(iOS)
import IdeaLabCore
import SwiftUI

/// A VND amount in the ledger's colours: "+450.000 ₫" in green for Thu,
/// "−120.000 ₫" in red for Chi, plain for totals. Digits are tabular and roll
/// when the value changes.
///
/// The sign is written out, not only coloured, and VoiceOver hears "Thu" /
/// "Chi": colour alone must never carry meaning.
public struct AmountText: View {
    private let amount: Int64
    private let kind: LedgerEntry.Kind?
    private let showsSign: Bool
    private let font: Font
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - amount: whole đồng. With a `kind`, pass the positive amount.
    ///   - kind: `.income` / `.expense` add the sign and colour; `nil` shows
    ///     the amount as is (a total, which may be negative — a loss is red).
    ///   - showsSign: `false` drops the +/− where a label already says which
    ///     way the money went ("Tổng chi"), so it does not read as negative.
    public init(_ amount: Int64, kind: LedgerEntry.Kind? = nil, showsSign: Bool = true, font: Font = .body.weight(.semibold)) {
        self.amount = amount
        self.kind = kind
        self.showsSign = showsSign
        self.font = font
    }

    private var signed: Int64 {
        switch kind {
        case .income: amount
        case .expense: -amount
        case nil: amount
        }
    }

    private var text: String {
        // Zero has no direction: "0 ₫", never "+0 ₫" or a red "−0 ₫".
        guard kind != nil, amount != 0, showsSign else { return VND.string(amount) }
        return VND.signedString(signed)
    }

    private var color: Color {
        guard amount != 0 else { return theme.label }
        guard let kind else { return amount < 0 ? theme.text(.negative) : theme.label }
        return theme.text(LabTint(kind))
    }

    public var body: some View {
        Text(verbatim: text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(signed)))
            .accessibilityLabel(Text(verbatim: spokenLabel))
    }

    private var spokenLabel: String {
        switch kind {
        case .income: "Thu \(Self.spoken(amount))"
        case .expense: "Chi \(Self.spoken(amount))"
        case nil: Self.spoken(amount)
        }
    }

    /// "450.000 đồng" / "Âm 450.000 đồng". Says "Âm" rather than trusting
    /// VoiceOver to read U+2212 aloud.
    static func spoken(_ amount: Int64) -> String {
        let words = VND.string(amount == .min ? .max : abs(amount), style: .spoken)
        return amount < 0 ? "Âm \(words)" : words
    }
}

/// The big number on the entry screen. Shows a dim "0 ₫" when empty so the
/// screen never looks broken, and shrinks to fit rather than wrapping.
public struct AmountDisplay: View {
    private let amount: Int64
    private let kind: LedgerEntry.Kind
    @Environment(\.labTheme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56

    public init(_ amount: Int64, kind: LedgerEntry.Kind) {
        self.amount = amount
        self.kind = kind
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LabSpacing.xs) {
            Text(verbatim: VND.string(amount, style: .plain))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(amount)))
            Text(verbatim: "₫")
                .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(amount == 0 ? theme.secondaryLabel : theme.text(LabTint(kind)))
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.2), value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Số tiền"))
        .accessibilityValue(Text(verbatim: VND.string(amount, style: .spoken)))
    }
}

/// Thu / Chi switch. The selected side is filled with its own colour and
/// carries an icon (+ / −), so it reads without colour too.
public struct KindPicker: View {
    @Binding private var kind: LedgerEntry.Kind
    @Namespace private var selection
    @Environment(\.labTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(kind: Binding<LedgerEntry.Kind>) {
        _kind = kind
    }

    public var body: some View {
        HStack(spacing: LabSpacing.xxs) {
            segment(.income, title: "Thu", systemImage: "plus")
            segment(.expense, title: "Chi", systemImage: "minus")
        }
        .padding(LabSpacing.xxs)
        .background(theme.surfaceSecondary, in: Capsule())
        .sensoryFeedback(.selection, trigger: kind)
    }

    private func segment(_ value: LedgerEntry.Kind, title: LocalizedStringKey, systemImage: String) -> some View {
        let isSelected = kind == value
        return Button {
            if reduceMotion {
                kind = value
            } else {
                withAnimation(.snappy(duration: 0.25)) { kind = value }
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight - LabSpacing.xs)
                .foregroundStyle(isSelected ? theme.onFill : theme.secondaryLabel)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(theme.fill(LabTint(value)))
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Number pad tuned for đồng: 1–9, "000", 0, delete. Typing 450.000 is
/// 4-5-0-000. Every press is a button (VoiceOver and Switch Control work), with
/// a light haptic; a rejected press (13th digit, "000" on empty) buzzes as an error.
/// Long-press delete, or the VoiceOver action "Xoá hết", clears the amount.
public struct AmountKeypad: View {
    @Binding private var input: AmountInput
    @Environment(\.labTheme) private var theme
    @ScaledMetric(relativeTo: .title2) private var keyHeight: CGFloat = 58
    @State private var accepted = 0
    @State private var rejected = 0

    public init(input: Binding<AmountInput>) {
        _input = input
    }

    private enum Key: Hashable {
        case digit(Int)
        case thousand
        case delete
    }

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.thousand, .digit(0), .delete],
    ]

    public var body: some View {
        Grid(horizontalSpacing: LabSpacing.xs, verticalSpacing: LabSpacing.xs) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: accepted)
        .sensoryFeedback(.error, trigger: rejected)
    }

    private func keyButton(_ key: Key) -> some View {
        Button {
            press(key)
        } label: {
            keyLabel(key)
                .frame(maxWidth: .infinity, minHeight: max(keyHeight, theme.density.controlHeight))
                .foregroundStyle(theme.label)
                .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(Text(verbatim: accessibilityName(key)))
        .modifier(DeleteKeyExtras(isDelete: key == .delete, clear: { clear() }))
    }

    @ViewBuilder
    private func keyLabel(_ key: Key) -> some View {
        switch key {
        case .digit(let digit):
            Text(verbatim: String(digit)).font(.system(.title, design: .rounded, weight: .semibold))
        case .thousand:
            Text(verbatim: "000").font(.system(.title2, design: .rounded, weight: .semibold))
        case .delete:
            Image(systemName: "delete.left").font(.title2.weight(.semibold))
        }
    }

    private func accessibilityName(_ key: Key) -> String {
        switch key {
        case .digit(let digit): String(digit)
        case .thousand: "Ba số không"
        case .delete: "Xoá"
        }
    }

    private func press(_ key: Key) {
        let ok: Bool
        switch key {
        case .digit(let digit): ok = input.append(digit: digit)
        case .thousand: ok = input.appendThousand()
        case .delete:
            // Deleting from nothing is not a mistake worth a buzz — and it is
            // exactly what the tap that ends a long-press-to-clear does.
            guard !input.isEmpty else { return }
            ok = input.deleteLast()
        }
        if ok { accepted += 1 } else { rejected += 1 }
    }

    private func clear() {
        guard !input.isEmpty else { return }
        input.clear()
        accepted += 1
    }
}

/// Keys darken while held, like the system keyboard.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct DeleteKeyExtras: ViewModifier {
    let isDelete: Bool
    let clear: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDelete {
            content
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in clear() })
                .accessibilityAction(named: Text(verbatim: "Xoá hết"), clear)
        } else {
            content
        }
    }
}
#endif
