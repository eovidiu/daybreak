import SwiftUI

// Warm Editorial design system — cream ink-on-paper, serif display, muted accents.
enum Theme {
    static let paper = Color(hex: 0xFDFBF7)
    static let paperDim = Color(hex: 0xF6F2EA)
    static let card = Color.white
    static let ink = Color(hex: 0x333333)
    static let inkSoft = Color(hex: 0x5C574F)
    static let muted = Color(hex: 0x928B7D)
    static let hairline = Color(hex: 0x333333).opacity(0.10)

    static let urgent = Color(hex: 0xC36A52)
    static let progress = Color(hex: 0x7D8C7F)
    static let extra = Color(hex: 0x7A8C99)

    static func accent(_ bucket: Bucket) -> Color {
        switch bucket {
        case .urgent: urgent
        case .progress: progress
        case .extra: extra
        }
    }

    // Tinted timeline block colors: soft fill + a darker ink for the label.
    static func slotFill(_ bucket: Bucket) -> Color { accent(bucket).opacity(0.14) }
    static func slotInk(_ bucket: Bucket) -> Color {
        switch bucket {
        case .urgent: Color(hex: 0x8F3F2B)
        case .progress: Color(hex: 0x47543F)
        case .extra: Color(hex: 0x43596B)
        }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    // Apple's New York — a premium system serif; no bundled font needed.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
