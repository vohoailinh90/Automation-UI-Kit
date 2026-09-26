/// Counts written the Vietnamese way whatever the phone's region is set to:
/// "1.284 ảnh", not "1,284 ảnh".
public enum VietnameseNumber {
    public static func grouped(_ value: Int) -> String {
        (value < 0 ? VND.minus : "") + VND.grouped(UInt64(value.magnitude))
    }
}
