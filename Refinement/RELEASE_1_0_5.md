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
- Simulator partial/full expansion checked via native accessibility actions: Jake's Show 4 connections leaves one backing circle and Show 1 more; revealing the final person removes Jake's backing circle and shows Connections shown. Other people retain their own hidden-person cues.
- App Store package export succeeded; the signed IPA is in `1.0-5/export/Goldfish.ipa`. Strict archive signature verification passed.
- Earlier checks of the combined interface include selection/Connections/return using native accessibility actions, largest-text wrapping, header actions, and Quiet background in Light and Dark. See APP_CONSISTENCY_AUDIT.md for exact evidence and limits.
- Direct edge drag attempted through computer use failed before dispatch with `noWindowsAvailable`. Manual confirmation requested. Direct gestures, full VoiceOver, dense expansion and the broader acceptance matrix remain incomplete; automated policy tests do not establish touch behavior.

## Distribution status

Uploaded successfully at 10:23 Europe/Zurich on 14 October 2026. Xcode reported Upload succeeded and EXPORT SUCCEEDED. Processing completed, testing notes were saved, and the build was submitted for beta review for the existing Goldfish U18 — External 50 group (one tester). The initial run stopped at **Approved**, with **Notify Testers** still available and automatic notification unchecked. Following the user’s explicit go-ahead on 14 October 2026, Notify Testers was clicked and App Store Connect visibly changed build 5 to **Testing**. The existing tester was notified; no new testers or groups were created. Build ID: `5d76ba6c-b39f-4d3e-ac61-6539ddb9ec21`.

Final TestFlight evidence: `/Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-5/testflight-testing.jpg`. The signed-in Apple and GitHub Chrome tabs were periodically refreshed during this run and left open. Simulator remains open for the requested manual edge-swipe confirmation; shut it down after that check.

Existing TestFlight app verified as Goldfish: Relationship Journal, app ID 6816847677, account Marcel Meeh / goldfish.pond.app@gmail.com. Previous latest build is 1.0 (4), Testing. App Store Connect earlier displayed an updated Developer Program License Agreement requiring Account Holder review; user asked to handle it. No agreement was accepted by the agent, and it did not block this upload. Upload is explicitly authorized by the user; the remaining acceptance matrix is still pending and is not marked complete by this beta upload.

Release artifacts: `/Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-5/`.
Code/test diff SHA-256 before commit: `8725a5c53dad72d3f5048954aaadf32ded3eac9385e378dbcb2ff7599803ee61`.
Source commit: `f6db20a`, pushed to `https://github.com/bytemeeh/Goldfish/tree/codex/testflight-p0-p1` through the `github` remote. The existing local `origin` was preserved.

## What to Test

Try the people-behind circles: select a person, reveal Connections, reveal any remaining batch, then return. Swipe inward from the right edge to List and from the left edge to Pond; ordinary pond dragging should still pan. Check Search/List return, nested exploration, larger text, Light/Dark, and Quiet pond background. Use fictional sample data for draft, sharing/import and scope checks. Direct gestures and the complete accessibility/density matrix still need hands-on testing.
