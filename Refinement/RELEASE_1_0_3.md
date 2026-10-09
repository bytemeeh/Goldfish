# Goldfish 1.0 (3) release candidate — 9 October 2026

## Included

- Refined pond layout, in-place branch exploration, compact selection controls, and large-text list fallback.
- Approved quiet watercolor pond backdrop, transparent fish artwork, and animated welcome transition with Reduce Motion support.
- Batch pond organization, guided connection creation, and selected-contact Goldfish bundle sharing/import.
- Import regression fix preserving specific family roles when merging an existing generic relationship.

## Verification

- 315 Xcode simulator tests passed, zero failures.
- Project/source consistency check passed; Apple Swift parser passed all 94 project Swift files.
- Signed arm64 Release archive succeeded using team VL6L6N34D5 and the existing App Store profile.
- Code signature verification and App Store export succeeded. Upload succeeded at 16:54 UTC on 9 October 2026; Apple reported that the package was processing. App Store Connect subsequently confirmed processing completion. Build 3 was submitted through the beta review flow and is now marked Testing in the external group.
- Source and archive both identify app.pond.goldfish, version 1.0, build 3.
- Support and privacy URLs responded HTTP 200. Hosted policy additions are drafted but publishing is blocked because the current Sites connector cannot access the existing project.

## Evidence

Preserved archive, IPA, logs and screenshots: /Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-3/
Original build/test workspace: /tmp/goldfish-release-2026-10-09/
Test result: /tmp/goldfish-release-2026-10-09/ReleaseCandidateTests.xcresult
Archive: Goldfish-1.0-3.xcarchive
Export: export/Goldfish.ipa

The older static_check.py and verify-core.py scripts have JSONC/parser and XCTest runner compatibility failures; the actual Xcode test suite and signed build passed. No physical-device upgrade test of this candidate has been completed. App Store Connect access is restored. Build 3 is assigned to Goldfish Internal Rehearsal and Goldfish U18 — External 50. The external group has one tester; approximately 50 remains the intended audience size. What to Test, beta description and review notes were saved, and Automatically notify testers was checked when submitting.

## Final interaction check

The simulator sharing flow exported Adriana plus her direct connections (Riley and Selma): three people, two relationships and two ponds. Opening the exported file in Goldfish showed the contents review. Import recognized all three existing contacts without adding duplicate contacts, relationships or ponds. If a file arrives while Settings is presented, its review waits until Settings closes; the file is retained. This is a remaining UX limitation. Native device-to-device AirDrop and an upgrade on a physical iPhone remain unverified.

Source commit for the uploaded binary: 7b63e4811671cb1c17d649e3e6a36e8cb29c2fa1, pushed and verified on GitHub branch codex/testflight-p0-p1. Later documentation-only commits do not change this binary.

## TestFlight rollout confirmation

On 9 October 2026, App Store Connect showed version 1.0 (3) as Testing in the external group, with 90 days remaining. The existing tester has access to the update. The public App Store listing remains a separate release. Proof: Goldfish-Releases/1.0-3/screenshots/testflight-build-3-testing.jpg (local, outside this repository).
