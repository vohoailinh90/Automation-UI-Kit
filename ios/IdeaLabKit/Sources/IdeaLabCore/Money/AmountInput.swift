/// The state behind an amount keypad: digits typed so far, as whole đồng.
///
/// Every mutation reports whether it was accepted, so the keypad can play an
/// error haptic instead of silently ignoring a press (a 13th digit, "000" on
/// an empty amount).
public struct AmountInput: Hashable, Sendable {
    /// Largest amount the keypad accepts: 999.999.999.999 ₫, just under one
    /// nghìn tỷ. Far above any household-business entry, and far below where
    /// summing a year of entries could overflow `Int64`.
    public static let maximum: Int64 = 999_999_999_999

    public private(set) var value: Int64

    public init(value: Int64 = 0) {
        self.value = min(max(value, 0), Self.maximum)
    }

    public var isEmpty: Bool { value == 0 }

    /// Appends one digit (0–9). Leading zeros are rejected, not stored.
    @discardableResult
    public mutating func append(digit: Int) -> Bool {
        precondition((0...9).contains(digit), "append(digit:) takes 0–9, got \(digit)")
        if value == 0 && digit == 0 { return false }
        return replace(with: value.multipliedReportingOverflow(by: 10), adding: Int64(digit))
    }

    /// The "000" key: 450.000 is 4-5-0-000, four presses instead of six.
    @discardableResult
    public mutating func appendThousand() -> Bool {
        if value == 0 { return false }
        return replace(with: value.multipliedReportingOverflow(by: 1_000), adding: 0)
    }

    /// Deletes the last digit. Returns `false` when there was nothing to delete.
    @discardableResult
    public mutating func deleteLast() -> Bool {
        guard value > 0 else { return false }
        value /= 10
        return true
    }

    public mutating func clear() {
        value = 0
    }

    /// Replaces the whole amount, e.g. with one parsed from "bán 3 thùng 450k".
    /// Out-of-range values are rejected rather than clamped: clamping would
    /// save a different amount from the one the user said.
    @discardableResult
    public mutating func set(_ newValue: Int64) -> Bool {
        guard (0...Self.maximum).contains(newValue) else { return false }
        value = newValue
        return true
    }

    private mutating func replace(with shifted: (partialValue: Int64, overflow: Bool), adding digit: Int64) -> Bool {
        guard !shifted.overflow else { return false }
        let next = shifted.partialValue.addingReportingOverflow(digit)
        guard !next.overflow, next.partialValue <= Self.maximum else { return false }
        value = next.partialValue
        return true
    }
}
