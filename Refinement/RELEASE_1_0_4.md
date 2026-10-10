# Goldfish 1.0 (4) release candidate — 10 October 2026

## Included

- Refined Pond exploration with relationship-aware placement, clearer branch focus and return navigation, readable connection cues, and optional pond rearrangement with confirmation and Undo.
- Persisted System/Light/Dark appearance choices and a quiet-watercolor setting; the background remains stationary and yields to stronger contrast/transparency settings and Reduce Motion.
- Replayable welcome tour and first-use guidance that preserve contact data and onboarding preferences.
- Import follow-up that offers pond organization for newly imported contacts, and branch sharing that preselects the explored branch and reviews people, relationships, ponds, and note inclusion.
- Goldfish bundle import improvements and the previously introduced batch pond organization and connection creation flows.

## Verification

- 322 Xcode simulator tests passed, zero failures (`DeliveryTests.xcresult`).
- Unsigned physical-iPhone Release build succeeded (`delivery-release.log`).
- Manual simulator checks covered light/dark appearance, quiet-background control, welcome-tour replay and return to Settings, inline branch expansion, branch-share selection/review, and pond-move confirmation/Undo.
- A final camera-height correction passed the automated suite, but native coordinate input returned `noWindowsAvailable`; that exact animation still needs hands-on review. Physical-device haptics and a complete VoiceOver audit also remain unverified.
- The user rejected the visual result of the prior pass. The proposed visual correction remains outstanding; this candidate does not claim to address that feedback.
- Signed arm64 Release archive and code-signature verification succeeded for app.pond.goldfish, version 1.0 (4), using the existing Apple Distribution identity and App Store profile. Xcode upload succeeded on 10 October 2026 at 11:23 Europe/Zurich. Apple reported that the uploaded package was processing. Processing completion and tester-group rollout are not yet confirmed because App Store Connect in Chrome is signed out.

## Evidence

Implementation and verification notes: `POND_FOCUS_IMPLEMENTATION.md`, section “9 October — selected natural pond interaction pass”.

Simulator captures: `Refinement/pond-review-2026-10-09/natural-pond/`.

Automated test result and unsigned Release build log: `/tmp/goldfish-natural-pond/DeliveryTests.xcresult` and `/tmp/goldfish-natural-pond/delivery-release.log`.

Signed archive and upload log: `/Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-4/`.
Source commit for this binary: `0f43fa22f83a31f39ec2f3d037d525a4feda8e72`, pushed and verified on GitHub branch `codex/testflight-p0-p1`.
