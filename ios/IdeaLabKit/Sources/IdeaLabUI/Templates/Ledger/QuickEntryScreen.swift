#if os(iOS)
import IdeaLabCore
import SwiftUI

/// The ten-second entry sheet: pick Thu/Chi (already picked by the button
/// that opened it), type the amount on a big đồng keypad, tap Lưu.
///
/// Two faster paths for people who would rather talk or type a sentence:
/// the note field understands "bán 3 thùng nước 450k" and fills the amount
/// itself, and the keyboard's own microphone key dictates Vietnamese into it
/// — no speech permission, no extra code.
///
/// Template: present it in a `.sheet`; it brings its own `NavigationStack`.
///
/// Where the amount comes from: the keypad, or an amount *phrase* in the note
/// ("450k", "1 triệu 2", "450.000đ"). The latest of the two wins, and neither
/// ever erases the other: delete the phrase and the keypad's amount is back.
/// A bare trailing number ("bán 3", on its way to "bán 3 thùng") only fills
/// an empty amount — otherwise typing a note would overwrite what was keyed.
public struct QuickEntryScreen: View {
    @State private var kind: LedgerEntry.Kind
    /// What the keypad holds.
    @State private var keypad = AmountInput()
    @State private var text = ""
    @State private var date: Date
    /// The note's amount phrase, while the note has one worth using.
    @State private var reading: ParsedAmount?
    /// `true` while `reading` rather than `keypad` sets the amount.
    @State private var readingDrivesAmount = false
    @State private var saves = 0
    @FocusState private var noteFocused: Bool

    private let latestDate: Date
    private let calendar: Calendar
    private let suggestions: (LedgerEntry.Kind) -> [String]
    private let onSave: (LedgerEntry) -> Void
    private let onCancel: () -> Void
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - kind: which button opened the sheet.
    ///   - date: when the entry happened; defaults to now and can be moved back ("hôm qua quên ghi").
    ///   - calendar: the book's calendar; the date picker shows days in it.
    ///   - suggestions: one-tap notes for each kind.
    public init(
        kind: LedgerEntry.Kind,
        date: Date = .now,
        calendar: Calendar = .current,
        suggestions: @escaping (LedgerEntry.Kind) -> [String] = QuickEntryScreen.defaultSuggestions,
        onSave: @escaping (LedgerEntry) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _kind = State(initialValue: kind)
        _date = State(initialValue: date)
        latestDate = date
        self.calendar = calendar
        self.suggestions = suggestions
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// The amount that will be saved.
    private var amount: Int64 {
        if readingDrivesAmount, let reading { reading.amount } else { keypad.value }
    }

    nonisolated public static func defaultSuggestions(for kind: LedgerEntry.Kind) -> [String] {
        switch kind {
        case .income: ["Bán hàng", "Bán lẻ", "Khách trả nợ", "Tiền cọc"]
        case .expense: ["Nhập hàng", "Tiền điện", "Tiền nước", "Tiền ship", "Mặt bằng"]
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LabSpacing.md) {
                    KindPicker(kind: $kind)
                    amountSection
                    noteSection
                    if !noteFocused {
                        AmountKeypad(input: keypadBinding)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.sm)
                .animation(.snappy(duration: 0.25), value: noteFocused)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(theme.surface.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    save()
                } label: {
                    Label(kind == .income ? "Lưu khoản thu" : "Lưu khoản chi", systemImage: "checkmark")
                }
                .buttonStyle(.labFilled(LabTint(kind)))
                .disabled(amount == 0)
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.xs)
                .background(theme.surface)
            }
            .navigationTitle(kind == .income ? "Thêm khoản thu" : "Thêm khoản chi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", action: onCancel)
                }
            }
            .onChange(of: text) { _, newValue in
                read(newValue)
            }
            .sensoryFeedback(.success, trigger: saves)
        }
    }

    private var amountSection: some View {
        VStack(spacing: LabSpacing.xs) {
            AmountDisplay(amount, kind: kind)
                .padding(.top, LabSpacing.xs)
            if let reading, readingDrivesAmount {
                Label {
                    Text(verbatim: reading.assumedThousands
                        ? "Hiểu là \(VND.string(reading.amount)) — sửa nếu chưa đúng"
                        : "Đã lấy số tiền từ ghi chú")
                } icon: {
                    Image(systemName: reading.assumedThousands ? "questionmark.circle" : "sparkles")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(reading.assumedThousands ? theme.warning : theme.secondaryLabel)
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: LabSpacing.sm) {
            TextField(
                "Ghi chú",
                text: $text,
                prompt: Text("Ghi chú, hoặc gõ “bán 3 thùng nước 450k”"),
                axis: .vertical
            )
            .lineLimit(1...3)
            .focused($noteFocused)
            .submitLabel(.done)
            .onSubmit { noteFocused = false }
            .padding(LabSpacing.sm)
            .frame(minHeight: theme.density.controlHeight)
            .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: LabRadius.md, style: .continuous))
            .accessibilityHint(Text("Có thể gõ hoặc đọc cả câu có số tiền, ví dụ bán 3 thùng nước 450 nghìn"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LabSpacing.xs) {
                    ForEach(suggestions(kind), id: \.self) { suggestion in
                        Button {
                            // The chip replaces the words, not the money: an
                            // amount read from the old note moves to the keypad.
                            if readingDrivesAmount {
                                keypad = AmountInput(value: amount)
                            }
                            readingDrivesAmount = false
                            reading = nil
                            text = suggestion
                        } label: {
                            Text(verbatim: suggestion)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.text(LabTint(kind)))
                                .padding(.horizontal, LabSpacing.sm)
                                .frame(minHeight: 44)
                                .background(theme.tonalFill(LabTint(kind)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()

            DatePicker(selection: $date, in: ...latestDate, displayedComponents: .date) {
                Label("Ngày", systemImage: "calendar")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(theme.secondaryLabel)
            }
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .frame(minHeight: 44)
        }
    }

    /// The keypad edits the amount on screen — including one read from the
    /// note — and from then on the keypad is in charge.
    private var keypadBinding: Binding<AmountInput> {
        Binding(
            get: { readingDrivesAmount ? AmountInput(value: amount) : keypad },
            set: { newValue in
                keypad = newValue
                readingDrivesAmount = false
            }
        )
    }

    private func read(_ newText: String) {
        guard let parsed = AmountParser.parse(newText), parsed.isExplicit || keypad.isEmpty else {
            // No phrase (any more), or only a half-typed bare number next to a
            // keyed amount: the keypad's amount stands.
            reading = nil
            readingDrivesAmount = false
            return
        }
        reading = parsed
        readingDrivesAmount = true
    }

    private func save() {
        guard amount > 0 else { return }
        // While the note holds an amount phrase, save the words around it —
        // even if the keypad has since changed the amount.
        let note = reading?.note ?? text
        saves += 1
        onSave(LedgerEntry(
            kind: kind,
            amount: amount,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date
        ))
    }
}
#endif
