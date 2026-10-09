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
- Code signature verification and App Store export succeeded. Upload succeeded at 16:54 UTC on 9 October 2026; Apple reported that the package was processing. Processing completion and beta approval are not yet verified.
- Source and archive both identify app.pond.goldfish, version 1.0, build 3.
- Support and privacy URLs responded HTTP 200. Hosted policy additions are drafted but publishing is blocked because the current Sites connector cannot access the existing project.

## Evidence

Preserved archive, IPA, logs and screenshots: /Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-3/
Original build/test workspace: /tmp/goldfish-release-2026-10-09/
Test result: /tmp/goldfish-release-2026-10-09/ReleaseCandidateTests.xcresult
Archive: Goldfish-1.0-3.xcarchive
Export: export/Goldfish.ipa

The older static_check.py and verify-core.py scripts have JSONC/parser and XCTest runner compatibility failures; the actual Xcode test suite and signed build passed. No physical-device upgrade test of this candidate has been completed. App Store Connect browser access is required to verify processing, update beta metadata, and distribute to the existing tester group. The requested audience is approximately 50 people, not a verified current tester count.

## Final interaction check

The simulator sharing flow exported Adriana plus her direct connections (Riley and Selma): three people, two relationships and two ponds. Opening the exported file in Goldfish showed the contents review. Import recognized all three existing contacts without adding duplicate contacts, relationships or ponds. If a file arrives while Settings is presented, its review waits until Settings closes; the file is retained. This is a remaining UX limitation. Native device-to-device AirDrop and an upgrade on a physical iPhone remain unverified.

Source commit for the uploaded binary: 7b63e4811671cb1c17d649e3e6a36e8cb29c2fa1, pushed and verified on GitHub branch codex/testflight-p0-p1. Later documentation-only commits do not change this binary.
