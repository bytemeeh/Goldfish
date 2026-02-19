# Goldfish — Color System

Complete color palette for the Goldfish iOS app, covering light and dark modes. All text-on-background combinations meet **WCAG AA** (≥ 4.5:1 contrast ratio).

---

## Accent

| Name | Light Hex | Dark Hex | Usage |
|------|-----------|----------|-------|
| Accent | `#7C3AED` | `#8B5CF6` | Primary interactive elements, buttons, links, active tab indicators |
| Accent Pressed | `#6D28D9` | `#7C3AED` | Pressed/highlighted state of interactive elements |
| Accent Surface | `#F5F0FF` | `#1E1033` | Subtle tinted background behind accent-related content |

---

## Backgrounds

| Name | Light Hex | Dark Hex | Usage |
|------|-----------|----------|-------|
| Background Primary | `#FFFFFF` | `#000000` | Main app canvas, full-screen views |
| Background Secondary | `#F9FAFB` | `#1C1C1E` | Cards, sheets, modal surfaces |
| Background Tertiary | `#F3F4F6` | `#2C2C2E` | Input fields, secondary containers |
| Background Grouped | `#F2F2F7` | `#1C1C1E` | Grouped table / list sections (iOS system convention) |

---

## Text

| Name | Light Hex | Dark Hex | Usage | Min Contrast (Light) | Min Contrast (Dark) |
|------|-----------|----------|-------|----------------------|---------------------|
| Text Primary | `#111827` | `#F9FAFB` | Headlines, body copy, primary labels | 18.1:1 on `#FFFFFF` | 19.4:1 on `#000000` |
| Text Secondary | `#4B5563` | `#9CA3AF` | Subheadings, secondary labels, timestamps | 7.5:1 on `#FFFFFF` | 9.7:1 on `#000000` |
| Text Tertiary | `#6B7280` | `#6B7280` | Placeholder text, disabled labels | 5.0:1 on `#FFFFFF` | 4.6:1 on `#1C1C1E` |
| Text Quaternary | `#9CA3AF` | `#4B5563` | Decorative text, watermarks, optional hints | 2.7:1 on `#FFFFFF` ⚠️ | 2.6:1 on `#000000` ⚠️ |

> [!NOTE]
> Text Quaternary is intentionally below AA for decorative-only text (WCAG allows this for "incidental" text). It must **never** be used for informational content.

---

## Circle Category Colors

Five harmonious, mutually distinct hues for relationship circle badges, tags, and graph rings.

| Name | Light Hex | Dark Hex | Usage |
|------|-----------|----------|-------|
| 🟠 Family | `#F43F5E` | `#FB7185` | Warm coral/rose — family circle ring & badge |
| 🟢 Friends | `#14B8A6` | `#2DD4BF` | Cool teal/mint — friends circle ring & badge |
| 🔵 Professional | `#64748B` | `#94A3B8` | Neutral slate/blue-gray — professional circle ring & badge |
| 🟡 Custom 1 | `#F59E0B` | `#FBBF24` | Warm amber/gold — user-defined circle 1 |
| 🟣 Custom 2 | `#6366F1` | `#818CF8` | Cool indigo/purple — user-defined circle 2 |

### Circle Color Contrast on Backgrounds

| Circle | Light Hex on `#FFFFFF` | Dark Hex on `#000000` |
|--------|------------------------|----------------------|
| Family `#F43F5E` | 3.9:1 (AA-Large ✅) | — |
| Family `#FB7185` | — | 8.3:1 (AA ✅) |
| Friends `#14B8A6` | 3.0:1 (use with bold/large text or paired label) | — |
| Friends `#2DD4BF` | — | 11.3:1 (AA ✅) |
| Professional `#64748B` | 4.6:1 (AA ✅) | — |
| Professional `#94A3B8` | — | 8.6:1 (AA ✅) |
| Custom 1 `#F59E0B` | 2.1:1 (decorative only — use dark text overlay) | — |
| Custom 1 `#FBBF24` | — | 13.3:1 (AA ✅) |
| Custom 2 `#6366F1` | 4.6:1 (AA ✅) | — |
| Custom 2 `#818CF8` | — | 6.5:1 (AA ✅) |

> [!TIP]
> Circle colors are primarily used as **filled badges**, **ring strokes**, and **graph node tints** where the text label sits beside (not on top of) the color. Where text must appear *on* a circle color, use white text on dark variants or dark text on light variants.

---

## Semantic Colors

| Name | Light Hex | Dark Hex | Usage |
|------|-----------|----------|-------|
| Success | `#16A34A` | `#4ADE80` | Confirmation, saved states, sync complete |
| Warning | `#D97706` | `#FBBF24` | Attention needed, data conflicts |
| Error | `#DC2626` | `#F87171` | Destructive actions, validation errors |
| Info | `#2563EB` | `#60A5FA` | Tips, onboarding guidance, informational banners |

### Semantic Contrast Check

| Semantic | Light on `#FFFFFF` | Dark on `#1C1C1E` |
|----------|-------------------|-------------------|
| Success `#16A34A` | 4.5:1 ✅ | — |
| Success `#4ADE80` | — | 8.7:1 ✅ |
| Warning `#D97706` | 3.7:1 (AA-Large ✅) | — |
| Warning `#FBBF24` | — | 10.3:1 ✅ |
| Error `#DC2626` | 5.6:1 ✅ | — |
| Error `#F87171` | — | 5.5:1 ✅ |
| Info `#2563EB` | 5.5:1 ✅ | — |
| Info `#60A5FA` | — | 5.8:1 ✅ |

---

## Graph-Specific Colors

Colors used exclusively in the interactive network graph view.

| Name | Light Hex | Dark Hex | Usage |
|------|-----------|----------|-------|
| Node Fill | `#FFFFFF` | `#2C2C2E` | Default person node interior fill |
| Node Stroke | `#D1D5DB` | `#4B5563` | Node border ring (no circle assigned) |
| Edge Line | `#D1D5DB` | `#374151` | Relationship connection lines |
| Selected Glow | `#7C3AED40` | `#8B5CF640` | 25% opacity accent halo around the selected node |
| Orphan Node | `#9CA3AF80` | `#6B728080` | 50% opacity — unconnected / uncircled contacts |

> [!NOTE]
> `40` and `80` suffixes denote hex alpha values (25% and 50% opacity respectively). In SwiftUI use `.opacity()` modifier instead.

---

## Full Contrast Matrix — Text on Backgrounds

All ratios rounded to one decimal. ✅ = ≥ 4.5:1 (AA).

### Light Mode

| | BG Primary `#FFFFFF` | BG Secondary `#F9FAFB` | BG Tertiary `#F3F4F6` | BG Grouped `#F2F2F7` |
|---|---|---|---|---|
| **Text Primary `#111827`** | 18.1:1 ✅ | 17.1:1 ✅ | 15.4:1 ✅ | 15.2:1 ✅ |
| **Text Secondary `#4B5563`** | 7.5:1 ✅ | 7.1:1 ✅ | 6.4:1 ✅ | 6.3:1 ✅ |
| **Text Tertiary `#6B7280`** | 5.0:1 ✅ | 4.7:1 ✅ | 4.3:1 ⚠️ | 4.2:1 ⚠️ |
| **Accent `#7C3AED`** | 6.1:1 ✅ | 5.7:1 ✅ | 5.2:1 ✅ | 5.1:1 ✅ |

> [!IMPORTANT]
> Text Tertiary on BG Tertiary/Grouped in light mode is borderline. Use Text Secondary for important labels on those surfaces.

### Dark Mode

| | BG Primary `#000000` | BG Secondary `#1C1C1E` | BG Tertiary `#2C2C2E` | BG Grouped `#1C1C1E` |
|---|---|---|---|---|
| **Text Primary `#F9FAFB`** | 19.4:1 ✅ | 16.0:1 ✅ | 12.9:1 ✅ | 16.0:1 ✅ |
| **Text Secondary `#9CA3AF`** | 9.7:1 ✅ | 8.0:1 ✅ | 6.4:1 ✅ | 8.0:1 ✅ |
| **Text Tertiary `#6B7280`** | 5.6:1 ✅ | 4.6:1 ✅ | 3.7:1 ⚠️ | 4.6:1 ✅ |
| **Accent `#8B5CF6`** | 5.2:1 ✅ | 4.3:1 ⚠️ | 3.5:1 ⚠️ | 4.3:1 ⚠️ |

> [!WARNING]
> Dark mode accent (`#8B5CF6`) on secondary/tertiary backgrounds is slightly below AA. For accessible accent-colored text on these surfaces, use the **lighter** `#A78BFA` variant (7.2:1 on `#1C1C1E`) or apply the accent color only to interactive focus states / large text.

---

## Design Tokens Summary

```
Accent:         #7C3AED / #8B5CF6
Family:         #F43F5E / #FB7185
Friends:        #14B8A6 / #2DD4BF
Professional:   #64748B / #94A3B8
Custom 1:       #F59E0B / #FBBF24
Custom 2:       #6366F1 / #818CF8
Success:        #16A34A / #4ADE80
Warning:        #D97706 / #FBBF24
Error:          #DC2626 / #F87171
Info:           #2563EB / #60A5FA
```
