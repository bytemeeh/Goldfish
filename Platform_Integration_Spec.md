# Goldfish — Platform Integration Specification

> **Platform:** iOS 17+ · **Stack:** SwiftUI · SwiftData · MapKit  
> **Version:** 1.0 · **Last updated:** 2026-02-15

---

## Table of Contents

1. [Permissions Matrix](#1-permissions-matrix)
2. [Sharing Design (Local-Only)](#2-sharing-design-local-only)
3. [vCard X-GOLDFISH-\* Extension Spec](#3-vcard-x-goldfish--extension-spec)
4. [Photo Pipeline](#4-photo-pipeline)
5. [Privacy Nutrition Label](#5-privacy-nutrition-label)

---

## 1. Permissions Matrix

### Overview

Goldfish requests permissions **contextually** — never at launch, never in a batch. Each prompt appears the *first time* the user triggers the feature that requires it. If denied, the feature degrades gracefully with no error alerts and no re-prompting.

### 1.1 Contacts — `CNContactStore`

| Attribute | Value |
|---|---|
| **Framework** | `Contacts` / `CNContactStore` |
| **Authorization level** | `CNAuthorizationStatus` → `.authorized` |
| **Info.plist key** | `NSContactsUsageDescription` |
| **User-facing string** | *"Goldfish imports names and phone numbers from your address book so you can build your relationship map. Your contacts stay on your device and are never sent to a server."* |
| **When requested** | **Onboarding Screen 4** ("Import from Contacts") — or later when the user taps "Import Contacts" in Settings. Never at cold launch. |
| **Request code** | `CNContactStore().requestAccess(for: .contacts)` |

**Graceful degradation when denied:**

| Feature | Behavior |
|---|---|
| Onboarding import | Skipped. Graph shows only the "Me" node. No error shown. |
| Settings → Import Contacts | Row displays explanatory text: *"Goldfish needs access to your contacts to import them."* Below: **"Open Settings"** button → `UIApplication.openSettingsURLString`. |
| Manual contact creation | Fully functional. Users can always add contacts by hand. |
| Contact deduplication | Unavailable (no address book to compare against). Silent. |

**Fetched keys (minimal set):**
```swift
let keysToFetch: [CNKeyDescriptor] = [
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactBirthdayKey as CNKeyDescriptor,
    CNContactPostalAddressesKey as CNKeyDescriptor,
    CNContactThumbnailImageDataKey as CNKeyDescriptor,
    CNContactNoteKey as CNKeyDescriptor
]
```

> [!NOTE]
> We fetch `CNContactThumbnailImageDataKey` (not `imageData`) to keep import memory footprint low. The thumbnail is resized through the photo pipeline (§4) before storage.

---

### 1.2 Location — `CLLocationManager` (When In Use)

| Attribute | Value |
|---|---|
| **Framework** | `CoreLocation` / `CLLocationManager` |
| **Authorization level** | `.authorizedWhenInUse` only — never `.authorizedAlways` |
| **Info.plist key** | `NSLocationWhenInUseUsageDescription` |
| **User-facing string** | *"Goldfish uses your location to show which of your contacts are nearby. Your location is never stored, shared, or sent anywhere."* |
| **When requested** | First time the user activates the **"Nearby"** proximity filter in the contact list, or the first time they view the full-screen map. Never at launch, never during onboarding. |
| **Request code** | `CLLocationManager().requestWhenInUseAuthorization()` |

**Graceful degradation when denied:**

| Feature | Behavior |
|---|---|
| Proximity filter ("Nearby") | **Hidden entirely** — the filter chip does not appear in the UI. Not disabled, not grayed — removed from layout. |
| Map in contact detail | **Still works.** If the contact has stored address coordinates, the map renders those locations. Only the user's *own* blue dot is missing. Map annotation pins still display. |
| Settings → Location | Shows explanatory row: *"Location access lets Goldfish show nearby contacts."* Below: **"Open Settings"** button. |

**Implementation notes:**
- Use `CLLocationManager.location` for a **single on-demand read** when the filter is activated. Do not start continuous location updates.
- Set `desiredAccuracy = kCLLocationAccuracyHundredMeters` — proximity filtering doesn't need GPS precision.
- The user's coordinates are held in memory only (a `CLLocation?` property on the ViewModel). They are **never persisted** to SwiftData, UserDefaults, or any file.

> [!IMPORTANT]
> Goldfish must *not* include `NSLocationAlwaysAndWhenInUseUsageDescription` or `NSLocationAlwaysUsageDescription` in Info.plist. Including either key — even unused — may trigger App Review scrutiny and requires justification.

---

### 1.3 Photo Library — `PHPickerViewController`

| Attribute | Value |
|---|---|
| **Framework** | `PhotosUI` / `PHPickerViewController` (iOS 14+) |
| **Info.plist key** | **None required** |
| **User-facing string** | **None — no system prompt appears** |
| **When triggered** | User taps the photo placeholder in the Add/Edit Contact form to choose a photo from their library. |
| **Request code** | Present `PHPickerViewController` with `.filter(.images)` and `selectionLimit = 1`. |

**Why no permission is needed:**

`PHPickerViewController` runs in a **separate process** outside the app sandbox. The host app only receives the specific image(s) the user explicitly selects — it never gains access to the full photo library. Apple [explicitly states](https://developer.apple.com/documentation/photokit/phpickerviewcontroller) this does not require `NSPhotoLibraryUsageDescription`.

> [!WARNING]
> Do **not** use `UIImagePickerController` with `.sourceType = .photoLibrary` — that older API *does* require the `NSPhotoLibraryUsageDescription` key and triggers a permission dialog. Always use `PHPickerViewController` for library access.

**Graceful degradation:**
There is no denial scenario — `PHPickerViewController` is always available. If the user dismisses the picker without selecting a photo, the existing photo (or initials fallback) remains unchanged.

---

### 1.4 Camera — `AVCaptureDevice`

| Attribute | Value |
|---|---|
| **Framework** | `AVFoundation` / `AVCaptureDevice` |
| **Info.plist key** | `NSCameraUsageDescription` |
| **User-facing string** | *"Goldfish uses your camera to take a photo for this contact. Photos are stored on your device and never uploaded."* |
| **When requested** | User taps the **"Take Photo"** option in the photo action sheet on the Add/Edit Contact form. Never at launch, never during onboarding. |
| **Request code** | `AVCaptureDevice.requestAccess(for: .video)` — or implicitly via `UIImagePickerController(sourceType: .camera)` |

**Graceful degradation when denied:**

| Feature | Behavior |
|---|---|
| "Take Photo" option | **Hidden** from the action sheet. Only "Choose from Library" remains. |
| Contact creation | Fully functional — user can still pick from library or use initials. |
| Settings | No dedicated "Camera" row needed. Camera is an optional convenience; the photo library picker is the primary path. |

**Camera availability check:**
```swift
// Only show "Take Photo" if both hardware and permission allow it
var canTakePhoto: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera) &&
    AVCaptureDevice.authorizationStatus(for: .video) != .denied
}
```

If `authorizationStatus == .notDetermined`, show the option — the system will prompt on first tap. If `.denied` or `.restricted`, hide it silently.

---

### 1.5 Permissions Summary Table

| Permission | Info.plist Key | Prompt Timing | If Denied |
|---|---|---|---|
| Contacts | `NSContactsUsageDescription` | Onboarding Screen 4 or Settings import | Hide import; manual creation works |
| Location (When In Use) | `NSLocationWhenInUseUsageDescription` | First "Nearby" filter or map view | Hide proximity filter; static maps work |
| Photo Library | *None* (PHPicker) | N/A — no prompt | N/A — always available |
| Camera | `NSCameraUsageDescription` | First "Take Photo" tap | Hide camera option; library picker works |

### 1.6 Info.plist Entries

```xml
<key>NSContactsUsageDescription</key>
<string>Goldfish imports names and phone numbers from your address book so you can build your relationship map. Your contacts stay on your device and are never sent to a server.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Goldfish uses your location to show which of your contacts are nearby. Your location is never stored, shared, or sent anywhere.</string>

<key>NSCameraUsageDescription</key>
<string>Goldfish uses your camera to take a photo for this contact. Photos are stored on your device and never uploaded.</string>
```

> [!NOTE]
> No `NSPhotoLibraryUsageDescription` is needed. Using `PHPickerViewController` eliminates this requirement entirely.

---

## 2. Sharing Design (Local-Only)

### 2.1 Design Rationale

The original design relied on token-based share links backed by a server. Since Goldfish is local-first with no backend, sharing is redesigned around **vCard file export** using the native iOS share sheet.

**Principles:**
- No server. No URLs. No accounts. No analytics.
- Uses the universally supported `.vcf` (vCard 3.0) format.
- Goldfish-specific metadata is preserved via `X-GOLDFISH-*` extension fields (§3).
- The recipient can open the file in **any** contacts app (standard vCard) or in **Goldfish** (which also reads the extension fields).

---

### 2.2 Export Flow

#### User-Facing Flow

```
User opens Contact Detail or selects contacts in List
       │
       ▼
Taps share icon (square.and.arrow.up)
       │
       ▼
┌─────────────────────────────────────┐
│  Share Options Sheet                │
│                                     │
│  ○ Share just this contact          │
│  ○ Share with connections           │
│    └─ Depth picker: 1 / 2 / 3      │
│                                     │
│  [Preview: "3 contacts, 2 KB"]      │
│                                     │
│  [ Share ]  (primary action)        │
└─────────────────────────────────────┘
       │
       ▼
UIActivityViewController (native share sheet)
       │
       ├─ AirDrop
       ├─ Messages
       ├─ Mail
       ├─ Save to Files
       ├─ Copy
       └─ Third-party apps
```

#### Depth Selection Logic

| Option | What's included | Use case |
|---|---|---|
| **Just this contact** | Single person → 1 vCard entry | Sharing someone's contact info |
| **With connections, depth 1** | Selected person + all directly connected contacts | Sharing a person with their immediate network |
| **With connections, depth 2** | Depth 1 + connections of those connections | Sharing a cluster (e.g., a whole family) |
| **With connections, depth 3** | Depth 2 + one more level | Sharing a large network segment |

**Connection traversal algorithm:**
```
func collectContacts(root: Person, maxDepth: Int) -> Set<Person> {
    var visited: Set<UUID> = []
    var queue: [(person: Person, depth: Int)] = [(root, 0)]
    var result: Set<Person> = []
    
    while !queue.isEmpty {
        let (person, depth) = queue.removeFirst()
        guard !visited.contains(person.id) else { continue }
        visited.insert(person.id)
        result.insert(person)
        
        if depth < maxDepth {
            for connected in person.connectedContacts {
                queue.append((connected, depth + 1))
            }
        }
    }
    return result
}
```

- The BFS traversal follows both outgoing and incoming relationships.
- The `isMe` contact is **excluded** from depth-based export (the user's personal card is never shared alongside others unless explicitly selected as the root).
- Circle memberships are included as `X-GOLDFISH-CIRCLE` entries on each contact.
- Relationships between exported contacts are included as `X-GOLDFISH-RELATED-TO` entries.

---

### 2.3 vCard File Generation

**File name:** `Goldfish_Export_[YYYY-MM-DD].vcf`  
**Encoding:** UTF-8  
**Format:** vCard 3.0 (RFC 2426) — widest compatibility across platforms  

Multiple contacts are concatenated into a single `.vcf` file (each between `BEGIN:VCARD` and `END:VCARD` markers, as per spec).

**Mapping from `Person` model to vCard fields:**

| Person property | vCard field | Notes |
|---|---|---|
| `name` | `FN` / `N` | `FN` = full name. `N` = structured (Family;Given;;;) |
| `phone` | `TEL;TYPE=CELL` | Single phone field |
| `email` | `EMAIL;TYPE=INTERNET` | Single email field |
| `birthday` | `BDAY` | ISO 8601 date (YYYY-MM-DD) |
| `notes` | `NOTE` | Free-form text, line-folded |
| `street`, `city`, etc. | `ADR` | Structured address field |
| `photoData` | `PHOTO;ENCODING=b;TYPE=JPEG` | Base64-encoded JPEG |
| `tags` | `X-GOLDFISH-TAGS` | Comma-separated |
| `color` | `X-GOLDFISH-COLOR` | Hex string |
| `isFavorite` | `X-GOLDFISH-FAVORITE` | "true" / "false" |
| `isMe` | `X-GOLDFISH-IS-ME` | "true" if personal card |
| Circles | `X-GOLDFISH-CIRCLE` | One per circle, repeatable |
| Relationships | `X-GOLDFISH-RELATED-TO` | UUID + type, repeatable |

---

### 2.4 Import Flow

**Two import paths exist:**

#### Path A: OS-level vCard import (any app)
1. User receives a `.vcf` file via AirDrop, Messages, Mail, etc.
2. iOS offers to "Add to Contacts" — standard system behavior.
3. Standard vCard fields (name, phone, email, photo, etc.) are imported into the iOS Contacts app.
4. `X-GOLDFISH-*` fields are silently ignored by the system contacts app.

#### Path B: Goldfish-aware import
1. User receives a `.vcf` file.
2. If Goldfish is installed, it appears as a "Open in Goldfish" option via Registered UTType.
3. Goldfish parses the vCard including all `X-GOLDFISH-*` extensions.
4. Tags, circles, relationships, favorites, colors — all metadata is restored.
5. Duplicate detection: match on `name` + `phone` OR `name` + `email`. If a match exists, present a merge dialog:
   - **"Update existing"** — merge new data into the existing contact.
   - **"Import as new"** — create a separate contact.
   - **"Skip"** — do not import this contact.

#### UTType Registration

Register Goldfish as a handler for `.vcf` files in `Info.plist`:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>vCard</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.vcard</string>
        </array>
    </dict>
</array>
```

**`LSHandlerRank = Alternate`** ensures Goldfish shows as an option but doesn't hijack `.vcf` from the system Contacts app.

#### `.goldfish` Bundle Format (Optional, Future)

For richer exports that include relationship graph structure, define a custom UTType:

| Attribute | Value |
|---|---|
| **Extension** | `.goldfish` |
| **UTType identifier** | `com.goldfish.export` |
| **Conforms to** | `public.data`, `public.content` |
| **MIME type** | `application/x-goldfish-export` |
| **Description** | "Goldfish Contact Bundle" |

**Bundle structure:**
```
export.goldfish
├── contacts.vcf          ← All contacts with X-GOLDFISH-* extensions
├── relationships.json    ← Full relationship graph as JSON
└── metadata.json         ← Export date, Goldfish version, contact count
```

**Info.plist UTType declaration:**
```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.content</string>
        </array>
        <key>UTTypeDescription</key>
        <string>Goldfish Contact Bundle</string>
        <key>UTTypeIdentifier</key>
        <string>com.goldfish.export</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>goldfish</string>
            </array>
            <key>public.mime-type</key>
            <string>application/x-goldfish-export</string>
        </dict>
    </dict>
</array>
```

> [!TIP]
> For v1, use the single `.vcf` file approach. The `.goldfish` bundle format is reserved for a future version where full graph topology preservation is critical (e.g., team/family shared networks).

---

### 2.5 UIActivityViewController Integration

```swift
func shareContacts(_ contacts: [Person], depth: Int) {
    let exportContacts = collectContacts(roots: contacts, maxDepth: depth)
    let vcfData = VCardExporter.export(exportContacts)
    
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Goldfish_Export_\(dateString).vcf")
    try vcfData.write(to: tempURL)
    
    let activityVC = UIActivityViewController(
        activityItems: [tempURL],
        applicationActivities: nil
    )
    
    // Exclude irrelevant activities
    activityVC.excludedActivityTypes = [
        .addToReadingList,
        .assignToContact,   // Would create duplicates
        .openInIBooks,
        .postToFacebook,
        .postToTwitter,
        .postToWeibo,
        .postToFlickr,
        .postToVimeo,
        .postToTencentWeibo
    ]
    
    // Clean up temp file after sharing completes
    activityVC.completionWithItemsHandler = { _, _, _, _ in
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    present(activityVC)
}
```

---

## 3. vCard X-GOLDFISH-* Extension Spec

### 3.1 Extension Field Definitions

All custom fields use the `X-GOLDFISH-` prefix per RFC 6350 §6.10 (private-use extensions). These fields are ignored by non-Goldfish vCard parsers and do not affect standard import behavior.

---

#### `X-GOLDFISH-TAGS`

| Attribute | Value |
|---|---|
| **Cardinality** | 0 or 1 per vCard |
| **Value type** | TEXT |
| **Format** | Comma-separated list, no spaces after commas |
| **Encoding** | UTF-8 |
| **Example** | `X-GOLDFISH-TAGS:gym,book-club,neighbor` |

**Rules:**
- Tags are lowercased on export and matched case-insensitively on import.
- Tags containing commas must be escaped: `tag\,name` → unescaped to `tag,name`.
- Empty tags are stripped.
- Maximum 50 tags per contact (enforced at export).

---

#### `X-GOLDFISH-RELATIONSHIP-TYPE`

| Attribute | Value |
|---|---|
| **Cardinality** | 0..N per vCard (repeatable) |
| **Value type** | TEXT |
| **Format** | One of the `RelationshipType` raw values |
| **Valid values** | `mother`, `father`, `sibling`, `spouse`, `partner`, `friend`, `coworker`, `child`, `other` |
| **Example** | `X-GOLDFISH-RELATIONSHIP-TYPE:mother` |

**Rules:**
- Multiple instances indicate this contact holds multiple relationship types within the export.
- This field describes what relationship type(s) this contact *is* in the context of the export bundle — the specific connection is defined by `X-GOLDFISH-RELATED-TO`.
- Unknown values are imported as `other`.

---

#### `X-GOLDFISH-FAVORITE`

| Attribute | Value |
|---|---|
| **Cardinality** | 0 or 1 per vCard |
| **Value type** | TEXT |
| **Valid values** | `true`, `false` |
| **Default** | `false` (if field is absent) |
| **Example** | `X-GOLDFISH-FAVORITE:true` |

---

#### `X-GOLDFISH-CIRCLE`

| Attribute | Value |
|---|---|
| **Cardinality** | 0..N per vCard (repeatable) |
| **Value type** | TEXT |
| **Format** | Circle display name |
| **Example** | `X-GOLDFISH-CIRCLE:Family` |

**Rules:**
- Each instance represents one circle membership.
- On import, Goldfish matches circle names case-insensitively. If a circle doesn't exist, it is **created** as a custom circle with a default color and emoji.
- System circles ("Family", "Friends", "Professional") are matched by name.

---

#### `X-GOLDFISH-COLOR`

| Attribute | Value |
|---|---|
| **Cardinality** | 0 or 1 per vCard |
| **Value type** | TEXT |
| **Format** | Hex color including `#` prefix, 6 digits |
| **Example** | `X-GOLDFISH-COLOR:#FF6B6B` |

**Rules:**
- Must match regex `^#[0-9A-Fa-f]{6}$`.
- Invalid values are silently ignored on import (contact uses default color derivation from name hash).

---

#### `X-GOLDFISH-IS-ME`

| Attribute | Value |
|---|---|
| **Cardinality** | 0 or 1 per vCard |
| **Value type** | TEXT |
| **Valid values** | `true` |
| **Default** | Absent (treated as `false`) |
| **Example** | `X-GOLDFISH-IS-ME:true` |

**Rules:**
- At most one vCard in an export bundle should have this field set to `true`.
- On import, if an `isMe` contact already exists in the database, the imported `isMe` card is **demoted to a regular contact** — the local `isMe` is never overwritten. A merge dialog may offer to update the existing `isMe` contact's fields.

---

#### `X-GOLDFISH-RELATED-TO`

| Attribute | Value |
|---|---|
| **Cardinality** | 0..N per vCard (repeatable) |
| **Value type** | TEXT |
| **Format** | `<UUID>;<relationship-type>` |
| **Example** | `X-GOLDFISH-RELATED-TO:550e8400-e29b-41d4-a716-446655440000;mother` |

**Rules:**
- The UUID references another contact's `UID` field within the **same export bundle**. It is not a reference to the recipient's local database.
- On import, Goldfish resolves UUIDs by matching them to `UID` fields of other contacts in the same `.vcf` file. If the referenced UUID is not present (e.g., the contact was exported individually), the relationship is silently dropped.
- The relationship type follows the same directionality contract as `RelationshipType`: the vCard containing `X-GOLDFISH-RELATED-TO:<UUID>;mother` means "this contact IS the mother OF the contact with the given UUID."
- Duplicate relationships (same pair + same type) are deduplicated on import.

---

### 3.2 Example vCard Output

The following shows a complete vCard 3.0 export of two contacts (a mother and child) with all Goldfish extensions:

```vcf
BEGIN:VCARD
VERSION:3.0
UID:550e8400-e29b-41d4-a716-446655440000
FN:Anna Schmidt
N:Schmidt;Anna;;;
TEL;TYPE=CELL:+49 176 12345678
EMAIL;TYPE=INTERNET:anna.schmidt@example.com
BDAY:1985-03-15
ADR;TYPE=HOME:;;Musterstraße 42;Berlin;;10115;Germany
NOTE:Loves hiking and baking. Met at the Kita parents' evening.
PHOTO;ENCODING=b;TYPE=JPEG:/9j/4AAQSkZJRgABAQ...
X-GOLDFISH-TAGS:kita,neighbor,hiking
X-GOLDFISH-FAVORITE:true
X-GOLDFISH-CIRCLE:Family
X-GOLDFISH-CIRCLE:Kita Parents
X-GOLDFISH-COLOR:#FF6B6B
X-GOLDFISH-IS-ME:false
X-GOLDFISH-RELATED-TO:7c9e6679-7425-40de-944b-e07fc1f90ae7;mother
END:VCARD
BEGIN:VCARD
VERSION:3.0
UID:7c9e6679-7425-40de-944b-e07fc1f90ae7
FN:Luca Schmidt
N:Schmidt;Luca;;;
BDAY:2019-07-22
NOTE:Anna's son. Plays in the garden group at Kita.
X-GOLDFISH-TAGS:kita-kid
X-GOLDFISH-FAVORITE:false
X-GOLDFISH-CIRCLE:Family
X-GOLDFISH-COLOR:#4ECDC4
X-GOLDFISH-RELATED-TO:550e8400-e29b-41d4-a716-446655440000;child
END:VCARD
```

**Reading this example:**
- Anna's vCard says `X-GOLDFISH-RELATED-TO:7c9e6679...;mother` → "Anna IS Luca's mother."
- Luca's vCard says `X-GOLDFISH-RELATED-TO:550e8400...;child` → "Luca IS Anna's child."
- Both entries encode the same relationship from opposite perspectives. On import, Goldfish creates a single `Relationship(from: Anna, to: Luca, type: .mother)` and deduplicates the inverse.

---

### 3.3 Parser Implementation Notes

```swift
struct VCardGoldfishParser {
    
    /// Parse X-GOLDFISH-* fields from a vCard property line
    static func parseExtension(_ line: String) -> (key: String, value: String)? {
        guard line.hasPrefix("X-GOLDFISH-") else { return nil }
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (key: String(parts[0]), value: String(parts[1]))
    }
    
    /// Parse X-GOLDFISH-RELATED-TO value
    static func parseRelatedTo(_ value: String) -> (uuid: UUID, type: RelationshipType)? {
        let parts = value.split(separator: ";", maxSplits: 1)
        guard parts.count == 2,
              let uuid = UUID(uuidString: String(parts[0])),
              let type = RelationshipType(rawValue: String(parts[1]))
        else { return nil }
        return (uuid: uuid, type: type)
    }
    
    /// Parse X-GOLDFISH-TAGS value
    static func parseTags(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: "\\,", with: ",") }
            .filter { !$0.isEmpty }
    }
}
```

---

## 4. Photo Pipeline

### 4.1 Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                    Source Selection                    │
│  ┌──────────────────┐    ┌─────────────────────────┐ │
│  │  PHPicker         │    │  Camera                 │ │
│  │  (Photo Library)  │    │  (AVCaptureDevice)      │ │
│  │  No permission    │    │  NSCameraUsageDescription│ │
│  └────────┬─────────┘    └────────┬────────────────┘ │
│           │                       │                   │
│           └───────────┬───────────┘                   │
│                       ▼                               │
│              ┌────────────────┐                       │
│              │  Crop View     │                       │
│              │  Circular mask │                       │
│              └───────┬────────┘                       │
│                      ▼                                │
│              ┌────────────────┐                       │
│              │  Resize        │                       │
│              │  ≤ 800×800px   │                       │
│              └───────┬────────┘                       │
│                      ▼                                │
│              ┌────────────────┐                       │
│              │  Compress      │                       │
│              │  JPEG q=0.7   │                       │
│              │  Target <500KB │                       │
│              └───────┬────────┘                       │
│                      ▼                                │
│              ┌────────────────┐                       │
│              │  Store         │                       │
│              │  SwiftData     │                       │
│              │  @Attribute    │                       │
│              │  (.external    │                       │
│              │   Storage)     │                       │
│              └────────────────┘                       │
└──────────────────────────────────────────────────────┘
```

---

### 4.2 Source: PHPicker (Photo Library)

**Presentation:**
```swift
struct PhotoPickerView: UIViewControllerRepresentable {
    var configuration: PHPickerConfiguration {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        return config
    }
}
```

**Key points:**
- No permission required (privacy-preserving picker).
- Results delivered via `PHPickerViewControllerDelegate`.
- Load the selected item as `UIImage` via `NSItemProvider.loadObject(ofClass: UIImage.self)`.
- Handle `NSItemProvider` errors gracefully — if loading fails, show a brief toast: "Couldn't load that photo. Try another one."

---

### 4.3 Source: Camera

**Presentation:**
```swift
struct CameraPickerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front     // Default to front camera for portraits
        picker.allowsEditing = true       // Built-in square crop
        return picker
    }
}
```

**Pre-conditions:**
- Check `UIImagePickerController.isSourceTypeAvailable(.camera)` — returns `false` on simulator and devices without cameras.
- Check `AVCaptureDevice.authorizationStatus(for: .video)` — if `.denied`, don't present the camera option.

---

### 4.4 Crop

**Approach: Custom `CircularCropView`**

Use a custom SwiftUI crop overlay rather than `UIImagePickerController.allowsEditing` for these reasons:
- `allowsEditing` provides a square crop (not circular).
- The square crop is acceptable functionally (the circle mask is applied at display time), but a circular overlay gives a better UX preview.

**Specification:**

| Attribute | Value |
|---|---|
| Overlay shape | Circle, centered in the view |
| Circle diameter | `min(imageWidth, imageHeight) * 0.85` |
| Outside mask | Black at 60% opacity |
| Gestures | Pinch to zoom, drag to pan the image behind the mask |
| Minimum zoom | 1.0× (image fills the circle) |
| Maximum zoom | 4.0× |
| Output | Square `CGImage` cropped to the circle's bounding box |

**Fallback:** If the custom crop view is not ready for v1, use `UIImagePickerController.allowsEditing = true` (square crop). The circular display mask at render time makes the square crop invisible to the user.

---

### 4.5 Resize

```swift
extension UIImage {
    /// Resize to fit within maxDimension, preserving aspect ratio.
    func resizedToFit(maxDimension: CGFloat = 800) -> UIImage {
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        guard ratio < 1.0 else { return self } // Already within bounds
        
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

**Rules:**
- Maximum output dimension: **800×800px** (either axis).
- If the image is already ≤800px on both axes, no resize occurs.
- Aspect ratio is always preserved — no stretching, no distortion.
- Use `UIGraphicsImageRenderer` (not `UIGraphicsBeginImageContext`) for automatic scale-factor handling.

---

### 4.6 Compress

```swift
extension UIImage {
    /// Compress to JPEG within the target byte budget.
    func compressedJPEG(maxBytes: Int = 500_000, initialQuality: CGFloat = 0.7) -> Data? {
        var quality = initialQuality
        
        while quality > 0.1 {
            guard let data = jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        
        // Last resort: lowest quality
        return jpegData(compressionQuality: 0.1)
    }
}
```

**Rules:**

| Parameter | Value |
|---|---|
| Format | JPEG (not PNG, HEIF, or WebP) |
| Initial quality | 0.7 (70%) |
| Target max size | 500 KB (512,000 bytes) |
| Quality reduction step | 0.1 per iteration |
| Minimum quality floor | 0.1 (10%) |
| Typical output size | 80–250 KB for an 800×800 photo at q=0.7 |

**Why JPEG:**
- Universally supported across all platforms (vCard `PHOTO` field compatibility).
- SwiftData + CloudKit Assets handle `Data` blobs; JPEG is the most compact raster format for photos.
- HEIF would be smaller but isn't universally decodable outside Apple platforms.

---

### 4.7 Storage

```swift
// In Person model
@Attribute(.externalStorage)
var photoData: Data?
```

**Behavior of `@Attribute(.externalStorage)`:**
- SwiftData stores the blob as a **sidecar file** on disk, not inline in the SQLite database.
- The database row contains only a reference (file path) to the sidecar.
- On iCloud sync, the sidecar is uploaded as a **CloudKit Asset** (CKAsset), which:
  - Is lazily downloaded on other devices (not eagerly synced).
  - Doesn't count against the 1 MB CloudKit record size limit.
  - Is automatically purged from CloudKit when the owning record is deleted.
- This is critical for performance: list views that fetch `Person` objects don't load photo blobs into memory unless `photoData` is explicitly accessed.

---

### 4.8 Display

**Primary display component:**

```swift
struct ContactPhotoView: View {
    let person: Person
    let size: CGFloat
    
    var body: some View {
        Group {
            if let data = person.photoData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Initials fallback
                Circle()
                    .fill(Color(hex: person.color ?? defaultColor))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(person.initials)
                            .font(.system(
                                size: size * 0.38, 
                                weight: .semibold, 
                                design: .rounded
                            ))
                            .foregroundStyle(.white)
                    }
            }
        }
        .accessibilityLabel(
            person.photoData != nil  
                ? "\(person.name)'s photo" 
                : "\(person.name)'s initials, \(person.initials)"
        )
    }
    
    private var defaultColor: String {
        let hue = abs(person.name.hashValue % 360)
        // Convert to hex — saturation 0.4, brightness 0.85
        return hueToHex(hue: Double(hue) / 360.0, saturation: 0.4, brightness: 0.85)
    }
}
```

**Display sizes across the app:**

| Context | Diameter | Notes |
|---|---|---|
| Graph node (compact) | 44pt | With 1pt selection ring space |
| Graph node (regular) | 56pt | For focused/nearby nodes |
| List row | 40pt | Leading position |
| Contact detail header | 100pt | Centered at top |
| Edit form | 100pt | Tappable to change photo |
| Relationship row | 32pt | Inline mini avatar |
| Onboarding "Me" card | 100pt | Centered |
| Share preview | 44pt | In share sheet |

---

### 4.9 Deletion

**Flow:**
1. User taps the photo in the Edit Contact form.
2. Action sheet presents: "Choose from Library" / "Take Photo" / **"Remove Photo"** / "Cancel".
3. "Remove Photo" sets `person.photoData = nil` and saves the context.
4. The `ContactPhotoView` automatically falls back to initials display.
5. The sidecar file is cleaned up by SwiftData's storage manager on the next save.
6. On iCloud sync, the CloudKit Asset is removed from the server.

**No confirmation dialog** for photo deletion — it's easily reversible by adding a new photo.

---

### 4.10 End-to-End Pipeline Summary

```
Source Selection
     │
     ├── PHPickerViewController (library) — no permission needed
     │   └── NSItemProvider.loadObject(ofClass: UIImage.self)
     │
     └── UIImagePickerController(.camera) — NSCameraUsageDescription
         └── delegate.imagePickerController(_:didFinishPickingMediaWithInfo:)
              │
              ▼
       Raw UIImage (potentially 4032×3024 @ 12MP)
              │
              ▼
       CircularCropView (or allowsEditing square crop)
              │
              ▼
       Cropped UIImage (square, variable size)
              │
              ▼
       resizedToFit(maxDimension: 800)
              │
              ▼
       UIImage ≤ 800×800px
              │
              ▼
       compressedJPEG(maxBytes: 500_000, initialQuality: 0.7)
              │
              ▼
       Data (JPEG, ≤ 500KB)
              │
              ▼
       person.photoData = data
       modelContext.save()
              │
              ▼
       SwiftData writes sidecar file
       CloudKit syncs as CKAsset (lazy)
```

---

## 5. Privacy Nutrition Label

### 5.1 Data Inventory

Before filling the label, every data point the app handles must be classified:

| Data Point | Stored Where | Transmitted? | Purpose |
|---|---|---|---|
| Contact name | SwiftData (on-device) + iCloud sync | No | App functionality |
| Phone number | SwiftData + iCloud sync | No | App functionality |
| Email address | SwiftData + iCloud sync | No | App functionality |
| Birthday | SwiftData + iCloud sync | No | App functionality |
| Notes | SwiftData + iCloud sync | No | App functionality |
| Tags | SwiftData + iCloud sync | No | App functionality |
| Contact photo | SwiftData sidecar + iCloud Asset | No | App functionality |
| Relationship data | SwiftData + iCloud sync | No | App functionality |
| Circle membership | SwiftData + iCloud sync | No | App functionality |
| Address fields | SwiftData + iCloud sync | No | App functionality |
| User's location | **Memory only** (CLLocation?) | **Never** | Proximity filter |
| Contact coordinates | SwiftData + iCloud sync | No | Map display |
| Node color | SwiftData + iCloud sync | No | UI customization |
| App preferences | @AppStorage (UserDefaults) | No | App functionality |
| Onboarding state | @AppStorage | No | App functionality |

---

### 5.2 Privacy Nutrition Label — Full Matrix

| Apple Category | Sub-category | Data collected? | Linked to user identity? | Used for tracking? |
|---|---|---|---|---|
| **Contact Info** | Name | ❌ Not collected | N/A | N/A |
| **Contact Info** | Email Address | ❌ Not collected | N/A | N/A |
| **Contact Info** | Phone Number | ❌ Not collected | N/A | N/A |
| **Contact Info** | Physical Address | ❌ Not collected | N/A | N/A |
| **Contacts** | Contacts | ❌ Not collected | N/A | N/A |
| **Health & Fitness** | — | ❌ Not collected | N/A | N/A |
| **Financial Info** | — | ❌ Not collected | N/A | N/A |
| **Location** | Precise Location | ❌ Not collected | N/A | N/A |
| **Location** | Coarse Location | ❌ Not collected | N/A | N/A |
| **Sensitive Info** | — | ❌ Not collected | N/A | N/A |
| **User Content** | Photos or Videos | ❌ Not collected | N/A | N/A |
| **User Content** | Other User Content | ❌ Not collected | N/A | N/A |
| **Browsing History** | — | ❌ Not collected | N/A | N/A |
| **Search History** | — | ❌ Not collected | N/A | N/A |
| **Identifiers** | User ID | ❌ Not collected | N/A | N/A |
| **Identifiers** | Device ID | ❌ Not collected | N/A | N/A |
| **Usage Data** | — | ❌ Not collected | N/A | N/A |
| **Diagnostics** | Crash Data | ❌ Not collected | N/A | N/A |
| **Diagnostics** | Performance Data | ❌ Not collected | N/A | N/A |

### **Final Declaration: ✅ "Data Not Collected"**

---

### 5.3 Row-by-Row Justification

#### Contact Info (Name, Email, Phone, Address)

**Justification:** While the app stores contact information on the device, Apple's definition of "collected" means "transmitted off the device to the developer or a third party." Goldfish stores all contact data locally in a SwiftData database on the user's device. No data is sent to any server, API, analytics service, or third party. Therefore: **Not collected.**

#### Contacts

**Justification:** The app accesses the device address book (via `CNContactStore`) for the import feature. However, imported contacts are copied into the app's private SwiftData store — no address book data is transmitted off-device. Apple's guidance in [App Store Connect Help](https://developer.apple.com/app-store/app-privacy-details/) specifies that on-device-only access does not constitute "collection." Therefore: **Not collected.**

#### Location

**Justification:** The app requests When In Use location access for the proximity filter. However:
- The user's coordinates are held **in memory only** as a transient `CLLocation?` property.
- Coordinates are **never written** to SwiftData, UserDefaults, files, or any persistent storage.
- Coordinates are **never transmitted** off-device.
- The proximity filter computes distances locally and discards the location when the filter is deactivated.

Per Apple's guidance: location data used only for on-device computation and never transmitted is **not collected.**

#### Photos

**Justification:** The app stores contact photos as JPEG data in SwiftData with `@Attribute(.externalStorage)`. Photos are:
- Stored only on the user's device and in their personal iCloud account (via CloudKit sync).
- Never transmitted to the developer, any server, or any third party.
- Never used for analytics, advertising, or any purpose other than displaying the contact's profile picture.

Therefore: **Not collected.**

#### User Content (Notes, Tags)

**Justification:** Free-form notes and tags are stored locally in SwiftData and synced to the user's personal iCloud. No developer or third-party access. **Not collected.**

#### Diagnostics

**Justification:** Goldfish does not integrate any crash reporting SDK (Crashlytics, Sentry, Bugsnag, etc.). The app uses `os_log` for local debug logging only — these logs are accessible only on-device via Console.app and are never transmitted. Apple's own crash reports (via TestFlight/App Store) are separate and not declared in the developer's privacy label. **Not collected.**

---

### 5.4 Edge Case: iCloud Sync

> **Q: Does iCloud sync count as "data collection"?**
>
> **A: No.** Apple explicitly addresses this in the [App Privacy Details documentation](https://developer.apple.com/app-store/app-privacy-details/):
>
> > *"Data that is only stored on the user's device, or data that is synced across devices using end-to-end encryption, does not need to be disclosed."*
>
> CloudKit private database sync (used by SwiftData with iCloud) qualifies because:
> 1. Data is stored in the user's **private CloudKit container** — only the user's Apple ID can access it.
> 2. The developer (Goldfish) has **no access** to the private database contents via the CloudKit Dashboard or any API.
> 3. The sync exists solely for the user's benefit (multi-device access).
>
> Therefore, iCloud sync does not change the "Data Not Collected" declaration.

---

### 5.5 Edge Case: vCard Export/Share

> **Q: When the user shares a .vcf file via the share sheet, does that count as "data collection"?**
>
> **A: No.** The share action is:
> 1. **User-initiated** — the user explicitly chooses to share and selects the recipient.
> 2. **User-directed** — the data goes where the user sends it (AirDrop, Messages, etc.), not to the developer.
> 3. Apple's definition of "collection" refers to data being sent **to the developer or third parties for the developer's purposes**, not user-initiated sharing.
>
> Analogy: The Files app doesn't declare "Collected" for every file type just because users can share files from it.

---

### 5.6 Privacy Manifest (`PrivacyInfo.xcprivacy`)

Starting 2024, Apple requires a Privacy Manifest file for App Store submission. Goldfish's manifest:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Privacy Nutrition Label Types -->
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <!-- Empty array = "Data Not Collected" -->
    
    <!-- Privacy Tracking -->
    <key>NSPrivacyTracking</key>
    <false/>
    
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <!-- No tracking domains -->
    
    <!-- Required Reason APIs -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
                <!-- Reason: Access UserDefaults to read/write 
                     app preferences (view mode, sort order, 
                     onboarding state). -->
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
                <!-- Reason: Access file timestamps for SwiftData 
                     sidecar file management. -->
            </array>
        </dict>
    </array>
</dict>
</plist>
```

> [!CAUTION]
> The Privacy Manifest must be bundled in the app target, not a framework. Verify it appears in the app archive by running: `unzip -l MyApp.ipa | grep PrivacyInfo`.

---

## Appendix A: Complete Info.plist Additions

All platform integration entries that must be added to `Info.plist`:

```xml
<!-- Permissions -->
<key>NSContactsUsageDescription</key>
<string>Goldfish imports names and phone numbers from your address book so you can build your relationship map. Your contacts stay on your device and are never sent to a server.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Goldfish uses your location to show which of your contacts are nearby. Your location is never stored, shared, or sent anywhere.</string>

<key>NSCameraUsageDescription</key>
<string>Goldfish uses your camera to take a photo for this contact. Photos are stored on your device and never uploaded.</string>

<!-- Document Types (vCard import) -->
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>vCard</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.vcard</string>
        </array>
    </dict>
</array>

<!-- Exported UTTypes (optional, for .goldfish bundle) -->
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.content</string>
        </array>
        <key>UTTypeDescription</key>
        <string>Goldfish Contact Bundle</string>
        <key>UTTypeIdentifier</key>
        <string>com.goldfish.export</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>goldfish</string>
            </array>
            <key>public.mime-type</key>
            <string>application/x-goldfish-export</string>
        </dict>
    </dict>
</array>
```

---

## Appendix B: Permission Request Timing Diagram

```
App Launch
    │
    ├── Onboarding (first launch only)
    │     │
    │     └── Screen 4: "Import from Contacts"
    │           │
    │           └── [User taps "Allow Access"]
    │                 └── CNContactStore.requestAccess ← CONTACTS PROMPT
    │
    ├── Normal Use
    │     │
    │     ├── User taps photo placeholder → "Take Photo"
    │     │     └── AVCaptureDevice.requestAccess ← CAMERA PROMPT (one-time)
    │     │
    │     ├── User taps photo placeholder → "Choose from Library"
    │     │     └── PHPickerViewController ← NO PROMPT (privacy-preserving)
    │     │
    │     └── User activates "Nearby" filter or opens map
    │           └── CLLocationManager.requestWhenInUseAuthorization ← LOCATION PROMPT (one-time)
    │
    └── Settings
          │
          └── User taps "Import Contacts" (deferred)
                └── CNContactStore.requestAccess ← CONTACTS PROMPT (if not already authorized)
```
