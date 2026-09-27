# Goldfish P0/P1 integration verification

27 September 2026. Goldfish only; Lines was not modified.

## Implemented

- Camera centering and fit preserve pond scope and open branches. Ancestor navigation stays in the Pond.
- One bottom panel combines pond scope, shown/total counts, reveal, map controls and contact context.
- Newly revealed contacts produce feedback, with explicit Locate for offscreen contacts. Feedback clears after collapse/Locate and is announced for VoiceOver.
- Overlapping stationary taps offer a contact chooser; dragging does not. Duplicate names include context and distance ordering.
- Relationship summaries honor direction, primary role and additional roles. Pond membership is labeled separately.
- Quick add starts with name, relationship and optional memory; details remain available. Dated memory entries preserve existing notes.
- Pond moves and relationship removals offer Undo. Tokens reject deleted targets, stale membership, duplicates and newly introduced ancestry cycles. Action toasts remain until dismissed or replaced.
- First run offers sample versus personal mode, with an explicit sample exit, import from empty state, and visible cleanup failures.
- Lighter pond fills and selected-tab treatment preserve the existing visual concept.

## Executed checks

- Full Debug simulator suite: **245 tests, 0 failures**.
- After cross-review fixes: **70 focused tests, 0 failures**. Includes camera/branch preservation, actual-camera offscreen detection, ordered overlapping candidates, reveal clearing, relationship context, quick form, memory, reversible operations and sample failure paths.
- Final two navigation shortcuts: Debug build passed; they call already-tested centering and existing help presentation. No additional behavior test required.
- Xcode project membership verified: **62 app/resource entries and 19 test entries**, no missing/duplicate sources. The stock Python checker lacked an optional parser dependency; equivalent membership checks used `plutil` JSON and Python's standard library.
- Info.plist/project syntax and `git diff --check`: passed.
- Unsigned Release archive succeeded using Xcode 26.6 / iOS 26.5 SDK. Bundle `app.pond.goldfish`, version 1.0 build 1. A final archive refresh includes the last navigation shortcuts.
- App icon: 1024×1024, no alpha. Privacy manifest and app icon included in the archive. Contacts usage description present. iPhone/iPad orientations explicit. Non-exempt encryption flag is false; current app has no custom encryption implementation.
- Read-only keychain inspection found an Apple Development identity for the Goldfish account, expiring February 2027. No distribution identity was found.
- Simulator render captures inspected for sample Pond (18 contacts), 50-contact fixture, and first-run choices. The fixtures use an in-memory store.

## Not yet verified / release blockers

- Interactive screen checks, VoiceOver interaction, largest text, and iPad/oldest-supported OS review are pending. The Mac locked during this run. Render captures are not click-through or human usability tests.
- Membership purchase is complete per owner; Apple still reports pending activation. Distribution signing, App Store Connect app record, upload, processing and Beta App Review have not completed.
- Support/privacy website drafts exist locally; public publication and in-app support email await confirmation of the proposed business inbox. Do not submit placeholder contact details.
- Physical-device installation, upgrade persistence and real first-time-user comprehension tests are pending. Use the five-task protocol in TESTFLIGHT_READINESS.md; proposed cohort targets are not recorded results.

No TestFlight invitation was sent and no App Store submission was made. The unsigned archive is a build artifact, not an installable or upload-ready distribution.
