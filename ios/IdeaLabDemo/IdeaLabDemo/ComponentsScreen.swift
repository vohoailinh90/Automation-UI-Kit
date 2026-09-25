import IdeaLabCore
import IdeaLabUI
import SwiftUI

/// Each component alone, live: the keypad types, the switch switches, the
/// toast undoes.
struct ComponentsScreen: View {
    @State private var kind = LedgerEntry.Kind.income
    @State private var input = AmountInput(value: 450_000)
    @State private var toast: LabToastMessage?
    @Environment(\.labTheme) private var theme

    private let samples = Array(LedgerSamples.entries().prefix(3))

    var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    LabSectionHeader("Nút hành động lớn")
                    HStack(spacing: LabSpacing.sm) {
                        BigActionButton("Thu", subtitle: "Tiền vào", systemImage: "plus.circle.fill", tint: .positive) {}
                        BigActionButton("Chi", subtitle: "Tiền ra", systemImage: "minus.circle.fill", tint: .negative) {}
                    }
                    Button("Nút chính") {}
                        .buttonStyle(.labFilled)
                    Button("Nút phụ") {}
                        .buttonStyle(.labTonal)
                }
                .labCard()

                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    LabSectionHeader("Nhập số tiền")
                    KindPicker(kind: $kind)
                    AmountDisplay(input.value, kind: kind)
                    AmountKeypad(input: $input)
                }
                .labCard()

                VStack(alignment: .leading, spacing: LabSpacing.xs) {
                    LabSectionHeader("Dòng sổ và số liệu")
                    HStack(spacing: LabSpacing.md) {
                        StatTile("Thu", amount: 1_450_000, kind: .income)
                        StatTile("Chi", amount: 220_000, kind: .expense)
                    }
                    ForEach(samples) { entry in
                        LedgerRow(entry)
                    }
                }
                .labCard()

                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    LabSectionHeader("Thông báo có hoàn tác")
                    Button("Hiện thông báo") {
                        toast = LabToastMessage(text: "Đã lưu khoản thu 450.000 ₫", actionTitle: "Hoàn tác")
                    }
                    .buttonStyle(.labTonal)
                }
                .labCard()
            }
            .padding(LabSpacing.md)
        }
        .background(theme.canvas.ignoresSafeArea())
        .labToast($toast)
    }
}
