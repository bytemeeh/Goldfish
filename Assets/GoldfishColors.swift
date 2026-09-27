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

// ============================================================================
// MARK: - Goldfish Design System (folded in — kept in an in-target file)
// ============================================================================

// MARK: - Goldfish Design System
// The single source of truth for the "warm monochrome editorial" language.
// One ink (cream), many tints. Color is spent ONLY on meaning: terracotta marks
// the one live/active element on a screen; gold is reserved for "Me".
//
// Vision: a warmly lit field journal of your people — a quiet pond at dusk.
// See DESIGN_CHANGELOG.md §2.

enum GoldfishDS {
    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 12
        static let chip: CGFloat = 10
        static let sheet: CGFloat = 24
    }
    enum Rule {
        static let hairline: CGFloat = 0.5
        static let bar: CGFloat = 2
        static let track: CGFloat = 1
    }


    // MARK: Base surfaces (dark-only app)
    static let warmBlack   = Color.goldfishBgPrimary   // app background
    static let surface     = Color.goldfishBgSecondary   // raised surface (used sparingly)
    static let surfaceHi    = Color.goldfishBgTertiary  // coin fill base / hover

    // MARK: The ink ladder — cream at fixed opacities is the ONLY source of neutrals.
    // Primary text intentionally sits at 0.96 (not pure white) to stay warm on OLED.
    static let cream = Color(hex6: 0xF5F0EB)
    static func ink(_ level: InkLevel) -> Color {
        Color(uiColor: UIColor { traits in
            let base = UIColor(hex: traits.userInterfaceStyle == .dark ? 0xF5F0EB : 0x1A1614)
            let opacity = traits.accessibilityContrast == .high && level.opacity >= 0.25 ? max(0.80, level.opacity) : level.opacity
            return base.withAlphaComponent(CGFloat(opacity))
        })
    }
    enum InkLevel {
        case primary, secondary, tertiary, quaternary, hairline, faint
        var opacity: Double {
            switch self {
            case .primary:    return 0.96
            case .secondary:  return 0.70
            case .tertiary:   return 0.62
            case .quaternary: return 0.25
            case .hairline:   return 0.12
            case .faint:      return 0.06
            }
        }
    }

    // MARK: Meaningful color (spent only on the one live thing + identity)
    static let terracotta = Color.goldfishAccent   // the single active/selected accent
    static let gold        = Color(hex6: 0xD9A441)  // "Me" — used identically everywhere

    // Warm watercolor paper — the "specimen page" surface (light, pulled from the dark pond)
    static let paper      = Color.goldfishBgPrimary
    static let inkDark     = Color.goldfishTextPrimary  // ink on paper

    // MARK: Spacing — one editorial grid. 24pt left margin is sacred.
    enum Space {
        static let pageMargin: CGFloat = 24
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 40
    }

    // MARK: Motion — three named springs. Nothing else. No ad-hoc easeInOut.
    enum Motion {
        /// Taps, toggles, segmented selection — crisp.
        static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
        /// Nav pushes, sheets, list-row appear — settles like a heavy page.
        static let settle = Animation.spring(response: 0.48, dampingFraction: 0.80)
        /// Graph idle drift + Me breathing — slow, watery, never bouncy in feel.
        static let float  = Animation.spring(response: 0.90, dampingFraction: 0.65)
    }

    // MARK: Pond identity — warm tonal "coin" tones, all within the warm family.
    // Distinguishability of the coin is intentionally subtle; the first-name label
    // carries identity. Known system ponds get fixed tones; others hash into warmth.
    static func pondTone(_ pondName: String?) -> Color {
        guard let name = pondName?.lowercased(), !name.isEmpty else { return neutralSand }
        switch name {
        case "family":       return ember
        case "friends":      return neutralSand
        case "professional", "work": return slateWarm
        default:
            // Hash unknown ponds into the warm 18–44° hue band, low saturation.
            var h: UInt64 = 1469598103934665603
            for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            let hue = 0.05 + Double(h % 1000) / 1000.0 * 0.10   // ~18°–54°
            return Color(hue: hue, saturation: 0.22, brightness: 0.62)
        }
    }
    static let ember      = Color(hex6: 0xB86B4A)  // Family — warm clay
    static let neutralSand = Color(hex6: 0xA8957B) // Friends — warm sand
    static let slateWarm   = Color(hex6: 0x6E7479) // Professional — desaturated cool, still warm-leaning
}

// MARK: - Hex helper (6-digit, opaque)
extension Color {
    init(hex6: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex6 >> 16) & 0xFF) / 255,
            green: Double((hex6 >> 8)  & 0xFF) / 255,
            blue:  Double( hex6        & 0xFF) / 255,
            opacity: 1
        )
    }
}


// MARK: - Goldfish Typography
// Two families only. New York (serif) for human content — wordmark, screen titles,
// contact names, notes set as prose. SF Pro for ALL chrome and labels.
// Everything scales with Dynamic Type via `relativeTo:` — no fully hardcoded sizes.

extension Font {

    // MARK: Human content — New York (serif)
    /// Large screen titles ("Ponds", "Settings"). ~28pt.
    static var gfDisplay: Font   { .system(.largeTitle, design: .serif).weight(.medium) }
    /// Contact detail hero name. ~26–34pt; the target of the name-flight.
    static var gfHero: Font      { .system(.largeTitle, design: .serif).weight(.medium) }
    /// A person's name in a list row. Serif gives the editorial voice on the busiest screen.
    static var gfName: Font      { .system(.headline, design: .serif).weight(.medium) }
    /// Notes / bio set as prose.
    static var gfProse: Font     { .system(.body, design: .serif) }

    // MARK: Chrome & labels — SF Pro
    /// Running body / field values.
    static var gfBody: Font      { .system(.subheadline) }
    /// Secondary metadata line under a name.
    static var gfMeta: Font      { .system(.footnote) }
    /// Uppercase tracked section labels (FAMILY, CONFIGURATION). Apply `.gfTracked()`.
    static var gfLabel: Font     { .system(.caption, design: .default).weight(.medium) }
    /// Smallest counts / captions.
    static var gfCaption: Font   { .system(.caption2) }
}

extension View {
    /// Uppercase + wide tracking for editorial section labels.
    func gfSectionLabel() -> some View {
        self.font(.gfLabel)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(GoldfishDS.ink(.tertiary))
    }
}

extension Text {
    /// First name (or nickname) for labels — the user-chosen identity unit.
    static func firstName(_ fullName: String) -> Text {
        let first = fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? fullName
        return Text(first)
    }
}

/// Pure helper: the first name / nickname from a full name, for labels.
func gfFirstName(_ fullName: String) -> String {
    fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: " ").first.map(String.init) ?? fullName
}

// Stored custom colors and stable system roles are shared by every surface.
extension GoldfishDS {
    /// Fixed ink on a colored medallion must not invert with the page appearance.
    static func avatarInk(on tone: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        guard tone.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .black }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance > 0.179 ? .black : .white
    }

    /// The graph tone keeps the user's chosen hue while reducing chroma and
    /// pulling extreme light/dark values into a quiet, readable basin range.
    /// Stored circle colors remain untouched for editing and export.
    static func graphTone(_ circle: GoldfishCircle?) -> Color {
        guard let circle else { return pondTone(nil) }
        if circle.isSystem {
            return groupTone(circle)
        }

        let raw = UIColor(Color(hex: circle.color))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 1
        guard raw.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return pondTone(circle.name)
        }
        // Preserve hue, but cap chroma so one custom swatch cannot become a
        // competing neon basin. Keep enough luminance for both appearances.
        let subduedSaturation = min(saturation, 0.42)
        let idHash = circle.id.uuidString.utf8.reduce(UInt64(1469598103934665603)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        let subtleVariation = CGFloat(Int(idHash % 9) - 4) / 100
        let readableBrightness = min(max(brightness, 0.42), 0.78)
        let variedBrightness = min(max(readableBrightness + subtleVariation, 0.42), 0.82)
        return Color(uiColor: UIColor(hue: hue, saturation: subduedSaturation,
                                      brightness: variedBrightness, alpha: 1))
    }

    static func groupTone(_ circle: GoldfishCircle?) -> Color {
        guard let circle else { return pondTone(nil) }
        if circle.isSystem {
            if circle.shouldAutoAssign(for: .mother) || circle.shouldAutoAssign(for: .parent) { return pondTone("Family") }
            if circle.shouldAutoAssign(for: .friend) { return pondTone("Friends") }
            if circle.shouldAutoAssign(for: .coworker) { return pondTone("Professional") }
        }
        return Color(hex: circle.color)
    }
}
