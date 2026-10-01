import Foundation

/// A video's length, as Photos writes it on a thumbnail, and in words for
/// VoiceOver. Whole seconds, rounded to the nearest; a length that is not a
/// finite number, or below zero, is said as zero.
public enum VideoDuration {
    /// "0:07", "1:05", "12:34", "1:02:03": minutes and seconds, with the
    /// hours in front from one hour on.
    public static func string(_ seconds: TimeInterval) -> String {
        let (hours, minutes, rest) = parts(seconds)
        let twoDigits = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(twoDigits(minutes)):\(twoDigits(rest))" : "\(minutes):\(twoDigits(rest))"
    }

    /// "7 giây", "1 phút 5 giây", "12 phút", "1 giờ 2 phút 3 giây": each part
    /// that is not zero, "0 giây" for nothing at all.
    public static func spoken(_ seconds: TimeInterval) -> String {
        let (hours, minutes, rest) = parts(seconds)
        let words = [(hours, "giờ"), (minutes, "phút"), (rest, "giây")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return words.isEmpty ? "0 giây" : words.joined(separator: " ")
    }

    /// Hours, minutes and seconds of `seconds`, rounded to a whole second.
    private static func parts(_ seconds: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int) {
        // Past a hundred years, a length is no more a video's than NaN is:
        // capped, so the rounding below cannot overflow `Int`.
        let whole = seconds.isFinite ? Int(min(max(seconds, 0), 3_155_760_000).rounded()) : 0
        return (whole / 3_600, whole / 60 % 60, whole % 60)
    }
}
