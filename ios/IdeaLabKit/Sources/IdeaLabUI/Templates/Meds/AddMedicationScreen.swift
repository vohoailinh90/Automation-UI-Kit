#if os(iOS)
import IdeaLabCore
import SwiftUI

/// "Thêm thuốc": what the medicine is called, how much and how to take it,
/// what the pill looks like, when, and for how long — one scrolling page in
/// the senior density, with the pill drawn live at the top, so whoever sets
/// it up sees what the parent will see on "ĐÃ UỐNG".
///
/// Template: present it in a `.sheet`; it brings its own `NavigationStack`.
/// The rules (trimmed names, times kept sorted and unique, a course that ends
/// on a whole day of the parent's calendar) are `MedicationDraft`'s, in the
/// core, with tests.
///
/// The medicine starts when it is saved — `now()` at that moment — so this
/// morning's earlier doses are not shown as missed. Saving happens once:
/// after the first tap the button stays disabled. Dismiss the sheet from
/// `onSave`.
public struct AddMedicationScreen: View {
    @State private var draft: MedicationDraft
    @State private var isSaved = false
    /// The length a course of days goes back to when "Số ngày" is picked again.
    @State private var courseDays = 7
    /// A time moved onto one already in the list: said, not silently undone.
    @State private var clash: TimeOfDay?

    private let now: () -> Date
    private let calendar: Calendar
    private let onSave: (Medication) -> Void
    private let onCancel: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale

    /// - Parameters:
    ///   - draft: what the form starts with.
    ///   - now: the current time, read when the medicine is saved.
    ///   - calendar: the parent's, as for the other meds screens: the course's
    ///     last day is a day of theirs.
    public init(
        draft: MedicationDraft = MedicationDraft(),
        now: @escaping () -> Date = { .now },
        calendar: Calendar,
        onSave: @escaping (Medication) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        if case let .days(count) = draft.course {
            _courseDays = State(initialValue: count)
        }
        self.now = now
        self.calendar = calendar
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LabSpacing.md) {
                    preview
                    nameCard
                    doseCard
                    lookCard
                    timesCard
                    courseCard
                }
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBar
                    .labBottomBar()
            }
            .navigationTitle("Thêm thuốc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", action: onCancel)
                }
            }
            .sensoryFeedback(.success, trigger: isSaved)
        }
    }

    // MARK: - Preview

    private var hasName: Bool { !trimmed(draft.name).isEmpty }

    private var previewName: String {
        hasName ? trimmed(draft.name) : "Tên thuốc"
    }

    /// "1 viên · Sau ăn · 07:00, 21:00".
    private var previewDetails: String {
        [trimmed(draft.dose), trimmed(draft.instructions), draft.times.map(\.description).joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The pill as the parent will see it, with what the form says so far.
    private var preview: some View {
        VStack(spacing: LabSpacing.xs) {
            PillView(draft.style, size: 88)
                .padding(.vertical, LabSpacing.xs)
            Text(verbatim: previewName)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(hasName ? theme.label : theme.secondaryLabel)
                .multilineTextAlignment(.center)
            if !previewDetails.isEmpty {
                Text(verbatim: previewDetails)
                    .font(.title3)
                    .foregroundStyle(theme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .labCard(padding: LabSpacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Xem trước: \(previewName), \(draft.style.accessibilityDescription). \(previewDetails)"))
    }

    // MARK: - Name, dose, instructions

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.xs) {
            LabSectionHeader("Tên thuốc")
            field("Tên thuốc", prompt: "Ví dụ: Thuốc huyết áp", text: $draft.name)
            Text(verbatim: "Tên cả nhà vẫn gọi, để cha mẹ nhận ra ngay, không cần tên hoá chất trên hộp.")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labCard()
    }

    private var doseCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("Mỗi lần uống")
            field("Liều mỗi lần", prompt: "Ví dụ: 1 viên", text: $draft.dose)
            chips(MedicationDraft.doseSuggestions, selected: trimmed(draft.dose)) { draft.dose = $0 }
            LabSectionHeader("Cách uống")
            field("Cách uống", prompt: "Ví dụ: Sau ăn sáng", text: $draft.instructions)
            chips(MedicationDraft.instructionSuggestions, selected: trimmed(draft.instructions)) { choice in
                // The chosen one again clears it: how to take it is optional.
                draft.instructions = trimmed(draft.instructions) == choice ? "" : choice
            }
        }
        .labCard()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func field(_ label: String, prompt: String, text: Binding<String>) -> some View {
        TextField(text: text, prompt: Text(verbatim: prompt)) {
            Text(verbatim: label)
        }
        .font(.title3)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.done)
        .padding(.horizontal, LabSpacing.sm)
        .frame(minHeight: theme.density.controlHeight)
        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous))
    }

    /// One-tap choices under a field; the chosen one is filled in.
    private func chips(_ options: [String], selected: String, choose: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LabSpacing.xs) {
                ForEach(options, id: \.self) { option in
                    chip(option, isSelected: option == selected) { choose(option) }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LabSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
            }
            .font(.headline)
            .foregroundStyle(isSelected ? theme.onFill : theme.accentText)
            .padding(.horizontal, LabSpacing.md)
            .frame(minHeight: 48)
            .background(isSelected ? theme.fill(.accent) : theme.tonalFill(.accent), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Look

    private var lookCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("Hình viên thuốc")
            HStack(spacing: LabSpacing.xs) {
                ForEach(PillStyle.Shape.allCases, id: \.self) { shape in
                    shapeButton(shape)
                }
            }
            if draft.style.shape == .capsule {
                LabSectionHeader("Màu nửa thứ nhất")
                colorGrid(selected: draft.style.color) { draft.style.color = $0 }
                LabSectionHeader("Màu nửa thứ hai")
                colorGrid(selected: draft.style.secondColor ?? draft.style.color) { draft.style.secondColor = $0 }
            } else {
                LabSectionHeader("Màu")
                colorGrid(selected: draft.style.color) { draft.style.color = $0 }
            }
        }
        .labCard()
    }

    private func shapeButton(_ shape: PillStyle.Shape) -> some View {
        let isSelected = draft.style.shape == shape
        let sample = PillStyle(shape: shape, color: draft.style.color, secondColor: draft.style.secondColor)
        return Button {
            draft.style.shape = shape
        } label: {
            PillView(sample, size: 40)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    isSelected ? theme.tonalFill(.accent) : theme.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous)
                        .strokeBorder(isSelected ? theme.fill(.accent) : Color.clear, lineWidth: 3)
                }
                .contentShape(RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: shape.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorGrid(selected: PillStyle.Color, choose: @escaping (PillStyle.Color) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: LabSpacing.xs)], spacing: LabSpacing.xs) {
            ForEach(PillStyle.Color.allCases, id: \.self) { color in
                swatch(color, isSelected: color == selected) { choose(color) }
            }
        }
    }

    private func swatch(_ color: PillStyle.Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .overlay { Circle().strokeBorder(theme.separator, lineWidth: 1) }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            // Dark on the light colours, white on the dark ones.
                            .foregroundStyle(color.rgb.relativeLuminance > 0.4 ? Color.black.opacity(0.75) : Color.white)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 44, height: 44)
                .padding(4)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(theme.fill(.accent), lineWidth: 3)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: color.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Times

    private var timesCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("Giờ uống")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LabSpacing.xs) {
                    // The usual times, on and off with one tap each.
                    ForEach(MedicationDraft.timeSuggestions.indices, id: \.self) { index in
                        let suggestion = MedicationDraft.timeSuggestions[index]
                        let isOn = draft.times.contains(suggestion.time)
                        chip("\(suggestion.label) \(suggestion.time)", systemImage: isOn ? "checkmark" : "plus", isSelected: isOn) {
                            if isOn { draft.remove(suggestion.time) } else { draft.add(suggestion.time) }
                            clash = nil
                        }
                    }
                }
            }
            .scrollClipDisabled()
            ForEach(draft.times, id: \.self) { time in
                timeRow(time, number: (draft.times.firstIndex(of: time) ?? 0) + 1)
            }
            if let clash {
                Text(verbatim: "\(clash) đã có trong danh sách giờ uống.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text(.negative))
            }
            Button {
                if let time = draft.suggestedNewTime {
                    draft.add(time)
                    clash = nil
                }
            } label: {
                Label("Thêm giờ khác", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(draft.suggestedNewTime == nil)
        }
        .labCard()
    }

    private func timeRow(_ time: TimeOfDay, number: Int) -> some View {
        HStack(spacing: LabSpacing.sm) {
            DatePicker(selection: binding(for: time), displayedComponents: .hourAndMinute) {
                Text(verbatim: "Lần \(number)")
                    .font(.headline)
                    .foregroundStyle(theme.label)
            }
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            Button {
                draft.remove(time)
                clash = nil
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(theme.text(.negative))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Bỏ giờ \(time)"))
        }
        .frame(minHeight: theme.density.controlHeight)
    }

    /// A row's time as the picker's date, on a fixed day without a clock
    /// change, so no time of day is skipped.
    private func binding(for time: TimeOfDay) -> Binding<Date> {
        Binding(
            get: {
                calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)) ?? .now
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                guard let hour = parts.hour, let minute = parts.minute else { return }
                let new = TimeOfDay(hour: hour, minute: minute)
                clash = draft.change(time, to: new) ? nil : new
            }
        )
    }

    // MARK: - Course

    private var courseCard: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            LabSectionHeader("Uống trong bao lâu")
            Picker(selection: isCourse) {
                Text(verbatim: "Lâu dài").tag(false)
                Text(verbatim: "Số ngày").tag(true)
            } label: {
                Text(verbatim: "Uống trong bao lâu")
            }
            .pickerStyle(.segmented)
            if case let .days(count) = draft.course {
                Stepper(value: days, in: 1...MedicationDraft.longestCourse) {
                    Text(verbatim: "\(count) ngày")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.label)
                }
                .frame(minHeight: theme.density.controlHeight)
                if let end = MedicationDraft.courseEnd(days: count, startingAt: now(), calendar: calendar) {
                    Text(verbatim: "Uống đến hết \(end.formatted(calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits))), tính cả hôm nay.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(verbatim: "Uống mỗi ngày, không có ngày kết thúc.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
        .labCard()
    }

    private var isCourse: Binding<Bool> {
        Binding(
            get: { if case .days = draft.course { true } else { false } },
            set: { draft.course = $0 ? .days(courseDays) : .ongoing }
        )
    }

    private var days: Binding<Int> {
        Binding(
            get: { if case let .days(count) = draft.course { count } else { courseDays } },
            set: {
                courseDays = $0
                draft.course = .days($0)
            }
        )
    }

    // MARK: - Save

    private var saveBar: some View {
        let problem = draft.problems.first
        return VStack(spacing: LabSpacing.xs) {
            // A disabled button is never a riddle: what is missing is said.
            if let problem {
                Text(verbatim: problem.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondaryLabel)
            }
            Button {
                save()
            } label: {
                Label("Lưu thuốc", systemImage: "checkmark")
            }
            .buttonStyle(.labFilled)
            .disabled(problem != nil || isSaved)
        }
        .padding(.horizontal, LabSpacing.md)
        .padding(.vertical, LabSpacing.xs)
        .background(theme.canvas)
    }

    private func save() {
        guard !isSaved, let medication = draft.medication(startingAt: now(), calendar: calendar) else { return }
        isSaved = true
        onSave(medication)
    }
}
#endif
