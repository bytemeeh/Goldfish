# Goldfish — App Store Submission Package

> **Bundle ID:** `com.goldfish.app` *(update to match your actual bundle ID)*  
> **Platform:** iOS 17.0+  
> **Version:** 1.0 (Build 1)  
> **Last updated:** 2026-02-15

---

## Table of Contents

1. [App Store Metadata](#1-app-store-metadata)
2. [Screenshot Specification](#2-screenshot-specification)
3. [App Review Risk Assessment](#3-app-review-risk-assessment)
4. [Submission Checklist](#4-submission-checklist)
5. [Privacy Policy](#5-privacy-policy)
6. [Support Page](#6-support-page)

---

## 1. App Store Metadata

### 1.1 App Name (max 30 chars)

| Option | Characters | Notes |
|---|---|---|
| **Goldfish – Relationship Map** | 28 | ✅ Recommended. Clear value prop, includes keyword. |
| **Goldfish – People & Circles** | 29 | Alternative. Highlights the circles feature. |
| **Goldfish** | 8 | Minimalist. Relies on subtitle to explain. |

### 1.2 Subtitle (max 30 chars)

| Option | Characters | Notes |
|---|---|---|
| **Your Personal Network Map** | 26 | ✅ Recommended. Clear, benefit-oriented. |
| **Visual Relationship Manager** | 30 | More descriptive, uses full char limit. |
| **Map Your People** | 15 | Short, punchy, action-oriented. |

### 1.3 Keywords (max 100 chars, comma-separated)

```
contacts,relationship,network,CRM,circle,family,friends,graph,people,organizer,personal,vcard,map
```

**Character count:** 97  
**Rationale:** Front-loads high-volume terms (`contacts`, `relationship`, `network`, `CRM`). Includes long-tail terms (`vcard`, `graph`). Avoids duplicating words already in the app name or subtitle (`goldfish`, `personal`, `your`). Apple de-duplicates singular/plural automatically.

### 1.4 Categories

| | Category | Justification |
|---|---|---|
| **Primary** | **Productivity** | Personal CRM / relationship management is a productivity tool. Highest conversion category for organizer apps. |
| **Secondary** | **Social Networking** | The app maps social connections and relationships. Provides discoverability alongside social apps. |

### 1.5 Age Rating Questionnaire

| Question | Answer | Justification |
|---|---|---|
| Cartoon or Fantasy Violence | None | No violence of any kind. |
| Realistic Violence | None | No violence of any kind. |
| Sexual Content & Nudity | None | No sexual content. |
| Profanity or Crude Humor | None | No profanity. |
| Mature/Suggestive Themes | None | No mature themes. |
| Horror/Fear Themes | None | No horror content. |
| Medical/Treatment Information | None | No medical content. |
| Alcohol, Tobacco, Drug Use or References | None | No substance references. |
| Simulated Gambling | None | No gambling. |
| Frequent/Intense Mature Content | None | No mature content. |
| Unrestricted Web Access | No | App does not contain a web browser. |
| Gambling with Real Currency | No | No gambling features. |
| Contests | No | No contests. |

**Resulting Age Rating: 4+**

### 1.6 Full Description (max 4000 chars)

```
Goldfish is your personal relationship map — a beautiful, 
private way to organize and visualize the people in your life.

Unlike generic contact apps, Goldfish lets you see your network 
as an interactive graph. Arrange people in circles — Family, 
Friends, Professional, or your own custom groups — and map 
the connections between them. See at a glance how your people 
are related, who belongs where, and never lose track of the 
relationships that matter.

━━━━━━━━━━━━━━━━━━━━━━━
WHY GOLDFISH?
━━━━━━━━━━━━━━━━━━━━━━━

◆ VISUAL NETWORK MAP
See your entire personal network as an interactive, 
force-directed graph. Nodes represent people; lines represent 
relationships. Zoom, pan, and explore your network naturally.

◆ CIRCLES
Organize contacts into meaningful groups: Family, Friends, 
Professional, or unlimited custom circles with your own 
colors and emojis. One person can belong to many circles.

◆ RICH RELATIONSHIPS
Define how people are connected: mother, father, sibling, 
spouse, partner, friend, coworker, child — or create 
custom relationship types. See the full web of connections 
at a glance.

◆ COMPLETE CONTACT CARDS
Store names, phone numbers, emails, birthdays, addresses, 
photos, notes, and custom tags for every contact. Tap to 
call, message, or email directly.

◆ IMPORT & EXPORT
Import contacts from your address book with one tap. Export 
individual contacts or entire network segments as standard 
vCard (.vcf) files via AirDrop, Messages, Mail, or any 
sharing method.

◆ MAP VIEW
See where your contacts are located on an interactive map. 
Filter nearby contacts when you're traveling or in a new city.

◆ SEARCH EVERYTHING
Instantly search by name, phone, email, notes, tags, circles, 
or relationship type. Results appear as you type.

━━━━━━━━━━━━━━━━━━━━━━━
100% PRIVATE. ZERO TRACKING.
━━━━━━━━━━━━━━━━━━━━━━━

Goldfish is built from the ground up for privacy:

• All data stays on YOUR device — no servers, no accounts, 
  no cloud you don't control
• iCloud sync keeps your data across your Apple devices, 
  encrypted and accessible only to you
• No analytics, no tracking, no ads, no in-app purchases
• No data is ever sent to us or any third party
• Contact import stays local — we never read your 
  address book in the background

App Store Privacy Label: "Data Not Collected"

━━━━━━━━━━━━━━━━━━━━━━━
DESIGNED FOR iOS
━━━━━━━━━━━━━━━━━━━━━━━

• Native SwiftUI interface with dark mode support
• SpriteKit-powered graph with smooth 60fps animations
• Full VoiceOver and Dynamic Type accessibility
• Respects Reduce Motion preferences
• Works beautifully on iPhone and iPad

Goldfish is the relationship manager you wish your phone 
came with. See your world. Remember your people.
```

**Character count:** ~2,450 (well within 4,000 limit — leaves room for localization expansion)

### 1.7 Promotional Text (max 170 chars)

```
Map your personal network visually. Organize contacts in circles, track relationships, and never forget who matters. 100% private, zero tracking.
```

**Character count:** 148

> **Note:** Promotional text can be updated without a new app version — use it for seasonal messaging, feature highlights, or time-sensitive announcements.

### 1.8 What's New — v1.0

```
Welcome to Goldfish! 🐟

• Visual relationship graph — see your entire network at a glance
• Circles — organize contacts into Family, Friends, Professional, or custom groups
• Rich contact cards with photos, birthdays, notes, and tags
• vCard import and export
• Map view for contact locations
• Full iCloud sync across your devices
• Complete privacy — no tracking, no accounts, no data collection

We'd love to hear from you: support@goldfish-app.com
```

---

## 2. Screenshot Specification

### 2.1 Required Device Sizes

| Device Class | Display Size | Resolution | Required? |
|---|---|---|---|
| iPhone 16 Pro Max | 6.7" | 1320 × 2868 px | ✅ Required |
| iPhone 16 Pro | 6.3" | 1206 × 2622 px | ✅ Required (or use 6.7" scaled) |
| iPhone SE (3rd gen) | 4.7" | 750 × 1334 px | ⚠️ Required only if supporting SE |
| iPad Pro 13" | 12.9" | 2048 × 2732 px | ⚠️ If supporting iPad |

> Apple allows using 6.7" screenshots for 6.1"/6.3" if identical in layout.

### 2.2 Six Screenshots — Ordered by Conversion Importance

| # | Screen | Overlay Text | Rationale |
|---|---|---|---|
| **1** | **Relationship Graph** — Full graph view with 15-20 connected nodes, circles visible, colorful, zoomed to show the full network | **"See your world at a glance"** | First impression. The graph is the hero feature and strongest differentiator. Nothing else on the App Store looks like this. |
| **2** | **Circle Detail** — Family or Friends circle expanded, showing member avatars, relationships, and the circle color theme | **"Organize your people into circles"** | Explains the core organizational concept. Circles are immediately understandable. |
| **3** | **Contact Detail** — A rich contact card with photo, phone, email, birthday, notes, tags, relationships listed, and map | **"Every detail, beautifully organized"** | Shows depth of contact data. Demonstrates this is a full contact manager, not just a graph toy. |
| **4** | **Quick Actions** — Contact detail with call/message/email buttons visible, relationship section populated | **"Stay connected in one tap"** | Demonstrates practical utility — not just visual, but actionable. |
| **5** | **vCard Import** — Import flow showing contacts being added with a progress indicator, or the import completion banner | **"Import your contacts instantly"** | Reduces friction ("I don't have to add everyone manually"). |
| **6** | **Privacy Badge** — Settings screen or a custom frame showing the privacy posture: no tracking, no accounts, local-only, iCloud sync | **"Your data stays yours. Always."** | Privacy is a key purchase driver. Close with trust. |

### 2.3 Screenshot Design Guidelines

| Element | Specification |
|---|---|
| **Background** | Solid gradient matching app accent color, or a subtle blurred version of the screen content |
| **Device frame** | Optional — Apple recommends frameless screenshots for modern listings. If using frames, use iPhone 15 Pro Max frame in Space Black. |
| **Text position** | Top 25% of the screenshot (above the fold on the App Store listing) |
| **Text style** | SF Pro Display Bold, 64pt (6.7") / 56pt (6.1"), white or high-contrast color |
| **Subtitle** | Optional, SF Pro Text Regular, 32pt, 70% opacity white |
| **Screenshot content** | Center vertically in the remaining 75%, with 24pt horizontal padding |
| **Status bar** | Always show a clean status bar: 9:41, full signal, full WiFi, full battery |
| **Content** | Use realistic but fictional German contact data (no real people) — consistent with the Kita seed data |

### 2.4 Dark Mode Variants

**Recommendation:** Capture all 6 screenshots in **dark mode**. Reasons:

1. Dark mode screenshots have higher tap-through rates on the App Store (the listing page itself uses a light background — dark screenshots "pop" visually).
2. The colorful graph nodes and circle colors look more vibrant against a dark background.
3. If you want light mode variants, create them as an additional screenshot set for localization — not a replacement.

---

## 3. App Review Risk Assessment

### 3.1 Guideline 4.2 — Minimum Functionality

| | |
|---|---|
| **Risk Level** | 🟡 **Medium** |
| **Concern** | Apple may view a "personal CRM" as duplicating the built-in Contacts app. Rejection rationale: *"Your app duplicates functionality already available in the built-in iOS apps."* |
| **Mitigation** | ① The interactive force-directed graph visualization is a unique feature with no Contacts.app equivalent. All screenshots should highlight this. ② The circles/grouping system, relationship mapping, and graph exploration provide functionality substantially beyond the built-in Contacts app. ③ In App Review Notes, write: *"Goldfish is a personal relationship manager that complements the built-in Contacts app. Its core differentiator is the interactive network graph that visualizes how contacts are connected through relationship types and custom circles — functionality not available in iOS Contacts or any built-in app."* |

### 3.2 Guideline 5.1 — Privacy

| | |
|---|---|
| **Risk Level** | 🟢 **Low** |
| **Concern** | Contact access + location access could raise questions about data handling. |
| **Mitigation** | ① Privacy nutrition label declares "Data Not Collected." ② Info.plist usage descriptions clearly state data stays on-device. ③ Privacy manifest (`PrivacyInfo.xcprivacy`) is included and accurate. ④ Privacy policy URL is provided and hosted. ⑤ No third-party SDKs that collect data. ⑥ No network calls to any server (verifiable via `nslookup` during review). |

### 3.3 Guideline 5.1.1 — Data Collection and Storage

| | |
|---|---|
| **Risk Level** | 🟢 **Low** |
| **Concern** | App accesses contacts and stores them locally. |
| **Mitigation** | ① Contact import is user-initiated only (never background-read). ② `NSContactsUsageDescription` explains purpose clearly. ③ Imported data is stored only in on-device SwiftData. ④ iCloud sync uses private CloudKit container — developer has no access. |

### 3.4 Guideline 2.1 — App Completeness

| | |
|---|---|
| **Risk Level** | 🟡 **Medium** |
| **Concern** | If the app ships with only the "Me" node and no contacts, the reviewer may see an empty app with no content. |
| **Mitigation** | ① Provide a demo account / test notes in App Review Notes explaining how to import contacts from the test device's address book. ② Ensure the review device has sample contacts pre-loaded, or provide a test `.vcf` file URL for the reviewer to import. ③ All empty states have proper placeholder UI (§4 of UI spec) — no blank screens. ④ The onboarding flow guides the reviewer through creating their card and importing contacts. |

### 3.5 Guideline 4.0 — Design

| | |
|---|---|
| **Risk Level** | 🟢 **Low** |
| **Concern** | App must meet Apple's design quality bar. |
| **Mitigation** | ① Native SwiftUI with standard navigation patterns. ② Supports Dynamic Type, VoiceOver, and Reduce Motion. ③ Dark mode fully supported. ④ No web views or cross-platform UI toolkits — 100% native. |

### 3.6 Guideline 2.5.1 — Software Requirements

| | |
|---|---|
| **Risk Level** | 🟢 **Low** |
| **Concern** | App must use public APIs only. |
| **Mitigation** | ① All frameworks are public: SwiftUI, SwiftData, SpriteKit, MapKit, Contacts, CoreLocation, PhotosUI, AVFoundation. ② No private API usage. ③ No deprecated APIs that would trigger warnings. ④ Run `nm` or `otool` scan on the binary before submission to verify no private symbols. |

### 3.7 Guideline 2.3 — Accurate Metadata

| | |
|---|---|
| **Risk Level** | 🟢 **Low** |
| **Concern** | Screenshots and description must accurately represent the app. |
| **Mitigation** | ① All screenshots show actual app screens (no mockups or renders of features that don't exist). ② Description only references implemented features. ③ No mention of "AI", "machine learning", or other buzzwords the app doesn't use. |

### 3.8 Guideline 3.1.1 — In-App Purchase

| | |
|---|---|
| **Risk Level** | 🟢 **Low (N/A)** |
| **Concern** | None — the app has no in-app purchases, subscriptions, or monetization. |
| **Mitigation** | Declare "No" to in-app purchases in App Store Connect. Ensure no code references StoreKit or payment flows. |

### 3.9 Guideline 5.1.2 — Data Use and Sharing

| | |
|---|---|
| **Risk Level** | 🟢 **Low** |
| **Concern** | vCard export shares contact data. |
| **Mitigation** | ① Export is user-initiated via `UIActivityViewController` (native share sheet). ② The user chooses recipient and method. ③ No data is shared without explicit user action. ④ No background data sharing or sync to developer servers. |

### Risk Summary

| Guideline | Risk | Action Required |
|---|---|---|
| 4.2 Minimum Functionality | 🟡 Medium | Strong App Review Notes emphasizing graph differentiator |
| 2.1 App Completeness | 🟡 Medium | Provide test .vcf file and review instructions |
| 5.1 Privacy | 🟢 Low | Privacy manifest + policy URL in place |
| 5.1.1 Data Collection | 🟢 Low | All mitigations already in architecture |
| 4.0 Design | 🟢 Low | Native SwiftUI, full accessibility |
| 2.5.1 Software Requirements | 🟢 Low | Public APIs only |
| 2.3 Accurate Metadata | 🟢 Low | Screenshots match actual app |
| 3.1.1 IAP | 🟢 N/A | No monetization |
| 5.1.2 Data Sharing | 🟢 Low | User-initiated export only |

---

## 4. Submission Checklist

### 4.1 Technical Requirements

- [ ] **App Icon** — 1024×1024 px PNG, no alpha, no rounded corners (system applies mask). Included in `Assets.xcassets/AppIcon.appiconset`.
- [ ] **Launch Screen** — `LaunchScreen.storyboard` or SwiftUI launch screen configured in Info.plist. No placeholder text or loading spinners.
- [ ] **Bundle Identifier** — Registered in Apple Developer portal, matches Xcode project.
- [ ] **Version & Build** — Version string `1.0`, Build number `1` (or auto-incrementing).
- [ ] **Minimum Deployment Target** — iOS 17.0 set in Xcode project settings.
- [ ] **Device Support** — iPhone selected. iPad optional (verify layout if included).
- [ ] **Entitlements** — `iCloud` (CloudKit) entitlement enabled. `com.apple.developer.icloud-container-identifiers` set.
- [ ] **Capabilities** — Push Notifications OFF (not used). Background Modes OFF (not used).
- [ ] **PrivacyInfo.xcprivacy** — Privacy manifest bundled in app target (not a framework). Declares `UserDefaults` (CA92.1) and `FileTimestamp` (C617.1) API reasons.
- [ ] **Info.plist** — All permission strings present:
  - `NSContactsUsageDescription` ✓
  - `NSLocationWhenInUseUsageDescription` ✓
  - `NSCameraUsageDescription` ✓
  - No `NSPhotoLibraryUsageDescription` (PHPicker doesn't need it) ✓
  - No `NSLocationAlwaysUsageDescription` ✓
- [ ] **Architectures** — Build for `arm64` only (no simulator slices in archive).
- [ ] **Bitcode** — N/A (deprecated since Xcode 14).

### 4.2 Legal Requirements

- [ ] **Privacy Policy URL** — Hosted at a publicly accessible URL (e.g., `https://goldfish-app.com/privacy`). Entered in App Store Connect under App Information.
- [ ] **Support URL** — Hosted publicly (e.g., `https://goldfish-app.com/support`). Entered in App Store Connect.
- [ ] **License Agreement** — Use Apple's Standard EULA (default). No custom EULA needed.
- [ ] **Copyright** — e.g., `© 2026 [Your Name or Company]`. Entered in App Store Connect.
- [ ] **Privacy Nutrition Label** — Completed in App Store Connect: select **"Data Not Collected"** for all categories.
- [ ] **Encryption Declaration** — App uses HTTPS (CloudKit) which is exempt. Select: *"Yes, but only Apple's standard encryption (HTTPS/TLS)"* → exempt from ERN filing.

### 4.3 Content Requirements

- [ ] **Screenshots** — Minimum 3, recommended 6. Uploaded for 6.7" and 6.1" (or 6.7" only — Apple auto-scales).
- [ ] **App Name** — ≤ 30 characters, entered.
- [ ] **Subtitle** — ≤ 30 characters, entered.
- [ ] **Keywords** — ≤ 100 characters, comma-separated, entered.
- [ ] **Categories** — Primary: Productivity. Secondary: Social Networking.
- [ ] **Full Description** — ≤ 4,000 characters, entered.
- [ ] **Promotional Text** — ≤ 170 characters, entered.
- [ ] **What's New** — Entered for version 1.0.
- [ ] **Age Rating** — Questionnaire completed, result: 4+.
- [ ] **App Preview Video** — Optional. 15-30 second video showing graph interaction. Recommended but not required for v1.
- [ ] **App Review Notes** — Written (see §3.1 and §3.4 for recommended content). Include: how to test, any demo data instructions, and a link to a test `.vcf` file if the review device has no contacts.

### 4.4 Binary Requirements

- [ ] **No Private APIs** — Verified via `nm` / `otool` scan. No `_UIPrivate*`, no `_NS*Internal*` symbols.
- [ ] **No Placeholder Content** — All empty states show proper UI. No "TODO", "Lorem ipsum", or test data in the shipped binary. Grep the codebase: `grep -rn "TODO\|FIXME\|lorem\|placeholder\|test data" Sources/`.
- [ ] **No Hardcoded Test URLs** — No `localhost`, `127.0.0.1`, `staging`, or test server references.
- [ ] **No Unused Permissions** — Every Info.plist usage description key corresponds to code that actually uses that permission.
- [ ] **No Crash on Launch** — Test on a clean iOS 17 device with no iCloud account, no contacts, full disk, and airplane mode.
- [ ] **No Third-Party SDK Issues** — Verify no embedded SDKs with their own privacy manifests that conflict.
- [ ] **Archive Build Succeeds** — `Product > Archive` in Xcode completes without warnings.
- [ ] **Organizer Validation Passes** — Run `Validate App` in Xcode Organizer before distributing. Catches entitlement, icon, and signing issues.
- [ ] **TestFlight Build Uploaded** — Upload via Xcode Organizer or `xcrun altool`. TestFlight processing completes without errors.

### 4.5 Pre-Submit Smoke Test

- [ ] Fresh install on physical device (not simulator)
- [ ] Complete onboarding flow end-to-end
- [ ] Import contacts from address book
- [ ] Create a contact manually with photo
- [ ] Create relationships between contacts
- [ ] Verify graph renders with nodes and edges
- [ ] Verify circles display and filter correctly
- [ ] Export a contact as vCard and verify import
- [ ] Test with VoiceOver enabled
- [ ] Test with Dynamic Type at largest size
- [ ] Test with Reduce Motion enabled
- [ ] Test in dark mode and light mode
- [ ] Test on airplane mode (no iCloud — should still work)
- [ ] Verify delete contact with cascade
- [ ] Force-quit and relaunch — verify state restoration

---

## 5. Privacy Policy

> **Host this at your privacy policy URL** (e.g., `https://goldfish-app.com/privacy`).

---

### Privacy Policy for Goldfish

**Last updated: February 15, 2026**

Goldfish ("the App") is a personal relationship manager for iOS developed by [Your Name / Company Name] ("we", "us", "our"). This privacy policy describes how the App handles your information.

#### What Data Is Stored

Goldfish stores the following data that you create within the app:

- Contact information (names, phone numbers, email addresses, birthdays, notes, tags, addresses)
- Contact photos
- Relationship connections between contacts
- Circle (group) memberships
- Your app preferences (view mode, sort order)

All of this data is stored **exclusively on your device** in a local database. Nothing is stored on our servers — we do not operate any servers.

#### iCloud Sync

If you have iCloud enabled on your device, Goldfish syncs your data across your Apple devices using Apple's CloudKit private database. This means:

- Your data is stored in **your personal iCloud account**, encrypted by Apple.
- We (the developers) have **no access** to your iCloud data. We cannot read, view, or retrieve any of your information.
- iCloud sync is managed entirely by Apple under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).
- You can disable iCloud sync for Goldfish in your device's Settings > [Your Name] > iCloud.

#### Data That Is Never Collected or Transmitted

Goldfish does **not**:

- Send any data to our servers or any third-party servers
- Include any analytics, tracking, or telemetry
- Include any advertising SDKs or ad networks
- Track your usage, behavior, or interactions
- Access your data in the background
- Create user accounts or require registration
- Share data with any third party for any purpose

Our App Store privacy label declares: **"Data Not Collected."**

#### Contact Import

When you choose to import contacts from your device's address book, the imported information is copied into Goldfish's local database. Your address book is accessed only at the moment you initiate the import and only the data you choose to import is copied. We never access your address book in the background.

#### Location Data

If you grant location permission, Goldfish uses your location solely to show nearby contacts. Your location is:

- Used only while the app is open and the feature is active
- Held temporarily in memory and **never saved** to any database or file
- **Never transmitted** off your device

#### Photos

Contact photos you add are compressed and stored locally on your device (and in your personal iCloud if sync is enabled). Photos are never uploaded to our servers or shared with any third party.

#### Children's Privacy

Goldfish does not knowingly collect personal information from children under 13 (or the applicable age in your jurisdiction). The app does not require an account, does not collect any data, and is rated 4+ on the App Store. If you believe a child has provided personal information through the app, please contact us — though by design, no data from the app reaches us.

#### Data Deletion

All your data is stored on your device and in your personal iCloud account. To delete all Goldfish data:

1. **Delete the app** from your device. This removes all local data.
2. To also remove iCloud data, go to **Settings > [Your Name] > iCloud > Manage Storage > Goldfish** and delete the data.

We do not retain any data on any server, so there is nothing for us to delete on our end.

#### Changes to This Policy

If we update this privacy policy, we will post the updated version at this URL and update the "Last updated" date. Since we do not collect email addresses or any contact information, we cannot notify you directly — please check this page periodically.

#### Contact Us

If you have questions about this privacy policy, contact us at:

📧 **support@goldfish-app.com**

---

## 6. Support Page

> **Host this at your support URL** (e.g., `https://goldfish-app.com/support`).

---

### Goldfish — Support

**Goldfish** is a personal relationship manager for iPhone. Visualize your personal and professional network as an interactive graph, organize contacts into circles, track relationships, and keep detailed contact cards — all completely private and on your device.

---

#### Frequently Asked Questions

**1. Where is my data stored?**

All your data is stored on your iPhone in a local database. If you have iCloud enabled, your data also syncs to your personal iCloud account so it's available on your other Apple devices. We (the developers) never have access to your data — we don't operate any servers.

**2. How do I import my existing contacts?**

During the initial setup, Goldfish offers to import contacts from your address book. If you skipped this step, go to **Settings > Import Contacts** to import them anytime. Your address book data is copied locally and never sent anywhere.

**3. How do I back up or transfer my data?**

You can export your contacts as standard vCard (.vcf) files:
- Open a contact and tap the **share button** (↑)
- Choose "Share with connections" to include related contacts
- Send via AirDrop, Messages, Mail, or save to Files

If iCloud is enabled, your data is automatically backed up to your iCloud account.

**4. How do I delete all my data?**

Simply delete the Goldfish app from your iPhone. This removes all local data. To also remove synced iCloud data, go to **Settings > [Your Name] > iCloud > Manage Storage > Goldfish** and tap "Delete Data."

**5. Why does Goldfish need access to my contacts / location / camera?**

- **Contacts:** Only used when you tap "Import Contacts." Your address book is read once and the data is stored locally. Never accessed in the background.
- **Location:** Only used for the "Nearby" filter to show contacts close to your current location. Your location is never saved or transmitted.
- **Camera:** Only used when you choose "Take Photo" for a contact's profile picture. Photos are stored locally and never uploaded.

All permissions are optional. Goldfish works fully without any of them.

---

#### Contact Us

For bug reports, feature requests, or questions:

📧 **support@goldfish-app.com**

Please include your Goldfish version number (found in Settings > About) and your iOS version when reporting issues.

---

#### Version History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026 | Initial release. Visual relationship graph, circles, contact management, vCard import/export, iCloud sync. |

---

*Goldfish is made with ❤️ and respects your privacy by design.*
