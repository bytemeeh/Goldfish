# Goldfish 1.0 (5) — 14 October 2026

## Candidate changes

- Three-state pond browsing: selection first, explicit Connections, compact contact panel, optional path tracing, and exploration/origin restoration.
- Compact header, larger-text action wrapping, and Quiet pond background that removes watercolor entirely.
- People-behind circles replace the subtle dot cue. One hidden person uses one backing circle; two or more use two. The stack remains during partial expansion and disappears when all eligible people are visible. Counts remain in Connections and accessibility descriptions. Pond title clearance includes the stack.
- Inward right-edge swipe opens List; inward left-edge swipe returns to Pond. Ordinary canvas drags retain panning. Search, details and modal editors do not route edge gestures into the home mode switch. Cancelled/short/vertical gestures do not switch.
- Preserved and included existing scope, draft, load-recovery, terminology and sharing-filter corrections in the working tree.

## Verification

- Final full simulator suite: 333 tests, zero failures. Result: `/private/tmp/goldfish-plan-implementation/Logs/Test/Test-Goldfish-2026.10.14_10-14-29-+0200.xcresult`; log: `/private/tmp/goldfish-build5-tests.log`.
- Project membership/identity check passed. `git diff --check` passed. The optional tree-sitter static checker could not run because its installed Swift grammar requires a newer parser ABI; Xcode compiled and typechecked the full app and test suite successfully.
- Signed Release archive succeeded using existing Apple Distribution identity, team `VL6L6N34D5`, bundle `app.pond.goldfish`, and `Goldfish App Store 2026` profile.
- Final simulator overview visually reviewed on iPhone 17 Pro / iOS 26.5 with the in-memory 23-person fixture. Stacked circles, contact names and pond headings were visible and separated.
- Earlier checks of the combined interface include selection/Connections/return using native accessibility actions, largest-text wrapping, header actions, and Quiet background in Light and Dark. See APP_CONSISTENCY_AUDIT.md for exact evidence and limits.
- Direct edge drag attempted through computer use failed before dispatch with `noWindowsAvailable`. Manual confirmation requested. Direct gestures, full VoiceOver, dense expansion and the broader acceptance matrix remain incomplete; automated policy tests do not establish touch behavior.

## Distribution status

Prepared candidate, not yet uploaded or available to testers. Existing TestFlight app verified as Goldfish: Relationship Journal, app ID 6816847677, account Marcel Meeh / goldfish.pond.app@gmail.com. Previous latest build is 1.0 (4), Testing. App Store Connect displayed an updated Developer Program License Agreement requiring Account Holder review; user asked to handle it. No agreement was accepted by the agent.

Release artifacts: `/Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-5/`.
Code/test diff SHA-256 before commit: `8725a5c53dad72d3f5048954aaadf32ded3eac9385e378dbcb2ff7599803ee61`.

## What to Test

Try the people-behind circles: select a person, reveal Connections, reveal any remaining batch, then return. Swipe inward from the right edge to List and from the left edge to Pond; ordinary pond dragging should still pan. Check Search/List return, nested exploration, larger text, Light/Dark, and Quiet pond background. Use fictional sample data for draft, sharing/import and scope checks. Direct gestures and the complete accessibility/density matrix still need hands-on testing.
