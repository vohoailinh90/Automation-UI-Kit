#if os(iOS)
import IdeaLabCore
import SwiftUI

public extension PillStyle.Shape {
    /// "viên tròn", for VoiceOver and labels.
    var name: String {
        switch self {
        case .round: "viên tròn"
        case .oval: "viên bầu dục"
        case .oblong: "viên dài"
        case .capsule: "viên nang"
        }
    }
}

public extension PillStyle.Color {
    var name: String {
        switch self {
        case .white: "trắng"
        case .cream: "kem"
        case .yellow: "vàng"
        case .orange: "cam"
        case .pink: "hồng"
        case .red: "đỏ"
        case .lightBlue: "xanh nhạt"
        case .blue: "xanh dương"
        case .green: "xanh lá"
        case .brown: "nâu"
        }
    }

    // Spelled out: inside this extension, `Color` is `PillStyle.Color`.
    var swiftUIColor: SwiftUI.Color {
        SwiftUI.Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

public extension PillStyle {
    /// "viên nang cam và kem".
    var accessibilityDescription: String {
        if shape == .capsule, let secondColor, secondColor != color {
            return "\(shape.name) \(color.name) và \(secondColor.name)"
        }
        return "\(shape.name) \(color.name)"
    }
}

/// A drawn pill in its real shape and colour: the parent recognises the
/// tablet on screen as the one in their hand. Outlined, so a white pill
/// still shows on a white card.
public struct PillView: View {
    private let style: PillStyle
    private let size: CGFloat
    @Environment(\.labTheme) private var theme

    public init(_ style: PillStyle, size: CGFloat = 44) {
        self.style = style
        self.size = size
    }

    public var body: some View {
        Group {
            switch style.shape {
            case .round:
                pill(Circle(), width: size, height: size)
                    .overlay {
                        // The score line of a scored tablet.
                        Capsule()
                            .fill(.black.opacity(0.12))
                            .frame(width: size * 0.62, height: max(1.5, size * 0.04))
                    }
            case .oval:
                pill(Ellipse(), width: size, height: size * 0.7)
            case .oblong:
                pill(Capsule(), width: size, height: size * 0.46)
            case .capsule:
                capsule
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: style.accessibilityDescription))
    }

    private func pill<S: Shape>(_ shape: S, width: CGFloat, height: CGFloat) -> some View {
        shape
            .fill(style.color.swiftUIColor)
            .overlay { shape.fill(highlight) }
            .overlay { shape.stroke(theme.separator, lineWidth: 1) }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.12), radius: size * 0.06, x: 0, y: size * 0.04)
    }

    private var capsule: some View {
        let width = size * 0.98
        let height = size * 0.42
        let second = (style.secondColor ?? style.color).swiftUIColor
        return HStack(spacing: 0) {
            Rectangle().fill(style.color.swiftUIColor)
            Rectangle().fill(second)
        }
        .frame(width: width, height: height)
        .overlay { Capsule().fill(highlight) }
        .clipShape(Capsule())
        .overlay { Capsule().stroke(theme.separator, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: size * 0.06, x: 0, y: size * 0.04)
        .rotationEffect(.degrees(-35))
    }

    /// Soft top-left sheen that makes a flat fill read as a physical tablet.
    private var highlight: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.45), .white.opacity(0)],
            startPoint: .topLeading,
            endPoint: .center
        )
    }
}

/// A dose's state in words, colour and icon: "Đã uống 07:12", "Đến giờ uống",
/// "Trễ 2 giờ 41 phút", "Không xác nhận", "12:00". Late is an amber fill
/// with dark text — amber never reaches 4.5:1 as text. `calendar` is the
/// parent's, as on the screens.
public struct DoseStatusBadge: View {
    private let status: DoseStatus
    private let time: Date
    private let calendar: Calendar
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale

    public init(_ status: DoseStatus, scheduledAt time: Date, calendar: Calendar) {
        self.status = status
        self.time = time
        self.calendar = calendar
    }

    public var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: symbol)
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, LabSpacing.sm)
        .padding(.vertical, LabSpacing.xxs)
        .background(background, in: Capsule())
    }

    private func clock(_ date: Date) -> String {
        date.formatted(calendar.dateFormat(locale: locale).hour().minute())
    }

    private var text: String {
        switch status {
        case .upcoming: clock(time)
        case .due: "Đến giờ uống"
        case .late(let by): "Trễ \(VietnameseDuration.string(by))"
        case .missed: "Không xác nhận"
        case .taken(let at): "Đã uống \(clock(at))"
        case .skipped: "Bỏ qua"
        }
    }

    private var symbol: String {
        switch status {
        case .upcoming: "clock"
        case .due: "bell.fill"
        case .late: "exclamationmark.triangle.fill"
        case .missed: "questionmark.circle"
        case .taken: "checkmark.circle.fill"
        case .skipped: "xmark.circle"
        }
    }

    private var foreground: Color {
        switch status {
        case .upcoming, .skipped, .missed: theme.secondaryLabel
        case .due: theme.accentText
        case .late: theme.onWarningFill
        case .taken: theme.text(.positive)
        }
    }

    private var background: Color {
        switch status {
        case .upcoming, .skipped, .missed: theme.surfaceSecondary
        case .due: theme.tonalFill(.accent)
        case .late: theme.warningFill
        case .taken: theme.tonalFill(.positive)
        }
    }
}

/// One dose in a list: the pill, the name and instructions, the time and
/// its status. Stacks at accessibility text sizes.
public struct DoseRow: View {
    private let dose: ScheduledDose
    private let status: DoseStatus
    private let calendar: Calendar
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ dose: ScheduledDose, status: DoseStatus, calendar: Calendar) {
        self.dose = dose
        self.status = status
        self.calendar = calendar
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LabSpacing.sm))
        layout {
            PillView(dose.medication.style, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: dose.medication.name)
                    .font(.headline)
                    .foregroundStyle(theme.label)
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: LabSpacing.xs)
            }
            DoseStatusBadge(status, scheduledAt: dose.time, calendar: calendar)
        }
        .padding(.vertical, LabSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// "07:00 · 1 viên · Sau ăn sáng" — the time always leads, since the
    /// badge replaces it once the dose is due or answered.
    private var detail: String {
        let time = dose.time.formatted(calendar.dateFormat(locale: locale).hour().minute())
        return [time, dose.medication.dose, dose.medication.instructions]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// A dose alert drawn as a phone shows one: the app's icon, the title in
/// bold, the body under it. It is the example on a permission primer —
/// people allow alerts they can picture — and shows the planner's own words
/// (`DoseAlerts`). It stands in for nothing: real alerts are notifications.
public struct DoseAlertBanner: View {
    private let alert: DoseAlert
    private let when: String
    @Environment(\.labTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameter when: the time in the corner, as the Lock Screen writes
    ///   it: "bây giờ", "07:30".
    public init(_ alert: DoseAlert, when: String = "bây giờ") {
        self.alert = alert
        self.when = when
    }

    public var body: some View {
        // At accessibility sizes the time goes under the title, not beside it.
        let heading = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LabSpacing.xs))
        HStack(alignment: .top, spacing: LabSpacing.sm) {
            Image(systemName: "pills.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.onFill)
                .frame(width: 40, height: 40)
                .background(theme.fill(.accent), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                heading {
                    Text(verbatim: alert.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: when)
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryLabel)
                }
                Text(verbatim: alert.body)
                    .font(.subheadline)
                    .foregroundStyle(theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .labCard(padding: LabSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Thông báo mẫu: \(alert.title). \(alert.body)"))
    }
}
#endif
