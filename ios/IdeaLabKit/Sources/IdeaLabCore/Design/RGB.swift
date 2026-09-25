import Foundation

/// An opaque sRGB colour written as `0xRRGGBB`, plus the WCAG 2.x maths the
/// palette is checked against. Kept free of SwiftUI so the contrast tests run
/// on Linux too.
public struct RGB: Hashable, Sendable, CustomStringConvertible {
    public let hex: UInt32

    public init(_ hex: UInt32) {
        precondition(hex <= 0xFFFFFF, "RGB takes 0xRRGGBB; got \(String(hex, radix: 16))")
        self.hex = hex
    }

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    public var description: String {
        let digits = String(hex, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1...21. Symmetric: the order of the two colours does not matter.
    public func contrastRatio(with other: RGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This colour painted at `opacity` over `background`, the way a tinted
    /// fill (`accent.opacity(0.14)`) actually reaches the eye. Contrast has to
    /// be measured against this result, not against the tint itself.
    public func composited(over background: RGB, opacity: Double) -> RGB {
        let alpha = min(max(opacity, 0), 1)
        func mix(_ top: UInt32, _ bottom: UInt32) -> UInt32 {
            UInt32((Double(top) * alpha + Double(bottom) * (1 - alpha)).rounded())
        }
        let r = mix((hex >> 16) & 0xFF, (background.hex >> 16) & 0xFF)
        let g = mix((hex >> 8) & 0xFF, (background.hex >> 8) & 0xFF)
        let b = mix(hex & 0xFF, background.hex & 0xFF)
        return RGB(r << 16 | g << 8 | b)
    }
}
