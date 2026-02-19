# Goldfish — UI/UX Specification

> **Platform:** iOS 17+ · **Stack:** SwiftUI · SwiftData · MapKit  
> **Version:** 1.0 · **Last updated:** 2026-02-15

---

## Table of Contents

1. [Graph Renderer Selection](#1-graph-renderer-selection)
2. [Performance Targets](#2-performance-targets)
3. [Onboarding Flow](#3-onboarding-flow)
4. [Empty States](#4-empty-states)
5. [Error States](#5-error-states)
6. [State Restoration](#6-state-restoration)
7. [Search Behavior](#7-search-behavior)
8. [Accessibility](#8-accessibility)

---

## 1. Graph Renderer Selection

### Recommendation: **SpriteKit via `SpriteView`**

#### Evaluation Matrix

| Criterion | SpriteKit + SpriteView | SwiftUI Canvas | UIKit UIScrollView |
|---|---|---|---|
| Frame rate guarantee | ✅ 60fps via display link | ⚠️ Drops under 200+ nodes | ✅ 60fps with layer caching |
| Built-in physics | ✅ `SKPhysicsWorld` | ❌ Must implement from scratch | ❌ Must implement from scratch |
| Gesture handling | ✅ Native node hit testing | ⚠️ Manual via `CGPoint` math | ✅ Via `UIGestureRecognizer` |
| SwiftUI integration | ✅ `SpriteView` embeds natively | ✅ Fully native | ⚠️ Requires `UIViewRepresentable` |
| Accessibility | ⚠️ Requires custom container | ✅ Native accessibility tree | ✅ Accessible with `UIAccessibility` |
| Zoom & pan | ✅ Camera node (`SKCameraNode`) | ⚠️ Manual transform math | ✅ `UIScrollView.zoomScale` |
| Node animations | ✅ `SKAction` system | ⚠️ Manual `withAnimation` per node | ✅ Core Animation implicit |
| Previews support | ⚠️ Limited (scene won't render) | ✅ Full preview support | ⚠️ Limited |

#### Why SpriteKit Wins

1. **Physics engine is critical.** The relationship graph requires force-directed layout: nodes repel each other, edges act as springs, and circles cluster their members. SpriteKit's `SKPhysicsBody` and `SKPhysicsJointSpring` provide this out of the box. With Canvas or UIKit, you'd need to implement Verlet integration, Barnes-Hut approximation for N-body repulsion, and spring-damper systems from scratch — roughly 800–1200 lines of non-trivial math code.

2. **Guaranteed frame rate at scale.** SpriteKit renders via Metal under the hood with a dedicated render loop decoupled from the SwiftUI view update cycle. At 500 nodes, SwiftUI Canvas would need to redraw the entire `CGContext` on every frame — each node requiring `CGContext.fillEllipse`, text rendering, and edge path stroking. SpriteKit only redraws dirty regions and hardware-accelerates sprite batching.

3. **Node hit testing is free.** `SKNode.atPoint(_:)` and `SKNode.nodes(at:)` provide pixel-accurate hit testing. With Canvas, you'd need to maintain a separate spatial index (quadtree or R-tree) and manually map gesture coordinates through transform matrices — a common source of off-by-one bugs during zoom/pan.

4. **Camera system.** `SKCameraNode` provides zoom, pan, and rotation with automatic culling of off-screen nodes. This is precisely what the graph view needs for navigating large networks.

5. **SwiftUI embedding is trivial.** Since iOS 15+, `SpriteView(scene:)` embeds cleanly in SwiftUI view hierarchies, participates in frame layout, and can communicate state changes via `@Observable` view models.

#### Mitigating SpriteKit's Weaknesses

| Weakness | Mitigation |
|---|---|
| Not declarative | Wrap scene in `@Observable` ViewModel; SwiftUI drives state, SpriteKit renders it |
| Learning curve | Graph renderer is a single isolated module; team only needs SpriteKit for this component |
| Accessibility challenges | Implement custom `UIAccessibilityContainer` on the hosting `UIView` (see §8) |
| No SwiftUI Previews | Provide a static "thumbnail" preview using SwiftUI Canvas as fallback; test graph in simulator |

#### Architecture Overview

```
┌──────────────────────────────────────────────┐
│  GraphView (SwiftUI)                         │
│  ┌────────────────────────────────────────┐  │
│  │  SpriteView(scene: graphScene)         │  │
│  └────────────────────────────────────────┘  │
│                    ▲                         │
│                    │ observes                │
│  ┌────────────────────────────────────────┐  │
│  │  GraphViewModel (@Observable)          │  │
│  │  - contacts: [Person]                  │  │
│  │  - circles: [GoldfishCircle]           │  │
│  │  - selectedContactID: UUID?            │  │
│  │  - zoomLevel: CGFloat                  │  │
│  │  - cameraPosition: CGPoint             │  │
│  └────────────────────────────────────────┘  │
│                    ▲                         │
│                    │ reads/writes            │
│  ┌────────────────────────────────────────┐  │
│  │  GraphScene (SKScene)                  │  │
│  │  - ContactNode (SKShapeNode subclass)  │  │
│  │  - EdgeLine (SKShapeNode)              │  │
│  │  - CircleRegion (SKShapeNode)          │  │
│  │  - SKCameraNode                        │  │
│  │  - SKPhysicsWorld (force-directed)     │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

#### Node Visual Specification

Each `ContactNode` contains:
- **Photo circle** — 44pt diameter (compact), 56pt (regular). If `photoData` is nil, show initials in a circle filled with `person.color` (or a deterministic pastel derived from the name hash).
- **Name label** — `SKLabelNode`, `.caption2` equivalent (11pt), truncated at 12 characters with ellipsis. Positioned directly below the photo circle, 4pt spacing.
- **Selection ring** — 2pt stroke, system accent color, appears on tap.
- **Favorite badge** — Small ★ in `Color.yellow`, positioned top-right of the photo circle. Only shown when `person.isFavorite == true`.

#### Edge Visual Specification

- Edges rendered as `SKShapeNode` with `CGMutablePath` lines.
- Stroke width: 1pt (normal), 2pt (selected/highlighted).
- Stroke color: 30% opacity of the source contact's circle color.
- Relationship type label shown at the midpoint of the edge only when either connected node is selected.

#### Circle Region Specification

- Rendered as a translucent filled `SKShapeNode` (10% opacity of the circle's color).
- Border: 1pt dashed stroke in the circle's color.
- Label: Circle emoji + name, positioned at the top-center of the region.
- Circles are laid out using a modified force-directed algorithm where circle members are attracted toward their circle's center of mass with a weaker spring constant than edge springs.

---

## 2. Performance Targets

### Budget Table

| Metric | Target | Measurement Method |
|---|---|---|
| Cold launch → interactive | < 1.5s | `os_signpost` from `didFinishLaunching` to first `onAppear` |
| Graph render (100 contacts) | < 500ms to first painted frame, 60fps pan | `MetricKit` + Instruments Time Profiler |
| Graph render (500 contacts) | < 2s to first painted frame, 30fps min pan | `MetricKit` + Instruments Time Profiler |
| Contact list scroll | 60fps always | Instruments Core Animation FPS gauge |
| Search response | < 100ms after final keystroke (150ms debounce) | `os_signpost` in search pipeline |
| vCard import (200 cards) | < 5s with progress indicator | Wall clock + `Progress` API |
| Max supported contacts | 1000 (warning at 800) | `SwiftData` fetch count check at import + launch |

### Implementation Strategies

#### Launch Performance (< 1.5s)
- Use `ModelContainer` with lazy schema migration.
- Defer graph scene creation until the graph tab is first selected (use a placeholder shimmer view).
- Precompute and cache initials + colors at write time, not read time.
- Mark `photoData` queries with `#Predicate` excluding blob data for list views.

#### Graph Rendering
- **Level-of-Detail (LOD) system:**
  - Zoom > 100%: Show full photo + name + relationship labels.
  - Zoom 50–100%: Show photo circle + truncated name.
  - Zoom 25–50%: Show colored dot (8pt) + no label.
  - Zoom < 25%: Show dot only (4pt), cluster nearby nodes.
- **Viewport culling:** Only insert `SKNode` instances for contacts within the visible camera rect + 20% bleed margin.
- **Physics scheduling:** Run physics simulation at full speed for 60 frames on initial layout, then switch to `SKPhysicsWorld.speed = 0` (frozen) until the user adds/removes a node. Resume at `speed = 0.5` for animated reflow, then freeze again after 120 frames of low energy.

#### List Scroll Performance
- Use `LazyVStack` with fixed-size rows (72pt).
- Each row only fetches: `id`, `name`, `photoData`, `isFavorite`, `color`, `phone`, `email`.
- Use `.fetchLimit` and pagination if contact count > 200.

#### Search Performance
- Maintain an in-memory `[UUID: SearchableContact]` struct with precomputed lowercase name/email/phone/notes/tags fields.
- Rebuild index on any `Person` write (debounced 500ms via `Combine`).
- Filter in-memory using `String.localizedCaseInsensitiveContains` — no database round-trip during interactive search.

#### Import Performance
- Process vCards in batches of 50 on a background `ModelActor`.
- Insert with `modelContext.insert()` in a single transaction per batch.
- Update `Progress.fractionCompleted` per batch → drive a `ProgressView` on the main thread.
- After all batches, trigger a single graph layout recomputation.

#### Contact Capacity Warning
- At import and at app launch, check `Person.fetchCount()`.
- At 800: Show an inline banner — "You have 800+ contacts. Performance may be affected above 1000."
- At 1000: Show an alert — "Goldfish supports up to 1000 contacts. Additional imports will be skipped."
- Enforce hard cap at import time; reject new inserts.

---

## 3. Onboarding Flow

Onboarding is a **one-time, four-step sequence** presented as a full-screen cover on first launch. There is no skip button until step 2. Progress is indicated by a page indicator (4 dots) at the bottom.

### Screen 1: Welcome

**What the user sees:**
- Centered app icon (goldfish logo) with a subtle float animation (2s ease-in-out, ±4pt vertical).
- App name "Goldfish" in `.largeTitle` bold.
- Tagline: "Your personal relationship map" in `.title3`, secondary color.
- Single button: **"Get Started"** — full-width, tinted, bottom-aligned with 32pt padding.

**What they can interact with:**
- Tap "Get Started" → advances to Screen 2.

**Accessibility:**
- VoiceOver reads: "Goldfish. Your personal relationship map. Get Started button."
- Reduce Motion: Float animation replaced with static positioning.

---

### Screen 2: Create Your Card

**What the user sees:**
- Navigation title: "About You"
- A profile photo placeholder circle (100pt) at the top, centered. Tap to add photo (presents `PhotosPicker`).
- Form fields:
  - **Name** (required) — `TextField`, `.textContentType(.name)`, auto-focused.
  - **Phone** (optional) — `TextField`, `.textContentType(.telephoneNumber)`, `.keyboardType(.phonePad)`.
  - **Email** (optional) — `TextField`, `.textContentType(.emailAddress)`, `.keyboardType(.emailAddress)`.
  - **Birthday** (optional) — `DatePicker`, `.datePickerStyle(.compact)`.
- Button: **"Continue"** — enabled only when Name is non-empty.
- Secondary link: "I'll set this up later" — skips and creates a minimal `isMe` contact with name "Me" and no other data.

**What happens next:**
- Creates a `Person` with `isMe = true` and the provided data.
- Creates the three system `GoldfishCircle`s (Family, Friends, Professional).
- Advances to Screen 3.

**Accessibility:**
- All fields have `.accessibilityLabel` set (e.g., "Your name, required").
- Photo placeholder reads: "Add your profile photo. Optional. Double-tap to choose a photo."

---

### Screen 3: Quick Tour (Tooltip Walkthrough)

**What the user sees:**
- The graph view is shown in the background with the `isMe` node centered.
- A tooltip overlay highlights three features sequentially:

| Step | Highlight Area | Tooltip Text | Callout Position |
|---|---|---|---|
| 1 | The "Me" node | "This is you. Your network radiates from here." | Below the node |
| 2 | The "+" button in bottom toolbar | "Tap here to add your first contact." | Above the button |
| 3 | The list/graph toggle in navigation bar | "Switch between map and list view anytime." | Below the toggle |

- Each step has a **"Next"** button in the tooltip bubble and a **"Skip Tour"** link.
- A dimmed overlay (black at 40% opacity) covers everything except the highlighted element.

**What they can interact with:**
- "Next" → advances to next tooltip.
- "Skip Tour" → jumps to Screen 4.
- After step 3, auto-advances to Screen 4.

**Accessibility:**
- VoiceOver announces each tooltip's text as the focused element.
- Reduce Motion: Tooltips appear instantly with no transition animation.

---

### Screen 4: Contacts Permission Request

**What the user sees:**
- Icon: `person.crop.circle.badge.plus` SF Symbol, 60pt, accent color.
- Headline: "Import from Contacts" in `.title2` bold.
- Body text: "Goldfish can import names and contact info from your address book. Your data stays on your device — nothing is sent anywhere." in `.body`, secondary color.
- Primary button: **"Allow Access"** — triggers `CNContactStore.requestAccess(for: .contacts)`.
- Secondary link: **"Not now"** — dismisses onboarding without requesting permission. User can import later from Settings.

**What happens next if permission is granted:**
- Show a brief progress indicator while importing contacts.
- After import, dismiss onboarding and show the graph view with imported contacts.

**What happens if permission is denied:**
- Dismiss onboarding normally.
- The graph view shows only the "Me" node.
- No error message or re-prompt. Import is available later via Settings.

**What happens if "Not now" is tapped:**
- Dismiss onboarding. Graph view shows only the "Me" node.
- Settings will show an "Import Contacts" row for deferred import.

**Accessibility:**
- Body text emphasizes privacy: VoiceOver reads "Your data stays on your device."
- The permission dialog is system-managed and natively accessible.

### Onboarding State Tracking

```swift
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
```

- Set to `true` after Screen 4 is dismissed (regardless of permission choice).
- The root view checks this flag and presents the onboarding `.fullScreenCover` if `false`.
- There is no way to re-run onboarding. The "Me" card can be edited from Settings.

---

## 4. Empty States

Every empty state follows a consistent visual pattern:
- Centered SF Symbol icon (48pt, `.secondary` color).
- Headline in `.headline` weight.
- Subtext in `.subheadline`, `.secondary` color, max 2 lines.
- Optional primary action button.

---

### 4.1 No Contacts Yet (Post-Onboarding)

**Context:** The user has completed onboarding. Only the "Me" node exists.

**Graph view:**
- The "Me" node is centered and gently pulsing (scale 1.0 → 1.05, 2s loop). 
- Below the node: "Add your first contact" in `.headline`.
- Further below: "Tap + to start building your network" in `.subheadline`, `.secondary`.
- The "+" button in the toolbar has a one-time attention animation (brief glow pulse, 3 repetitions).

**List view:**
- Icon: `person.3.fill`
- Headline: "No contacts yet"
- Subtext: "People you add will appear here."
- Button: **"Add Contact"** → opens the Add Contact form.

**What happens next:** Adding a contact dismisses the empty state and shows the contact in both views.

---

### 4.2 Circle with No Contacts

**Context:** A circle exists (system or custom) but has zero active members.

**What the user sees (in circle detail or filter view):**
- Icon: Circle's own emoji (e.g., 👨‍👩‍👧‍👦 for Family), 48pt.
- Headline: "No one in [Circle Name] yet"
- Subtext:
  - System circle: "Add a [relationship type] relationship to auto-assign, or add contacts manually."
  - Custom circle: "Drag contacts here or tap Edit to add members."
- Button: **"Add to Circle"** → opens a contact picker filtered to contacts not already in this circle.

---

### 4.3 Search with No Results

**Context:** User has typed a query but no contacts match.

**What the user sees:**
- Icon: `magnifyingglass`
- Headline: "No results for \"[query]\""
- Subtext: "Try a different name, tag, or circle."
- No action button (the search bar remains active for editing).

---

### 4.4 Contact with No Phone or Email

**Context:** Viewing a contact detail where `phone` and/or `email` are nil.

**Behavior:**
- If `phone` is nil: The "Call" and "Message" action buttons are **hidden** (not disabled, not grayed out — fully removed from the layout).
- If `email` is nil: The "Email" action button is **hidden**.
- If both are nil: The entire "Quick Actions" row is hidden. The detail view begins with the "Info" section.
- In the info section, show an inline prompt: "Add a phone number or email" as a tappable row that opens the edit form with the relevant field focused.

---

### 4.5 Contact with No Photo

**Context:** `person.photoData == nil`.

**What the user sees:**
- A circle filled with a deterministic color:
  - If `person.color` is set, use that hex color.
  - If `person.color` is nil, derive a pastel color from a hash of `person.name`:
    ```
    hue = (name.hashValue % 360) / 360.0
    saturation = 0.4
    brightness = 0.85
    ```
- The contact's initials (from `person.initials`) are centered in the circle.
- Font: `.system(.headline, design: .rounded, weight: .semibold)`, white.
- This applies everywhere: graph nodes, list rows, contact detail header, relationship rows.

---

### 4.6 Contact with No Location

**Context:** `person.locations.isEmpty` and `person.fullAddress == nil`.

**Behavior:**
- The map section in the contact detail view is **entirely hidden** — no map, no address row, no empty placeholder.
- The "Location" header in the info section is not rendered.
- When editing, the address fields are still available in the edit form with placeholder text.

---

### 4.7 Contact with No Relationships

**Context:** `person.isOrphan == true` (no `outgoingRelationships` and no `incomingRelationships`).

**What the user sees in the contact detail:**
- Under the "Relationships" section header:
  - Icon: `person.line.dotted.person`
  - Headline: "No connections yet"
  - Subtext: "Add a relationship to see how you're connected."
  - Button: **"Add Relationship"** → opens the relationship type picker, then a contact picker.

**Graph behavior:**
- Orphan nodes float at the outer edge of the graph, outside any circle region.
- They have a slightly lower opacity (0.7) compared to connected nodes (1.0).
- A subtle dotted outline (instead of solid) distinguishes them visually.

---

### 4.8 Import File with 0 Valid Contacts

**Context:** User imports a `.vcf` file that parses to 0 valid contact records.

**What the user sees:**
- Alert title: "No Contacts Found"
- Alert message: "The file didn't contain any valid contact information. Make sure it's a .vcf file with at least one contact."
- Single button: **"OK"** → dismisses the alert.

---

## 5. Error States

### 5.1 vCard Import with Malformed Data

**Context:** A `.vcf` file contains some valid and some invalid entries.

**Behavior:**
- Valid contacts are imported normally.
- Invalid entries (missing `FN` property, unparseable fields) are silently skipped.
- After import completes, show a **banner notification** (not an alert):
  - If all succeeded: "✓ [N] contacts imported" — green tint, auto-dismiss after 3s.
  - If some skipped: "⚠ [N] contacts imported, [M] couldn't be read" — amber tint, auto-dismiss after 5s.
  - Tapping the banner does nothing (no drill-down into skipped entries).
- The skipped count is logged to `os_log` at `.info` level for diagnostics.

### 5.2 Photo Too Large

**Context:** User selects a photo from `PhotosPicker` that exceeds the 500KB / 800×800 limit.

**Behavior:**
- **The user never sees an error.** The repository layer silently:
  1. Resizes the image to fit within 800×800px preserving aspect ratio.
  2. Compresses to JPEG at quality 0.7.
  3. If still > 500KB, iteratively lowers quality in 0.1 steps until within budget.
  4. Stores the compressed data in `person.photoData`.
- No toast, no alert, no logging to the user. This is a transparent optimization.

### 5.3 Location Permission Denied

**Context:** The user previously denied location permission, or has it disabled in Settings.

**Behavior:**
- The "Nearby" / proximity filter in the contact list is **hidden** (not disabled).
- In Settings, under a "Location" section:
  - Show an explanatory row: "Location access lets Goldfish show nearby contacts on the map."
  - Below it: A **"Open Settings"** button that deep-links to `UIApplication.openSettingsURLString`.
- Map views in contact details still render if the contact has stored coordinates — the denied permission only affects the user's *own* location for proximity features.

### 5.4 iCloud Sync Conflict

**Context:** Two devices edit the same `Person` record and sync produces a conflict.

**Behavior:**
- **No user-facing UI.** Conflicts are resolved automatically using a **latest-wins** strategy:
  - Compare `updatedAt` timestamps on the conflicting records.
  - Keep the record with the more recent `updatedAt`.
  - If timestamps are identical (edge case), keep the record from the current device.
- This is configured in the `ModelConfiguration` with the default CloudKit merge policy (`.mergeByPropertyObjectTrump`).
- Conflict resolutions are logged to `os_log` at `.debug` level.

### 5.5 Database Corruption

**Context:** SwiftData fails to open the `ModelContainer` at launch (persistent store error).

**What the user sees:**
- A full-screen recovery view replaces the normal app UI:
  - Icon: `exclamationmark.triangle.fill`, 64pt, `.red`.
  - Headline: "Something went wrong" in `.title2`.
  - Body: "Goldfish's data couldn't be loaded. You can export your data as a backup and reinstall the app to fix this." in `.body`.
  - Primary button: **"Export Backup"** — attempts to serialize what data is recoverable to a `.vcf` file and presents a `ShareLink` / `UIActivityViewController`.
  - Secondary button: **"Try Again"** — attempts to re-initialize the `ModelContainer`.
  - Tertiary link: **"Contact Support"** — opens `mailto:` with pre-filled subject line.

**Technical details:**
- The app wraps `ModelContainer` initialization in a `do/catch`.
- On failure, set an `@Published var databaseError: Error?` on the root app state.
- The root `WindowGroup` checks this flag and shows the recovery view instead of the normal navigation.

---

## 6. State Restoration

### Strategy

Use `@AppStorage` for user preferences that survive app deletion/reinstall, and `@SceneStorage` for ephemeral UI state that restores within the same app lifecycle.

### Restored State Table

| State | Storage | Key | Type | Default |
|---|---|---|---|---|
| View mode (graph/list) | `@AppStorage` | `"homeViewMode"` | `String` (`"graph"` or `"list"`) | `"graph"` |
| List scroll position | `@SceneStorage` | `"listScrollPosition"` | `String` (contact UUID) | `nil` |
| Graph zoom level | `@SceneStorage` | `"graphZoomLevel"` | `Double` | `1.0` |
| Graph camera X | `@SceneStorage` | `"graphCameraX"` | `Double` | `0.0` |
| Graph camera Y | `@SceneStorage` | `"graphCameraY"` | `Double` | `0.0` |
| Open contact sheet ID | `@SceneStorage` | `"openContactSheetID"` | `String` (UUID) | `nil` |
| Search query | Not restored | — | — | `""` |
| Selected circle filter | `@SceneStorage` | `"selectedCircleID"` | `String` (UUID) | `nil` |
| Onboarding completed | `@AppStorage` | `"hasCompletedOnboarding"` | `Bool` | `false` |
| Sort order preference | `@AppStorage` | `"contactSortOrder"` | `String` | `"name"` |

### Restoration Behavior

**On app relaunch (cold start):**
1. Check `hasCompletedOnboarding`. If `false`, show onboarding flow (§3).
2. Restore `homeViewMode` to show graph or list.
3. If `homeViewMode == "graph"`, apply saved zoom level and camera position.
4. If `homeViewMode == "list"`, use `ScrollViewReader.scrollTo()` with the saved UUID.
5. If `openContactSheetID` is set and the contact still exists, present the contact detail sheet.

**On scene disconnect (backgrounding):**
- SwiftUI automatically persists `@SceneStorage` values.
- Write `graphZoomLevel`, `graphCameraX`, `graphCameraY` from the `GraphViewModel` to `@SceneStorage` in `scenePhase == .background`.

**Edge cases:**
- If a restored contact ID no longer exists (deleted on another device), silently clear the stored ID.
- If the restored zoom level is out of bounds (< 0.1 or > 5.0), clamp to the valid range.

---

## 7. Search Behavior

### Activation

| Trigger | From View | Behavior |
|---|---|---|
| Pull-down gesture | List view | Reveals the search bar inline at the top of the list (`.searchable` modifier) |
| Tap search icon (🔍) | Navigation bar (both views) | Activates the search bar with keyboard focus |
| Keyboard shortcut ⌘F | Either view (iPad) | Activates search |

### Search Pipeline

```
User keystroke
    │
    ▼
150ms debounce timer (Combine `debounce`)
    │
    ▼
Normalize query: lowercased, trimmed, diacritics folded
    │
    ▼
Filter in-memory SearchIndex (no database query)
    │
    ▼
Return [Person] results
    │
    ▼
Display as filtered list (even if in graph mode)
```

### Search Scope

The query matches against these fields using `localizedCaseInsensitiveContains`:

| Field | Source | Example Match |
|---|---|---|
| Name | `person.name` | "Mar" matches "Marcel Meeh" |
| Email | `person.email` | "gmail" matches "marcel@gmail.com" |
| Phone | `person.phone` | "0176" matches "+49 176 1234567" |
| Notes | `person.notes` | "birthday" matches "Bring cake for his birthday" |
| Tags | `person.tags` | "gym" matches tag "gym buddy" |
| Circle name | via `circleContacts.circle.name` | "fam" matches circle "Family" |
| Relationship type | via `allRelationships.type.displayName` | "mother" matches relationship type |

### Results Display

**When search is active (query is non-empty):**
- **In list mode:** The list is filtered in-place. Matching contacts remain; non-matching contacts are hidden. The section headers (alphabetical or by circle) are preserved if they contain at least one match.
- **In graph mode:** A temporary list overlay slides up from the bottom, covering the graph. This list shows the filtered results. Tapping a result:
  1. Dismisses the search overlay.
  2. Animates the graph camera to center on the selected node.
  3. Selects the node (shows selection ring).
  4. After 500ms, presents the contact detail sheet if the user tapped (not just navigated).

**Result row layout:**
- Same as the standard contact list row: photo/initials circle (40pt), name, subtitle (phone or email, whichever is present first).
- Matching text is **not** highlighted (keeping the UI clean). The relevance is implied by the filter.

### Empty Search State

See §4.3.

### Dismissal

- Tap "Cancel" button → clears query, dismisses search, restores full list/graph.
- Swipe down on the search overlay (graph mode) → dismisses.
- Clear the text field → shows full list again (but search bar stays visible).

---

## 8. Accessibility

### 8.1 VoiceOver Labels

Every interactive element must have an explicit `accessibilityLabel` and, where applicable, an `accessibilityHint`.

| Element | Label | Hint | Trait |
|---|---|---|---|
| Contact list row | "[Name]. [Relationship], [Circle]." | "Double-tap to view details." | `.button` |
| Graph node | "[Name]. [Circle name]. [N] connections." | "Double-tap to view details. Drag to reposition." | `.button`, `.adjustable` |
| Add contact button (+) | "Add contact" | "Creates a new contact." | `.button` |
| View mode toggle | "Switch to [list/graph] view" | — | `.button` |
| Search bar | "Search contacts" | "Search by name, phone, email, tags, or circle." | `.searchField` |
| Circle badge | "[Circle name] circle. [N] members." | "Double-tap to filter by this circle." | `.button` |
| Favorite toggle | "[Name] is [not] a favorite" | "Double-tap to toggle favorite." | `.button` |
| Delete action | "Delete [Name]" | "Permanently removes this contact." | `.button` |
| Photo placeholder | "[Name]'s initials, [XX]" | — | `.image` |
| Relationship row | "[Name] is your [type]" | "Double-tap to view [Name]." | `.button` |

### 8.2 Dynamic Type

**Rule:** No hardcoded font sizes anywhere. All text uses Apple's type styles.

| Context | Text Style | Weight |
|---|---|---|
| Navigation titles | `.largeTitle` | `.bold` |
| Section headers | `.headline` | `.semibold` |
| Contact name (list) | `.body` | `.regular` |
| Contact subtitle (list) | `.subheadline` | `.regular` |
| Contact name (detail) | `.title` | `.bold` |
| Graph node name | `.caption2` | `.medium` |
| Button labels | `.body` | `.semibold` |
| Empty state headline | `.headline` | `.semibold` |
| Empty state subtext | `.subheadline` | `.regular` |
| Form labels | `.body` | `.regular` |
| Form values | `.body` | `.regular` |

**Scaling behavior:**
- List rows expand vertically to accommodate larger text sizes.
- At Accessibility sizes (AX1–AX5), list rows switch to a stacked layout (name above subtitle) instead of side-by-side.
- Graph node names are capped at `.body` equivalent to prevent label overlap. A VoiceOver rotor provides full name access.
- The navigation bar uses `.inline` display style at AX sizes to preserve screen space.

### 8.3 Reduce Motion

When `UIAccessibility.isReduceMotionEnabled == true`:

| Normal Animation | Reduced Motion Alternative |
|---|---|
| Graph force-directed settling (nodes spring into place) | Instant layout, no animation |
| Node selection ring pulse | Static ring, no pulse |
| Onboarding logo float animation | Static centered logo |
| Tooltip overlay transitions | Cross-dissolve (0.15s) instead of slide |
| Contact detail sheet presentation | Reduced spring animation |
| Search overlay slide-up | Cross-dissolve |
| Favorite toggle star animation | Instant state change |
| Node drag spring-back | Instant reposition |
| "Me" node attention pulse | Static presentation |

**Implementation:**
```swift
let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .spring()
withAnimation(animation) { /* state change */ }
```

For SpriteKit: Check the flag in `GraphScene.didMove(to:)` and set `SKAction` durations to 0 when reduce motion is enabled.

### 8.4 Graph Accessibility Container

The SpriteKit graph is not natively accessible. We implement a custom accessibility container on the `SpriteView`'s underlying `UIView`:

**Architecture:**
```
SpriteView (UIView)
  └─ accessibilityContainerType = .list
  └─ accessibilityElements = [ContactAccessibilityElement]
```

**ContactAccessibilityElement** (subclass of `UIAccessibilityElement`):
- `accessibilityLabel`: "[Name]. [Circle]. [N] connections."
- `accessibilityValue`: "[Phone], [Email]" (if available)
- `accessibilityHint`: "Double-tap to view details. Three-finger swipe to navigate between contacts."
- `accessibilityFrame`: The screen-space frame of the node, updated on zoom/pan.
- `accessibilityTraits`: `.button`
- Custom `accessibilityCustomActions`:
  - "View details" → opens contact detail sheet.
  - "Toggle favorite" → toggles `isFavorite`.

**VoiceOver Rotor:**
- Register a custom rotor named "Contacts" via `UIAccessibilityCustomRotor`.
- Rotating the rotor cycles through contacts alphabetically.
- When a contact is focused, the graph camera pans to center on that node.

**Update cycle:**
- Rebuild `accessibilityElements` whenever the contacts array changes.
- Update `accessibilityFrame` on every camera move (debounced 100ms).

### 8.5 Color Contrast

**Minimum requirements:**

| Element | Foreground | Background | Ratio | Passes |
|---|---|---|---|---|
| Body text | `label` (system) | `systemBackground` | 15.3:1 (light) / 15.5:1 (dark) | ✅ |
| Subtitle text | `secondaryLabel` | `systemBackground` | 7.0:1 (light) / 7.2:1 (dark) | ✅ |
| Graph node name | `.white` | Node color circle | Must be ≥ 4.5:1 | ✅ (enforced by pastel palette) |
| Circle region label | Circle color | Region fill (10% opacity) | Must be ≥ 4.5:1 | ✅ (label is on full-opacity background) |
| Button text | `.white` | Accent color | Must be ≥ 4.5:1 | ✅ (checked per-theme) |

**Initials contrast enforcement:**
- For the initials avatar, always use white text on the color circle.
- The pastel color generator (§4.5) uses `brightness = 0.85` and `saturation = 0.4`, which guarantees a minimum contrast of 4.7:1 against white text.
- If `person.color` is user-set and fails contrast check against white, automatically darken the color by reducing brightness by 0.15 increments until 4.5:1 is reached.

### 8.6 Image Accessibility

| Image Context | Accessibility Description |
|---|---|
| Contact photo | "[Name]'s photo" |
| Initials avatar | "[Name]'s initials, [XX]" |
| App logo (onboarding) | "Goldfish app logo" |
| Empty state SF Symbol | Decorative — `accessibilityHidden(true)` |
| Circle emoji | "[Circle name] circle" |
| Relationship type icon | "[Type] relationship" |
| Map annotation | "[Name]'s [location type] location" |

**Decorative images** (empty state icons, dividers, background elements) are hidden from VoiceOver using `.accessibilityHidden(true)`.

---

## Appendix A: Screen Inventory

| Screen | Presentation | Back/Dismiss |
|---|---|---|
| Home (Graph) | Root view, tab equivalent | — |
| Home (List) | Root view, toggle | — |
| Contact Detail | Sheet (from graph), push (from list) | Drag to dismiss / back button |
| Add Contact Form | Sheet | Cancel / Save |
| Edit Contact Form | Push (from detail) | Cancel / Save |
| Circle Detail | Push or sheet | Back button |
| Add Relationship | Sheet (from detail) | Cancel / Done |
| Search Overlay (graph) | Overlay from bottom | Cancel / tap result |
| Settings | NavigationLink from tab/menu | Back button |
| Import Progress | Sheet (non-dismissible during import) | Dismisses on completion |
| Onboarding (4 screens) | Full-screen cover | Sequence flow |
| Database Recovery | Full-screen replacement | "Try Again" |

## Appendix B: Navigation Architecture

```
App
├── if !hasCompletedOnboarding → OnboardingFlow (fullScreenCover)
├── if databaseError → RecoveryView (fullScreenCover)
└── MainTabView / NavigationSplitView
    ├── Home
    │   ├── Graph View (SpriteView)
    │   │   └── Contact Detail (sheet)
    │   └── List View (LazyVStack)
    │       └── Contact Detail (NavigationLink push)
    │           ├── Edit Contact (push)
    │           ├── Add Relationship (sheet)
    │           └── Map View (inline)
    └── Settings
        ├── Edit My Card (push)
        ├── Import/Export (push)
        ├── Privacy Policy (sheet, SafariView)
        ├── Support (mailto:)
        └── About (inline)
```

## Appendix C: Gesture Reference

| Gesture | View | Action |
|---|---|---|
| Single tap | Graph node | Select node, show selection ring |
| Double tap | Graph node | Open contact detail sheet |
| Long press (0.5s) | Graph node | Enter repositioning mode (node lifts, shadow deepens) |
| Drag | Graph node (after long press) | Reposition node, breaks physics spring temporarily |
| Pinch | Graph background | Zoom in/out (0.25× to 4×) |
| Two-finger pan | Graph background | Pan camera |
| Single tap | Graph background | Deselect any selected node |
| Pull down | List view | Reveal search bar |
| Swipe left | List row | Reveal delete action |
| Tap | List row | Push to contact detail |
| Long press | List row | Context menu (Call, Message, Edit, Delete) |
