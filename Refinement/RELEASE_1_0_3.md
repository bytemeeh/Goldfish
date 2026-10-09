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
- Code signature verification and App Store export succeeded. Upload is in progress; this record does not claim processing or beta approval.
- Source and archive both identify app.pond.goldfish, version 1.0, build 3.
- Support and privacy URLs responded HTTP 200. Hosted policy additions are drafted but publishing is blocked because the current Sites connector cannot access the existing project.

## Evidence

Release artifacts and logs: /tmp/goldfish-release-2026-10-09/
Test result: ReleaseCandidateTests.xcresult
Archive: Goldfish-1.0-3.xcarchive
Export: export/Goldfish.ipa

The older static_check.py and verify-core.py scripts have JSONC/parser and XCTest runner compatibility failures; the actual Xcode test suite and signed build passed. No physical-device upgrade test of this candidate has been completed. App Store Connect browser access is required to verify processing, update beta metadata, and distribute to the existing tester group. The requested audience is approximately 50 people, not a verified current tester count.
