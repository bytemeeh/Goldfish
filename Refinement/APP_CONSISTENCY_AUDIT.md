# App consistency review — 13 October 2026

## Evidence and limits

Reviewed the release-checkout source for Home/List/search, contact details and forms, single/batch relationship editing, pond management, organization, onboarding/tour, Settings, sharing/import, feedback and in-app privacy copy. Followed actual HomeView call sites: the separate ContactListView has an empty Add callback, but HomeView renders its own contactsList. That unused implementation is not reported as a live broken button.

Opened the installed Goldfish app on the already-booted iPhone 17 Pro / iOS 26.5 simulator. Observed: Sample pond · 0 people; a full-width sample banner; the personal-style “Your pond starts here” empty state; Settings with “My Card not found”; and an empty Ponds management screen with only its title and add control. These are direct screen observations. The installed binary was not rebuilt or matched to the checkout, so they are not proof of current-source regressions or a clean-install failure. After opening Ponds, accessibility content disappeared and coordinate interaction returned `noWindowsAvailable`. Further live navigation was unavailable; this tool failure is not classified as an app accessibility defect.

No contacts were created, deleted, imported, reset or shared. No implementation or test-suite run is claimed. Source-confirmed findings below still need the specified runtime checks.

## Findings to include in the implementation plan

### Resumed interactive pass — reproduced results

After manual unlock, completed a further interactive simulator pass. App details and Settings both report **1.0 (4)** on iOS 26.5 / iPhone 17 Pro. The installed `Goldfish.debug.dylib` SHA-256 is `269b453e6861fa7e45af08d3f8223999c5ee65703e2243393c413b878bbebbca`, identical to the artifact in `/private/tmp/goldfish-oct13/DerivedData/Build/Products/Debug-iphonesimulator/Goldfish.app`. The checkout HEAD was `68e30cd0f9444eeb8a186e2af0e4047498276fb6` with existing uncommitted code changes. Matching the build artifact does not prove that every current source edit was compiled into it.

Used `--review-pond-disclosure` to load the built-in 23-person sample. The source routes this flag through `GoldfishModelContainer.preview()`, whose store is in-memory. No relationship, pond rename, import, export or reset was committed in this pass. The review flag does write onboarding/sample preferences; consequently the earlier empty-sample observation must not be represented as a reproduced clean-install defect. Screenshots and accessibility observations are present in the chat tool record.

| Finding / flow | Actual actions and result | Evidence status |
| --- | --- | --- |
| A2 feedback draft | Reopened Report a bug after the preceding pass's entered draft and dismissal. The field was blank and the counter was 0/10,000. | Draft loss reproduced across the two passes; no report sent. |
| A3 ordinary search | List → Search → type Adriana → open result → Close. Returned to the full 23-person List with no search field/query/results retained. | Reproduced. Relationship-query comparison remains source-confirmed. |
| A2 batch connections | Adriana → Add connections → select Aaron → choose Friend. Direction preview said Aaron is Adriana’s friend and Save all enabled. Cancel returned to details without warning; reopening showed Select people to continue and disabled Save all. | Unsaved selection/type loss reproduced; no relationship saved. |
| A2 pond edit | Settings → Manage Ponds → Book Club → change name to Audit draft pond. Verified changed field/preview, then Escape returned to management without warning. Reopening in the earlier repetition restored Book Club. | Unprotected dismissal and loss reproduced; no rename saved. |
| A1 scope mismatch | In Sample, Book Club showed 3 people and Daycare 4. Exit Sample → Settings → Manage Ponds showed both as 0 people with Delete actions. Book Club editor remained available and offered DELETE POND. | Cross-scope visibility/count/edit exposure reproduced in the sample-to-personal direction. Did not execute deletion or test the reverse direction with real records. |
| A6 reset | In the in-memory personal scope containing You but no other personal contacts, Settings RESET APP opened Reset Experience with Delete All Local Data and Cancel, without an export offer. Cancel closed it. | Naming mismatch and profile-only confirmation path reproduced; destructive/export round trip not executed. |
| A7 sharing language | Adriana → Share → Review 1 Person. Review displayed “1 people · 0 internal relationships · 1 ponds,” while the preceding CTA pluralized Person correctly. Sample/demo terminology also persisted. | Singular-count inconsistency reproduced. Review correctly listed Family, notes inclusion and only the selected contact scope. Cancelled before export. |
| Pond entry and expansion | Adriana details → Show in Pond selected Adriana with two hidden connections. Show 2 connections revealed Riley and Selma; Back returned to overview retaining the expanded contacts. | Native actions exercised. Show in Pond had no return-to-List control before expansion; Back after expansion returned to overview rather than the originating List. Covered by the new restoration contract. |
| Pond visual density | Expanded view showed permanent role labels/icons, a checkmark badge on Adriana and very faint unrelated Robert. Returned overview showed the large My ponds panel, multiple menus, counts and repeated guidance. | Rendered evidence supports existing clutter, focus-contrast and selection-cue requirements; do not add duplicate P0s. |
| Import entry | Personal empty-state Import Contacts opened File/Phonebook choice. Escape cancelled to Settings. | Entry/cancellation verified only; no permissions requested and no file imported. |

Accessibility-based native controls and keyboard input worked after reconnecting. Coordinate clicks still returned `noWindowsAvailable`, and one screenshot returned a ScreenCaptureKit stream error before succeeding on retry. The graph accessibility snapshot exposed its container but no individual contact buttons. This is insufficient to diagnose a VoiceOver defect: independently verify with VoiceOver. Direct node tapping, nested graph gestures, dragging, touch-target behavior, dark appearance, largest text, tour completion, injected failures, import round trips and destructive safeguards remain required implementation/release checks. This is a simulator-backed gap-analysis pass, not completed release verification.

### Additional narrow fixes from the interactive pass

- Extend A7 to count grammar: use correct zero/one/many forms in sharing/import/organization summaries, consistent with their action labels. The confirmed example is sharing one person in one pond.
- Extend the existing information-once rule to List and details: the grouped List repeats Pond: Family beneath every row already under FAMILY; Adriana's detail hero shows FAMILY and the membership section repeats Pond: Family. Keep a single clear visual membership indication per context while preserving meaningful accessibility labels. This is a targeted presentation cleanup, not a profile redesign.
- Keep sample editing scope visible in secondary screens. The same pond can otherwise look empty merely because the current scope hides its members; any intentionally global operation must disclose its actual affected scope before being offered.

### Simulator follow-up — review still in progress

Resumed the installed app on the same iPhone 17 Pro simulator after the user required simulator-based gap analysis. Rebinding the Simulator app and using accessibility actions restored partial interaction despite intermittent `noWindowsAvailable` errors.

- Reproduced Sample pond · 0 people after relaunch. Switched from Pond to List successfully. List adds Import Contacts to the empty state, while Pond offers only Add a contact; both use personal-pond wording in sample scope.
- Opened Add Contact from List. The screen says New Demo Contact and directs the user to Show Demo Data in Settings, confirming the visible sample/demo terminology mismatch. Closed the unchanged form successfully with Escape.
- Opened Settings → Report a bug. Entered the synthetic text “Simulator audit draft. Do not send.” The form displayed the entered text and a 35/10,000 counter. Escape dismissed the entire Settings sheet to Home without a discard confirmation. Reopened Settings successfully, but reopening Report a bug returned `cgWindowNotFound`; the next app connection explicitly reported that the Mac was locked and automatic unlock failed. Therefore unprotected dismissal is observed, but persistence/loss after reopening remains unverified. Nothing was sent.
- Populated-network navigation, sharing review, pond scope protection and remaining editor flows still require interactive checks. The installed binary remains unmatched to the current source. This follow-up does not complete the mandatory simulator audit or establish a release gate passed.

Resume after manual Mac unlock: reopen the report to check draft persistence, establish a known populated review fixture and matched build without overwriting personal data, then exercise search/details/return, pond management, relationship editors, sharing/import review and tour behavior. Record runtime evidence beside A1–A9 rather than relabeling source findings as simulator-confirmed.

### A1 — Scope protection must cover ponds, not just people (P0)

Source: [CircleManagerViewModel](../ViewModels/CircleManagerViewModel.swift), [CircleManagerView](../Views/CircleManagerView.swift), [ContactFormViewModel](../ViewModels/ContactFormViewModel.swift), [ContactOrganizationView](../Views/ContactOrganizationView.swift).

Pond management loads every pond and applies sample/personal filtering only to member counts. Edit/delete acts on that shared pond object. Contact forms also offer all ponds, whereas Organize people explicitly excludes custom ponds occupied by the other scope. A personal pond can therefore appear empty while browsing samples, and management can affect its real memberships. System ponds are shared deliberately, which needs separate treatment.

Use one eligibility policy for management, contact forms, organization and sharing filters. In sample mode, personal custom ponds must not be editable/deletable or usable as sample destinations. Any intentionally global operation must state its full scope and affected membership count before confirmation. Preserve shared built-in ponds and existing records; do not migrate or split them implicitly.

Acceptance: with personal and sample contacts in different custom ponds, every entry point offers consistent destinations; editing/deleting in sample mode cannot silently change hidden personal organization. Include empty and legacy mixed-scope ponds. Source-confirmed policy mismatch; destructive behavior was not exercised.

### A2 — Protect drafts consistently across editors (P1, this release)

Source: [ContactFormView](../Views/ContactFormView.swift), [AddRelationshipView](../Views/AddRelationshipView.swift), [BatchConnectionsView](../Views/BatchConnectionsView.swift), [CircleManagerView](../Views/CircleManagerView.swift), [FeedbackView](../Views/FeedbackView.swift).

Contact editing tracks unsaved changes, blocks swipe dismissal and offers Discard/Keep Editing. Relationship and batch editors simply dismiss on Cancel; pond edit sheets have no corresponding dirty-state protection. Feedback stores message/screenshot state locally and Done dismisses it without saving a draft or confirming loss.

Adopt a consistent rule: unchanged forms close immediately; changed forms offer Keep Editing/Discard, or preserve a local draft with clear behavior. Cover sheet swipe, navigation Back and explicit Cancel/Done. Feedback “Done” must not imply the report was sent or saved. Keep the existing explicit sharing flow.

Acceptance: entering a relationship, batch, pond change or report, then leaving and returning, does not silently lose meaningful input. After successful save/send completion, no stale discard prompt remains. Runtime dismissal routes remain to be checked.

### A3 — Search return behavior differs by query type (P1, this release)

Source: [HomeView](../Views/HomeView.swift), ordinary SearchOverlayView selection versus relationshipResults and openPondRipple.

Opening an ordinary result clears the query and closes search before presenting details. Opening a relationship-search result retains search. Thus dismissal returns to different contexts for the same inspect-a-person task; ordinary search also cannot supply the prior query to pond exploration restoration.

Preserve query, filters and result position while inspecting a result in either search mode. Define Show in Pond as an explicit transition into selection, with optional expansion/path tracing governed by the new contract. Returning should restore the originating search or List context without adding canvas controls.

Acceptance: name/email/note search and relationship search all survive open details → close, edit → return and Show in Pond → return. Clearing search and returning to All ponds remain deliberate actions.

### A4 — Tour and help will teach obsolete actions (P1, required with state redesign)

Source: [FeatureWalkthroughManager](../ViewModels/FeatureWalkthroughManager.swift), [GraphContainerView](../Views/GraphContainerView.swift) help rows, [HomeView](../Views/HomeView.swift) update notice, [ContactDetailView](../Views/ContactDetailView.swift).

The tour says “Tap a person to reveal their connections”; graph help teaches automatic reveal/focus, Collapse all and My ponds. The update notice teaches count cues and trails. These directly contradict the new selection/expansion and single-return contract.

Update copy, highlights, accessibility hints and completion events together: select a contact, then explicitly use Connections. Use the same rule from details, search and List entry points. Remove obsolete update notices and do not replace them with another persistent banner.

Acceptance: a fresh tour and Settings replay both complete using the actual new actions, with no reference to removed controls and no event falsely completing expansion on selection alone.

### A5 — Missing-profile and empty-sample states lack a clear recovery route (P1 investigation; promote to P0 if reproduced in ordinary launch/reset)

Source: [SettingsView](../Views/SettingsView.swift), [SettingsViewModel](../ViewModels/SettingsViewModel.swift), [HomeView](../Views/HomeView.swift), [DemoModeManager](../ViewModels/DemoModeManager.swift).

The simulator displayed a completed-looking home with no sample people and no profile. Settings offers only “My Card not found”; its profile fetch catch only logs an error. The personal empty-state wording is also misleading in an empty sample scope. Current source uses persisted onboarding/sample flags and sample-context updates on launch; this observation alone does not establish why the installed database and flags disagree.

Add explicit loading, genuinely empty, unavailable-data and incomplete-profile states. Provide a safe retry or profile/setup repair path that preserves existing contacts. Distinguish a deliberately emptied sample from seed failure; do not silently recreate samples a user removed. Give empty Ponds management a concise explanation and Create pond action.

Acceptance: test clean install, completed onboarding, database/flag mismatch, reset/relaunch, missing profile, failed fetch and intentionally removed sample contacts. No misleading invitation to populate personal data while in sample mode; recovery never requires deleting personal data.

### A6 — Reset/export promises exceed the offered copy (P1, before release)

Source: [SettingsView](../Views/SettingsView.swift), [SettingsViewModel](../ViewModels/SettingsViewModel.swift), [PrivacyPolicyView](../Views/PrivacyPolicyView.swift), [VCardExportService](../Services/VCardExportService.swift).

Reset's “Export First” generates a vCard directly, while the in-app privacy text correctly explains that a vCard is not a complete pond backup. The reset warning does not explain omitted empty ponds, layout positions or other unsupported records. It offers export only when non-demo/non-self contacts exist, excluding a profile-only or empty-custom-pond setup. “Reset App” becomes “Reset Experience” in the confirmation, and the reset handler does not reset appearance/quiet-background preferences despite promising an initial state.

Use one reset name and precise deletion scope. Before destruction, explain what the offered export preserves and omits; reuse an appropriate reviewed export path without calling it a complete backup. Account for profile-only and pond-only data and failed export/count reads. Either reset the stated preferences or narrow the promise. Do not build a new backup system in this pass.

Acceptance: export cancellation/failure never triggers deletion; a successful file export does not imply a complete restore; reset copy matches actual records/preferences removed. Verify supported round-trip data separately from known omissions.

### A7 — Sample, demo, profile and action terminology drifts (P1, small consistency pass)

Source: Settings says “Show Demo Data”/“Demo Mode”; home says “Sample pond”/“Exit Sample”; new-contact title says “New Demo Contact”; settings fallback says “My Card”; export copy switches between demo and sample. Settings also mixes title-case labels with “Organize people.”

Use Sample consistently in visible copy, Your profile for the user's card, Pond for membership, and connection/relationship language that distinguishes exploration from editing a saved type. Use sentence case for actions. Keep internal model names unchanged. A sample indicator must make scope clear in editing/sharing without adding repeated banners.

Acceptance: follow onboarding → home → add → details → settings → share and back without changing terminology for the same concept. VoiceOver labels match the visible action and current scope.

### A8 — Load errors can become misleading empty states (P1, this release)

Source: [HomeViewModel](../ViewModels/HomeViewModel.swift) sets emptyGlobal on failed initial load; [HomeView](../Views/HomeView.swift) then offers Add/Import after the error alert is dismissed. ContactFormViewModel logs failures loading people/ponds without exposing recovery. Settings profile fetch also logs only.

Retain an explicit failed-load state with Retry, preserve existing content where safe, and distinguish failure from zero results. Avoid showing an empty selection menu as though no relationships/ponds exist. Keep entered form data while retrying dependencies. Avoid repeated toasts plus alerts for the same failure.

Acceptance: injected read failures produce a truthful recoverable state in home, profile and form pickers; retry refreshes in place without duplicating records or clearing a draft.

### A9 — Sharing filters and review blur active membership with exclusion metadata (P1, narrow correctness fix)

Source: [ContactExportSelectionView](../Views/ContactExportSelectionView.swift) pond picker and includedPonds use any membership row, including manuallyExcluded rows; its contact filter uses active membership only. [GoldfishContactBundle](../Services/GoldfishContactBundle.swift) intentionally serializes exclusion metadata.

A pond can be offered by the picker even when all eligible people have been excluded from it, yielding an empty selection. The review's “Ponds included” does not distinguish active assignments from exclusion metadata. Preserve intentional serialization; separate active pond filtering from the exact file-content summary.

Acceptance: a contact moved from a built-in pond into a custom pond appears only under their active pond filter. File review truthfully explains included pond metadata and active assignments, agrees with preview/decoded output, and retains exclusion behavior on round trip.

## Bounded follow-ups

ContactRowView reconstructs the reachable graph for inferred relationship and pond summaries, while the live HomeView list does not pass precomputed summaries. Profile this in the existing dense-network check; cache/reuse scope context if it causes measurable scrolling or search latency. Do not classify it as a reproduced performance bug.

Full light/dark, Dynamic Type, VoiceOver and physical-device checks remain pending. Extend those checks to editors, import review, sharing review and feedback, not only the canvas. Do not add hypothetical visual defects to the bug count.


## Implementation evidence — 13 October, resumed after “go”

This is a partial implementation record, not closure of the release gates. Existing uncommitted graph work was preserved and extended narrowly. No upload, tester notification, real-data deletion or sharing was performed.

### Implemented safeguards

- A1: one eligibility policy now filters pond management, contact forms and organization. Management mutations and assignment saves recheck eligibility. Historical exclusion rows also protect a custom pond from being modified from the other scope; system ponds remain shared. Existing records are not migrated.
- A2: pond, relationship, batch-connection and feedback drafts block interactive dismissal and require deliberate discard through their explicit cancel/close controls. Feedback compares current content/options with its initial state, so reverting edits does not leave a stale dirty flag. Existing contact-form protection is retained.
- A3: ordinary search no longer clears its query when opening contact details. External Show in Pond origin restoration is still pending.
- A6: every Reset App entry offers the same personal-contact export and truthful deletion warning, including profile-only stores. Copy states that samples are omitted from that export and that it is not a full backup. Obsolete alternate reset prompt removed.
- A7/A9: sample terminology and singular/plural sharing counts corrected on the touched screens. Sharing pond filters use active memberships; the review describes included exclusion metadata separately.
- A8: failed initial List reads get a Retry state. Graph read failure retains its last valid state behind a recoverable error presentation. Contact editing choices expose failure and retry without clearing the draft; Save stays unavailable until choices load. Profile read failures are surfaced. Missing-profile clean-start diagnosis and injected failure verification remain pending.

### Simulator checks during implementation

Device: iPhone 17 Pro, iOS 26.5, `9110FDC2-34EF-415B-BE7E-29FAF166CDC1`. Fresh build from this checkout, launched with `--review-pond-disclosure` into the in-memory 23-person fixture. These checks used native simulator accessibility actions and keyboard input, not direct touch gestures.

- Search Adriana → open details → Close: query `Adriana`, one result and the original Pond selection remained visible. Previously this returned to the unfiltered List.
- Adriana → Add connections → select Aaron → Cancel: “Discard changes?” appeared. Dismissing that popup retained Aaron and the one-connection draft. Removing the temporary selection allowed Cancel to close directly.
- Settings → Report a bug → enter synthetic text: Escape left the report open. Close showed “Discard report?”; dismissing the popup retained all 31 characters. No report was sent, copied or shared.
- Screenshots and accessibility snapshots worked. Coordinate clicks failed with computer-use error `-10005: noWindowsAvailable` before dispatch, including after resetting the automation session and raising the simulator window. This leaves direct taps, dragging, swipe-dismissal and interruption gestures unverified. Do not relabel accessibility activation as direct input or VoiceOver testing.

### Automated evidence and remaining gates

Current safeguard runs: ContactOrganizationTests **8 passed**, including both scope directions and rejected stale/forged operations. ContactQuickForm, DataIntegrity, GraphLayout (model), PondDisclosure, Reset and TransferIntegrity suites: **88 passed**. The selector `ContactFormViewModelTests` in one invocation matched no suite; contact-form coverage was subsequently run under its actual `ContactQuickFormTests` name.

The separate scene baseline reproduced **19 assertions across three failed test cases**, not 19 independent defects: sample identity layout, startup overlap correction, and dragging a corrected pond. Source inspection confirmed the overview fixture subtracted a footer already outside SpriteView. It also found contact positions using only saved offsets while pond outlines used saved offsets plus collision corrections. The fixture now uses the measured canvas; contact positions use the effective offset, corrections survive same-scope refreshes and reset when the profile/scope changes. Restore automatic layout still clears corrections deliberately. The first scene rerun passed all **55 tests**; additional refresh/scope assertions were then added and require their own final result below.

Checkpoints 0, 1a and 1b remain incomplete despite the passing subsets above: both-direction simulator scope checks, all editor dismissal/save routes, failure injection, reset/export cancellation, clean-store profile triage and the required gesture/accessibility matrix are not all complete. Three-state controls, exploration history, external origins, density behavior and tour cleanup still need implementation and verification. No release-readiness claim is made.

Final scene rerun: **55 tests passed, zero failures**, including refresh retention and a switch to a distinct sample fixture. Result: `/private/tmp/goldfish-plan-implementation/Logs/Test/Test-Goldfish-2026.10.13_23-03-01-+0200.xcresult`. Across the three final targeted runs, 151 tests passed; this is not the full release suite. `git diff --check` passed.

Final build `Goldfish.debug.dylib` SHA-256: `16df31877b2dc13d358db6f5b5bc4de0972b280609eea0e709469b3b4aa6f047`. Tracked code/test diff SHA-256 (`git diff -- Models Services Tests ViewModels Views`): `6dfb08d391636a56887a2b67af795cb8b6ca391e149ec61f4460917650650120`. Base commit remains `68e30cd0f9444eeb8a186e2af0e4047498276fb6`; changes are uncommitted.

Final rendered-build check could not finish: after launch, computer-use reported `cgWindowNotFound`; inventory then explicitly reported that the Mac was locked and automatic unlock had failed. Manual unlock is required. The simulator was shut down afterward. Earlier interactive safeguard checks apply to the interim build; final feedback dirty-state refinements and layout fixes still require a rendered/interactive recheck.


## Implementation evidence — 14 October

### Changes implemented

- Overview's permanent My ponds card, tips, map menus and explanatory footer are absent in ordinary browsing. Recenter appears only after an overview camera adjustment.
- Contact selection uses the compact name/context group and Connections/More group. Direct scene activation and accessibility selection select without expanding. The numbered badge is hidden; the restrained dot cue remains. Relationship and age captions no longer repeat beneath graph identities. Surrounding people and pond headings use less severe dimming during focus.
- Connections explicitly reveals a bounded batch. Back uses an ordered exploration history, independent of relationship ancestry. Selecting another contact alone adds no step; pagination adds no step. Back exits path mode first. All ponds restores the captured origin disclosure and camera; fresh exploration does not retain the just-closed branch cache. Snapshot restoration reloads current records so it cannot undo data edits.
- Search/List entry records its origin and uses Back at its root. More offers All ponds for external entry. Pond/List switching retains the mounted scene and pauses it when inactive. Cancelled/backgrounded browsing invokes the existing gesture cancellation path. Deleted selections reconcile to a valid earlier exploration or the origin.
- Default More contains Open contact, optional Show connection path, and Hide connections. Full editing and sharing remain in details. Settings now holds zoom, Restore automatic layout and map help. The sample scope label supplies the mode indicator and exit menu, replacing the repeated banner. Ordinary What's new banners are removed. Pond tap offers Show people in List.
- Tour selection wording now describes tap → Connections. Map-help copy describes the revised controls. Grouped List rows no longer repeat their section's pond label visually; accessibility context is retained. Contact details do not repeat the hero's membership label in a second story row.

### Verification

Initial simulator access on the same iPhone 17 Pro / iOS 26.5 allowed inspection of the previous tested build. All eight overview contacts had visible names; the old large card and numbered bubbles were still present, confirming the baseline before this turn's interface edits. A coordinate tap failed with `noWindowsAvailable` before dispatch. Later `getApp` returned `cgWindowNotFound`; inventory explicitly reported that the Mac was locked and automatic unlock had failed. Manual unlock was requested. The final rendered/interactive review could not proceed, and a later retry still found no routable window.

Automated runs exposed obsolete select-and-expand, caption and tour-copy expectations. They were updated to assert selection without disclosure/camera change, a restrained cue with no numbered badge, panel-only relationship context, and explicit Connections wording. Added state tests cover overview restoration, preservation of edits, fresh re-entry, nested exploration, pagination, path-mode return and external-origin return signaling. Existing legacy route tests remain; they do not stand in for the new ordinary browsing contract.

Final full suite: **330 tests, zero failures**. Result: `/private/tmp/goldfish-plan-implementation/Logs/Test/Test-Goldfish-2026.10.14_08-43-11-+0200.xcresult`. Log: `/private/tmp/goldfish-oct14-full-final.log`. `git diff --check` passed.

Build `Goldfish.debug.dylib` SHA-256: `e7956546a3d1be89779ecee570f09c248c378974f82ad71f09b28f06b2a1b2ed`. Tracked code/test diff SHA-256 (`git diff -- Models Services Tests ViewModels Views`): `f8ee8daf255d90d545507c32b54a12114465793ddfd183267fff40ac7afa519d`. Changes remain uncommitted on base `68e30cd0f9444eeb8a186e2af0e4047498276fb6`.

The new interface has **not** passed rendered or hands-on acceptance. Do not mark J1–J5, the accessibility/density matrix, all A1–A9 flows, or the release gates complete. Density-driven smaller batches and readable-scale panning still require implementation and verification; the existing four-person batch limit alone is insufficient. No upload or notification was performed. Simulator shut down after testing while manual access remained blocked.

### Header refinement — 14 October, subsequent pass

Preserved the existing uncommitted work. HomeView now places the compact Pond/List control and Search/Add/Settings in one primary row, with scope on its own line. A larger-text fallback stacks the controls; mode targets retain a minimum 64 × 44 points. This removes the scope label from the horizontal fit calculation and avoids the ordinary full-width mode strip. This is implemented, but final rendered acceptance remains pending.

Simulator was booted and the prior installed interface rendered on iPhone 17 Pro / iOS 26.5. The baseline visibly showed the sample/count/actions row above a full-width Pond/List strip. A direct coordinate tap failed before dispatch with `-10005: noWindowsAvailable`. Subsequent computer-use observations explicitly reported that the Mac was locked and automatic unlock failed. Manual unlock was requested; the post-install retry returned the same lock blocker.

The fresh Debug simulator build succeeded and was installed/launched with `--review-pond-disclosure` (in-memory fixture). Build log: `/private/tmp/goldfish-header-build.log`. `Goldfish.debug.dylib` SHA-256: `495ee0f21dfaa4dbfe919d23bf483d5c6b48ea08cfb911e6e534205454618690`. HomeView diff SHA-256: `117e1e9566c0adcd6aaae17e9ed66991f8b57bc3be8a895712d4c0e774337a29`. `git diff --check` passed. The earlier 330-test result remains historical; no new full test run is claimed for this presentation-only edit. Final header screenshots, control interactions, text-size checks and selection/expansion/return review require unlocked simulator access. No acceptance checkpoint is closed by this pass.

### Header simulator verification — 14 October, resumed after unlock

On iPhone 17 Pro / iOS 26.5, launched the installed header build identified above with `--review-pond-disclosure`. Fresh simulator screenshots confirmed compact Pond/List on the left, Search/Add/Settings on the right, and a separate scope line. No header clipping or overlap was visible at the original `large` content size. All eight overview identities had readable names.

Native accessibility activation completed List → Adriana → Show in Pond → Show 2 connections → Back. Selection showed Adriana's ring and compact panel while the overview's eight people remained visible; expansion revealed Selma and Riley with their relationship lines and changed the action to Connections shown. The header remained in the same position throughout. Back restored the List origin with its sample scope. List rows displayed relationship context without repeating the section's pond membership. These are rendered and native-control checks, not direct touch or VoiceOver evidence.

Direct coordinate contact activation still failed before dispatch with `-10005: noWindowsAvailable`. Attempting the window's Raise accessibility action initially returned an invalid-element error; refreshing recovered observation and native-control interaction but did not resolve coordinate routing. After changing simulator content size to `accessibility-extra-extra-extra-large`, the observation tool explicitly reported that the Mac was locked and automatic unlock failed. Largest-text review could not be observed; content size was restored to its original `large`. Manual unlock was requested again. Larger-device, direct gestures, nested navigation and VoiceOver gates remain open. No source change or new full test run was needed for the successful normal-size checks.

Access recovered during the same pass. At largest accessibility text, the unselected header and List fit, but selecting Adriana reproduced horizontal overflow: the Connections label's unconditional horizontal `fixedSize` widened the entire view and clipped the header. Changed only `inspectorButton` to allow horizontal wrapping and vertical growth at accessibility sizes. Rebuilt successfully (`/private/tmp/goldfish-header-accessibility-build.log`) and reinstalled.

Final-build simulator verification: largest-text selection now stays within screen width, Show 2 connections wraps over two lines, all header actions remain visible, explicit expansion adds Riley/Selma, and All ponds clears selection/disclosure back to the eight-person overview. Returned to normal text and inspected the overview in both app Light and Dark appearance. Search opens and cancels, Add opens its expected menu, and Settings opens/closes through the header. Restored the original app/simulator Light appearance and `large` content size. Screenshots were inspected in the current review chat. Direct coordinate input was retried after these working native actions and still failed with `noWindowsAvailable`; gesture and VoiceOver acceptance remain pending. This bounded header/text-wrapping review does not close the broader release matrix or large-phone/density journeys.

Final build `Goldfish.debug.dylib` SHA-256: `db1b57c44af838ab0ad4547473c1178c18c93a2dce17c8dd112aa6bedbe36107`. Tracked code/test diff SHA-256: `b76bb4439288e4f910c89222c01f3c52837c120d8f975d169fde133d222d042a`. `git diff --check` passed. No new automated tests were added or full suite rerun for these view-only layout changes; the previous 330 tests are not represented as a test run of this binary. All changes remain uncommitted. Simulator shut down after review.

### Quiet pond background — 14 October

Per the requested behavior, Quiet pond background now omits the decorative watercolor layer entirely in both Light and Dark appearance. Settings describes removal rather than reduced opacity. Existing uncommitted changes were preserved.

Fresh Debug simulator build passed (`/private/tmp/goldfish-quiet-background-build.log`). On iPhone 17 Pro / iOS 26.5 with the in-memory pond review fixture, enabled Quiet through Settings and inspected both Light and Dark overview screenshots: no watercolor goldfish remained, while pond shapes and contacts remained visible. Disabled Quiet and confirmed the watercolor returned in Light appearance. Restored original review preferences (Light, Quiet off). `git diff --check` passed. No full test suite rerun for this visual-only change. Simulator shut down after verification.

### People behind and edge navigation — 14 October

Implemented the user's selected People behind concept: up to two opaque overlapping medallions behind a contact, one when a single eligible person remains hidden, none at zero. Partial expansion retains the cue. Screen-space offsets remain stable with zoom. The first scene run exposed title overlap from the larger footprint; title-band geometry now reserves the actual added reach. Scene regression tests then passed, followed by all 333 tests on build 5.

Added the user-selected edge-swipe behavior to Home: right edge inward selects List; left edge inward selects Pond. The home mode transition is shared with the buttons. Short, outward, vertical and cancelled gestures do not change mode; modal/detail/search contexts disable the home recognizer. The recognizer is removed when its host leaves the window.

Simulator overview review confirmed the stacked circles with readable names and pond titles. A direct right-edge drag failed before dispatch with `noWindowsAvailable`; manual gesture confirmation requested. No direct-touch or VoiceOver pass is claimed. Release preparation and distribution are tracked in RELEASE_1_0_5.md. User explicitly authorized GitHub push and a new TestFlight build in this chat, superseding the earlier lack of upload authorization; this does not turn pending acceptance checks into passes.
