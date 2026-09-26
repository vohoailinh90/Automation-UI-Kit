import IdeaLabCore
import IdeaLabUI
import SwiftUI

/// The current palette, each role with its contrast on the card it sits on,
/// and the type scale with the Vietnamese letters most likely to clip.
struct TokensScreen: View {
    @Environment(\.labTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var isDark: Bool { colorScheme == .dark }
    private var isHigh: Bool { contrast == .increased }

    var body: some View {
        ScrollView {
            VStack(spacing: LabSpacing.md) {
                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    LabSectionHeader("Chữ trên nền thẻ")
                    swatchRow("label", theme.palette.label, on: theme.palette.surface)
                    swatchRow("secondaryLabel", theme.palette.secondaryLabel, on: theme.palette.surface)
                    swatchRow("accentText", theme.palette.accentText, on: theme.palette.surface)
                    swatchRow("positive (Thu)", theme.palette.positive, on: theme.palette.surface)
                    swatchRow("negative (Chi)", theme.palette.negative, on: theme.palette.surface)
                    swatchRow("warning", theme.palette.warning, on: theme.palette.surface)
                }
                .labCard()

                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    LabSectionHeader("Mảng màu và chữ trên nó")
                    fillRow("accent", theme.palette.accent, text: theme.palette.onFill)
                    fillRow("positiveFill", theme.palette.positiveFill, text: theme.palette.onFill)
                    fillRow("negativeFill", theme.palette.negativeFill, text: theme.palette.onFill)
                    fillRow("warningFill", theme.palette.warningFill, text: theme.palette.onWarningFill)
                }
                .labCard()

                VStack(alignment: .leading, spacing: LabSpacing.sm) {
                    LabSectionHeader("Cỡ chữ (Dynamic Type)")
                    Text("Sổ thu chi 10 giây").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Lãi hôm nay").font(.title2.weight(.bold))
                    Text("Nhập hàng · Tiền điện").font(.headline)
                    Text("Bấm Thu hoặc Chi để ghi khoản đầu tiên.").font(.body)
                    Text("Dấu chồng dễ bị cắt: Ệ Ỗ Ữ Ặ Ẫ — ĐÃ UỐNG").font(.body.weight(.semibold))
                    Text("Ghi chú nhỏ nhất nên dùng: footnote").font(.footnote).foregroundStyle(theme.secondaryLabel)
                }
                .foregroundStyle(theme.label)
                .labCard()
            }
            .padding(LabSpacing.md)
        }
        .background(theme.canvas.ignoresSafeArea())
    }

    private func swatchRow(_ name: String, _ swatch: Swatch, on background: Swatch) -> some View {
        let fg = swatch.resolve(dark: isDark, highContrast: isHigh)
        let bg = background.resolve(dark: isDark, highContrast: isHigh)
        return HStack {
            Circle().fill(Color(swatch: swatch)).frame(width: 24, height: 24)
            Text(verbatim: name).font(.body.weight(.medium)).foregroundStyle(Color(swatch: swatch))
            Spacer()
            ratio(fg.contrastRatio(with: bg), hex: fg.description)
        }
    }

    private func fillRow(_ name: String, _ fill: Swatch, text: Swatch) -> some View {
        let bg = fill.resolve(dark: isDark, highContrast: isHigh)
        let fg = text.resolve(dark: isDark, highContrast: isHigh)
        return HStack {
            Text(verbatim: name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(swatch: text))
                .padding(.horizontal, LabSpacing.sm)
                .frame(minHeight: 40)
                .background(Color(swatch: fill), in: RoundedRectangle(cornerRadius: LabRadius.sm, style: .continuous))
            Spacer()
            ratio(fg.contrastRatio(with: bg), hex: bg.description)
        }
    }

    private func ratio(_ value: Double, hex: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: String(format: "%.1f:1", value))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(value >= 4.5 ? theme.text(.positive) : theme.text(.negative))
            Text(verbatim: hex)
                .font(.caption.monospaced())
                .foregroundStyle(theme.secondaryLabel)
        }
    }
}
