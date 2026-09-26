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
    /// The time the wheel sheet is open for.
    @State private var timeEdit: TimeEdit?

    private let now: () -> Date
    private let calendar: Calendar
    private let onSave: (Medication) -> Void
    private let onCancel: () -> Void
    @Environment(\.labTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - draft: what the form starts with.
    ///   - now: the current time, read when the medicine is saved, and every
    ///     minute for the course's last day.
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
            .sheet(item: $timeEdit) { edit in
                TimeWheelSheet(
                    edit: edit,
                    taken: Set(draft.times.filter { $0 != edit.original }),
                    calendar: calendar
                ) { picked in
                    setTime(picked, for: edit)
                }
                .labTheme(theme)
            }
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
        chipRow {
            ForEach(options, id: \.self) { option in
                chip(option, isSelected: option == selected) { choose(option) }
            }
        }
    }

    /// A row of chips that scrolls sideways inside its card. The row runs to
    /// the card's edges, so a chip that does not fit is cut off there, which
    /// shows the row scrolls, and is never drawn over the page around the
    /// card. At rest the first chip lines up with the card's text. The row
    /// is for a card with `labCard()`'s default padding, `LabSpacing.md`.
    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LabSpacing.xs) {
                content()
            }
        }
        .contentMargins(.horizontal, LabSpacing.md, for: .scrollContent)
        .padding(.horizontal, -LabSpacing.md)
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
            chipRow {
                // The usual times, on and off with one tap each.
                ForEach(MedicationDraft.timeSuggestions.indices, id: \.self) { index in
                    let suggestion = MedicationDraft.timeSuggestions[index]
                    let isOn = draft.times.contains(suggestion.time)
                    chip("\(suggestion.label) \(suggestion.time)", systemImage: isOn ? "checkmark" : "plus", isSelected: isOn) {
                        if isOn { draft.remove(suggestion.time) } else { draft.add(suggestion.time) }
                    }
                }
            }
            ForEach(Array(draft.times.enumerated()), id: \.element) { index, time in
                timeRow(time, number: index + 1)
            }
            Button {
                if let time = draft.suggestedNewTime {
                    timeEdit = TimeEdit(original: nil, start: time)
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

    /// "Lần 1 … 07:00": a tap opens the wheel. The list changes only once the
    /// new time is confirmed, so it never re-sorts under the finger. At
    /// accessibility sizes the time goes under "Lần 1", as in `DoseRow`: side
    /// by side, with the remove button, they would not fit an iPhone's width.
    private func timeRow(_ time: TimeOfDay, number: Int) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LabSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LabSpacing.xs))
        return HStack(spacing: LabSpacing.sm) {
            Button {
                timeEdit = TimeEdit(original: time, start: time)
            } label: {
                layout {
                    Text(verbatim: "Lần \(number)")
                        .font(.headline)
                        .foregroundStyle(theme.label)
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: LabSpacing.xs)
                    }
                    Text(verbatim: time.description)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.accentText)
                        .padding(.horizontal, LabSpacing.sm)
                        .frame(minHeight: 44)
                        .background(theme.tonalFill(.accent), in: RoundedRectangle(cornerRadius: LabRadius.sm, style: .continuous))
                }
                .padding(.vertical, typeSize.isAccessibilitySize ? LabSpacing.xs : 0)
                .frame(maxWidth: .infinity, minHeight: theme.density.controlHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Lần \(number), \(time)"))
            .accessibilityHint(Text(verbatim: "Đổi giờ uống"))
            Button {
                draft.remove(time)
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
    }

    /// The time confirmed on the wheel: a new one, or a row's new time.
    private func setTime(_ picked: TimeOfDay, for edit: TimeEdit) {
        guard let original = edit.original else {
            draft.add(picked)
            return
        }
        draft.change(original, to: picked)
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
                // Read again every minute: left open past midnight, "hôm nay"
                // moves on, and so does the last day, as it will on saving.
                TimelineView(.everyMinute) { _ in
                    if let end = MedicationDraft.courseEnd(days: count, startingAt: now(), calendar: calendar) {
                        Text(verbatim: "Uống đến hết \(end.formatted(calendar.dateFormat(locale: locale).weekday(.wide).day().month(.defaultDigits))), tính cả hôm nay.")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
            // Reached straight from the button, VoiceOver says why it is dimmed.
            .accessibilityHint(Text(verbatim: problem?.message ?? ""))
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

/// What the wheel sheet is open for: a time in the list, or a new one.
private struct TimeEdit: Identifiable {
    /// The time being changed; `nil` for "Thêm giờ khác".
    let original: TimeOfDay?
    /// Where the wheel starts.
    let start: TimeOfDay

    var id: String { original.map { "change \($0)" } ?? "add" }
}

/// A time on a wheel, as the Clock app sets an alarm: the list behind it
/// changes once, on "Xong", not while the wheel turns. A time already in the
/// list can't be confirmed, and the sheet says so.
private struct TimeWheelSheet: View {
    let edit: TimeEdit
    /// The list's other times.
    let taken: Set<TimeOfDay>
    let calendar: Calendar
    let onDone: (TimeOfDay) -> Void
    @State private var date: Date
    @Environment(\.labTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(edit: TimeEdit, taken: Set<TimeOfDay>, calendar: Calendar, onDone: @escaping (TimeOfDay) -> Void) {
        self.edit = edit
        self.taken = taken
        self.calendar = calendar
        self.onDone = onDone
        // On a fixed day without a clock change, so no time of day is skipped.
        let start = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: edit.start.hour, minute: edit.start.minute))
        _date = State(initialValue: start ?? .now)
    }

    private var picked: TimeOfDay? {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }

    private static func takenMessage(_ time: TimeOfDay) -> String {
        "\(time) đã có trong danh sách giờ uống."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: LabSpacing.md) {
                DatePicker(selection: $date, displayedComponents: .hourAndMinute) {
                    Text(verbatim: "Giờ uống")
                }
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                if let picked, taken.contains(picked) {
                    Text(verbatim: Self.takenMessage(picked))
                        .font(.headline)
                        .foregroundStyle(theme.text(.negative))
                        .multilineTextAlignment(.center)
                }
            }
            .onChange(of: picked) { _, picked in
                // VoiceOver stays on the wheel, not on the message under it:
                // say it, or the greyed-out "Xong" is a riddle.
                if let picked, taken.contains(picked) {
                    AccessibilityNotification.Announcement(Self.takenMessage(picked)).post()
                }
            }
            .padding(LabSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle(edit.original == nil ? "Thêm giờ uống" : "Đổi giờ uống")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(edit.original == nil ? "Thêm" : "Xong") {
                        guard let picked, !taken.contains(picked) else { return }
                        onDone(picked)
                        dismiss()
                    }
                    .disabled(picked.map { taken.contains($0) } ?? true)
                }
            }
        }
        // Half a screen holds the wheel, but not the wheel and the message
        // under it at accessibility sizes.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}
#endif
