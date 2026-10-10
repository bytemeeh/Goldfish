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
- Signed arm64 Release archive and code-signature verification succeeded for app.pond.goldfish, version 1.0 (4), using the existing Apple Distribution identity and App Store profile. Xcode upload succeeded on 10 October 2026 at 11:23 Europe/Zurich. Apple reported that the uploaded package was processing. App Store Connect subsequently confirmed processing completion and status Testing for the external group.

## Evidence

Implementation and verification notes: `POND_FOCUS_IMPLEMENTATION.md`, section “9 October — selected natural pond interaction pass”.

Simulator captures: `Refinement/pond-review-2026-10-09/natural-pond/`.

Automated test result and unsigned Release build log: `/tmp/goldfish-natural-pond/DeliveryTests.xcresult` and `/tmp/goldfish-natural-pond/delivery-release.log`.

Signed archive and upload log: `/Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-4/`.
Source commit for this binary: `0f43fa22f83a31f39ec2f3d037d525a4feda8e72`, pushed and verified on GitHub branch `codex/testflight-p0-p1`.


## TestFlight rollout confirmation

On 10 October 2026, App Store Connect confirmed version 1.0 (4) as **Testing** for **Goldfish U18 — External 50**, with one existing tester and 90 days remaining. What to Test was saved, and Automatically notify testers was enabled when submitting through the beta review flow. This is a TestFlight rollout, not a public App Store release.

Build ID: `a88951a3-2563-44e2-a112-07bba24ad48a`.
Proof: `/Users/marcelmeeh/Documents/ChatGPT/Contacts/Goldfish-Releases/1.0-4/screenshots/testflight-build-4-testing.jpg`.

The optional internal-group assignment was not performed: automatic approval review rejected the combined group selection as exceeding the clearly authorized external-testing scope. External distribution completed successfully without changing the internal group.
