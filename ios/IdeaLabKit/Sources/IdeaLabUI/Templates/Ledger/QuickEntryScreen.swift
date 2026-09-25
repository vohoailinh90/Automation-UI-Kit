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
public struct QuickEntryScreen: View {
    private enum AmountSource {
        case keypad
        case text
    }

    @State private var kind: LedgerEntry.Kind
    @State private var input = AmountInput()
    @State private var text = ""
    @State private var date: Date
    @State private var reading: ParsedAmount?
    @State private var amountSource = AmountSource.keypad
    @State private var saves = 0
    @FocusState private var noteFocused: Bool

    private let latestDate: Date
    private let suggestions: (LedgerEntry.Kind) -> [String]
    private let onSave: (LedgerEntry) -> Void
    private let onCancel: () -> Void
    @Environment(\.labTheme) private var theme

    /// - Parameters:
    ///   - kind: which button opened the sheet.
    ///   - date: when the entry happened; defaults to now and can be moved back ("hôm qua quên ghi").
    ///   - suggestions: one-tap notes for each kind.
    public init(
        kind: LedgerEntry.Kind,
        date: Date = .now,
        suggestions: @escaping (LedgerEntry.Kind) -> [String] = QuickEntryScreen.defaultSuggestions,
        onSave: @escaping (LedgerEntry) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _kind = State(initialValue: kind)
        _date = State(initialValue: date)
        latestDate = date
        self.suggestions = suggestions
        self.onSave = onSave
        self.onCancel = onCancel
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
                .disabled(input.isEmpty)
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
            AmountDisplay(input.value, kind: kind)
                .padding(.top, LabSpacing.xs)
            if let reading, amountSource == .text {
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
                            // Keep an amount read from the old text: the chip
                            // replaces the words, not the money.
                            amountSource = .keypad
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
            .frame(minHeight: 44)
        }
    }

    /// The keypad writes through this, so typing digits takes over from an
    /// amount that was read out of the note.
    private var keypadBinding: Binding<AmountInput> {
        Binding(
            get: { input },
            set: { newValue in
                input = newValue
                amountSource = .keypad
            }
        )
    }

    private func read(_ newText: String) {
        if let parsed = AmountParser.parse(newText), input.set(parsed.amount) {
            reading = parsed
            amountSource = .text
        } else if amountSource == .text {
            // The sentence no longer holds an amount: drop the one it gave.
            input.clear()
            reading = nil
            amountSource = .keypad
        } else {
            reading = nil
        }
    }

    private func save() {
        guard !input.isEmpty else { return }
        // While the text still holds an amount phrase, save the words around
        // it — even if the keypad has since changed the amount.
        let note = reading?.note ?? text
        saves += 1
        onSave(LedgerEntry(
            kind: kind,
            amount: input.value,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date
        ))
    }
}
#endif
