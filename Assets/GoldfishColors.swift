import SwiftUI

// MARK: - Goldfish Color System
// Warm terracotta / Bauhaus palette — matches the approved demo design.

extension Color {

    // MARK: Accent (Terracotta)

    static let goldfishAccent = Color(light: 0xB74F3A, dark: 0xC96A54)
    static let goldfishAccentPressed = Color(light: 0x9E3F2E, dark: 0xB74F3A)
    static let goldfishAccentSurface = Color(light: 0xF5F0EB, dark: 0x1E1815)

    // MARK: Backgrounds (Warm Beige)

    static let goldfishBgPrimary = Color(light: 0xF5F0EB, dark: 0x1A1614)
    static let goldfishBgSecondary = Color(light: 0xEDE7E0, dark: 0x1E1815)
    static let goldfishBgTertiary = Color(light: 0xE5DED5, dark: 0x2A2420)
    static let goldfishBgGrouped = Color(light: 0xF0EAE3, dark: 0x1E1815)

    // MARK: Text

    static let goldfishTextPrimary = Color(light: 0x1A1614, dark: 0xF5F0EB)
    static let goldfishTextSecondary = Color(light: 0x6B6259, dark: 0xA89F95)
    static let goldfishTextTertiary = Color(light: 0xA89F95, dark: 0x6B6259)
    static let goldfishTextQuaternary = Color(light: 0xDDD6CD, dark: 0x4B4540)

    // MARK: Pond Categories (from demo)

    static let goldfishCircleFamily = Color(light: 0xB74F3A, dark: 0xC96A54)
    static let goldfishCircleFriends = Color(light: 0x3D6B8E, dark: 0x5A8DB5)
    static let goldfishCircleProfessional = Color(light: 0x8B7D3C, dark: 0xA89F60)
    static let goldfishCircleCustom1 = Color(light: 0xF59E0B, dark: 0xFBBF24)
    static let goldfishCircleCustom2 = Color(light: 0x6366F1, dark: 0x818CF8)

    // MARK: Semantic

    static let goldfishSuccess = Color(light: 0x16A34A, dark: 0x4ADE80)
    static let goldfishWarning = Color(light: 0xD97706, dark: 0xFBBF24)
    static let goldfishError = Color(light: 0xDC2626, dark: 0xF87171)
    static let goldfishInfo = Color(light: 0x2563EB, dark: 0x60A5FA)

    // MARK: Graph

    static let goldfishNodeFill = Color(light: 0xF5F0EB, dark: 0x2A2420)
    static let goldfishNodeStroke = Color(light: 0xDDD6CD, dark: 0x4B4540)
    static let goldfishEdgeLine = Color(light: 0xDDD6CD, dark: 0x3A3430)
    static let goldfishSelectedGlow = Color.goldfishAccent.opacity(0.25)
    static let goldfishOrphanNode = Color(light: 0xA89F95, dark: 0x6B6259).opacity(0.50)
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
