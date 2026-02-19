import SwiftUI

// MARK: - Goldfish Color System
// Auto-generated from ColorSystem.md — keep in sync.

extension Color {

    // MARK: Accent

    static let goldfishAccent = Color(light: 0x7C3AED, dark: 0x8B5CF6)
    static let goldfishAccentPressed = Color(light: 0x6D28D9, dark: 0x7C3AED)
    static let goldfishAccentSurface = Color(light: 0xF5F0FF, dark: 0x1E1033)

    // MARK: Backgrounds

    static let goldfishBgPrimary = Color(light: 0xFFFFFF, dark: 0x000000)
    static let goldfishBgSecondary = Color(light: 0xF9FAFB, dark: 0x1C1C1E)
    static let goldfishBgTertiary = Color(light: 0xF3F4F6, dark: 0x2C2C2E)
    static let goldfishBgGrouped = Color(light: 0xF2F2F7, dark: 0x1C1C1E)

    // MARK: Text

    static let goldfishTextPrimary = Color(light: 0x111827, dark: 0xF9FAFB)
    static let goldfishTextSecondary = Color(light: 0x4B5563, dark: 0x9CA3AF)
    static let goldfishTextTertiary = Color(light: 0x6B7280, dark: 0x6B7280)
    static let goldfishTextQuaternary = Color(light: 0x9CA3AF, dark: 0x4B5563)

    // MARK: Circle Categories

    static let goldfishCircleFamily = Color(light: 0xF43F5E, dark: 0xFB7185)
    static let goldfishCircleFriends = Color(light: 0x14B8A6, dark: 0x2DD4BF)
    static let goldfishCircleProfessional = Color(light: 0x64748B, dark: 0x94A3B8)
    static let goldfishCircleCustom1 = Color(light: 0xF59E0B, dark: 0xFBBF24)
    static let goldfishCircleCustom2 = Color(light: 0x6366F1, dark: 0x818CF8)

    // MARK: Semantic

    static let goldfishSuccess = Color(light: 0x16A34A, dark: 0x4ADE80)
    static let goldfishWarning = Color(light: 0xD97706, dark: 0xFBBF24)
    static let goldfishError = Color(light: 0xDC2626, dark: 0xF87171)
    static let goldfishInfo = Color(light: 0x2563EB, dark: 0x60A5FA)

    // MARK: Graph

    static let goldfishNodeFill = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let goldfishNodeStroke = Color(light: 0xD1D5DB, dark: 0x4B5563)
    static let goldfishEdgeLine = Color(light: 0xD1D5DB, dark: 0x374151)
    static let goldfishSelectedGlow = Color.goldfishAccent.opacity(0.25)
    static let goldfishOrphanNode = Color(light: 0x9CA3AF, dark: 0x6B7280).opacity(0.50)
}

// MARK: - Hex Initializer (Dynamic Light/Dark)

extension Color {

    /// Creates a dynamic `Color` that resolves to `light` in light mode and `dark` in dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

extension UIColor {

    /// Creates a `UIColor` from a 6-digit hex integer (e.g. `0x7C3AED`).
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8)  & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
