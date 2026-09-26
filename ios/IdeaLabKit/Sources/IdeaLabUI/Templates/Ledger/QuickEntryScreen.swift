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
/// Where the amount comes from: the note can fill it ("bán 3 thùng nước
/// 450k"), but once the keypad is touched the keypad owns it. Editing the
/// note never silently changes a keyed amount; if the note then holds a
/// different amount, the screen offers it as a one-tap "Dùng … trong ghi chú".
/// A bare trailing number ("bán 3", on its way to "bán 3 thùng") is only read
/// while nothing was keyed.
///
/// Saving happens once: after the first tap the button stays disabled, so a
/// double tap, or a tap while the sheet is closing, cannot add the entry twice.
/// Dismiss the sheet from `onSave`.
public struct QuickEntryScreen: View {
    @State private var kind: LedgerEntry.Kind
    /// What the keypad holds; only meaningful once `keypadOwnsAmount`.
    @State private var keypad = AmountInput()
    /// Set by the first keypad press, cleared only by choosing the note's amount.
    @State private var keypadOwnsAmount = false
    @State private var text = ""
    @State private var date: Date
    /// The note's amount phrase as last read, before deciding whether it counts.
    @State private var parsed: ParsedAmount?
    /// Set by the first save; the screen is done after it.
    @State private var isSaved = false
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

    /// The note's amount phrase, if it counts. Next to a keyed amount, a bare
    /// trailing number is a note still being typed ("bán 3" on its way to
    /// "bán 3 thùng"), not an amount — and it stays in the note when saved.
    /// Worked out from the current state, since the keypad can take over
    /// without the note changing.
    private var reading: ParsedAmount? {
        guard let parsed else { return nil }
        return parsed.isExplicit || !keypadOwnsAmount ? parsed : nil
    }

    /// The amount that will be saved.
    private var amount: Int64 {
        keypadOwnsAmount ? keypad.value : (reading?.amount ?? 0)
    }

    /// A different, explicit amount in the note while the keypad owns the
    /// amount: offered, never applied on its own.
    private var noteAmountOffer: ParsedAmount? {
        guard keypadOwnsAmount, let reading, reading.isExplicit, reading.amount != keypad.value else { return nil }
        return reading
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
                .disabled(amount == 0 || isSaved)
                .padding(.horizontal, LabSpacing.md)
                .padding(.vertical, LabSpacing.xs)
                .background(theme.surface)
                .labBottomBar()
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
            .sensoryFeedback(.success, trigger: isSaved)
        }
    }

    private var amountSection: some View {
        VStack(spacing: LabSpacing.xs) {
            AmountDisplay(amount, kind: kind)
                .padding(.top, LabSpacing.xs)
            if let offer = noteAmountOffer {
                Button {
                    keypadOwnsAmount = false
                } label: {
                    Label {
                        Text(verbatim: "Dùng \(VND.string(offer.amount)) trong ghi chú")
                    } icon: {
                        Image(systemName: "arrow.up.doc")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.accentText)
                    .padding(.horizontal, LabSpacing.sm)
                    .frame(minHeight: 44)
                    .background(theme.tonalFill(.accent), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if let reading, !keypadOwnsAmount {
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
                            if !keypadOwnsAmount, amount > 0 {
                                keypad = AmountInput(value: amount)
                                keypadOwnsAmount = true
                            }
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
    /// note — and from its first press on, it owns the amount.
    private var keypadBinding: Binding<AmountInput> {
        Binding(
            get: { keypadOwnsAmount ? keypad : AmountInput(value: amount) },
            set: { newValue in
                keypad = newValue
                keypadOwnsAmount = true
            }
        )
    }

    private func read(_ newText: String) {
        parsed = AmountParser.parse(newText)
    }

    private func save() {
        guard amount > 0, !isSaved else { return }
        isSaved = true
        // While the note holds an amount phrase, save the words around it —
        // even if the keypad has since changed the amount.
        let note = reading?.note ?? text
        onSave(LedgerEntry(
            kind: kind,
            amount: amount,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date
        ))
    }
}
#endif
