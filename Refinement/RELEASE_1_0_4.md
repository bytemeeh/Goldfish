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
- The proposed broader visual redesign was rejected and remains unresolved. This candidate does not claim to address that feedback.
- Version 1.0 (4) is the release candidate target. The signed archive, upload, TestFlight status, and rollout confirmation are pending.

## Evidence

Implementation and verification notes: `POND_FOCUS_IMPLEMENTATION.md`, section “9 October — selected natural pond interaction pass”.

Simulator captures: `Refinement/pond-review-2026-10-09/natural-pond/`.

Automated test result and unsigned Release build log: `/tmp/goldfish-natural-pond/DeliveryTests.xcresult` and `/tmp/goldfish-natural-pond/delivery-release.log`.
