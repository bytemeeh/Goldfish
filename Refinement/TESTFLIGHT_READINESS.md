# Goldfish U18 TestFlight readiness

**Prepared:** 28 September 2026
**Decision:** **Not ready to invite external testers.** Developer membership and public support details are active. Distribution signing, App Store Connect setup/upload, physical-device verification, and beta review remain pending. Human testing is planned for the beta; it is not represented as completed.

This document is a release plan and evidence register for the Goldfish iOS beta. It does not certify a build. See `P1_RELEASE_VERIFICATION.md` for engineering checks performed during integration. App Store Connect upload, TestFlight installation, physical-device testing and human usability sessions remain pending. Historical build, test, and screenshot records elsewhere in `Refinement/` remain useful engineering context, but they do not fill the U18 release-rehearsal evidence slots below.

## Current release position

| Item | Current state | Release consequence |
|---|---|---|
| Apple Developer Program membership | **Active — verified 28 September 2026** | Individual membership is active through 28 September 2027. App Store Connect and certificate resources are available. |
| Signing identities | **Development identity found; Xcode account and distribution signing pending** | An Apple Development certificate exists for the Goldfish account (expires 18 February 2027). Signed archive attempts confirm that Xcode has no Apple account configured and no matching provisioning profile. Add the active account in Xcode Settings → Accounts, then allow Xcode to manage signing. |
| App Store Connect app record | **Blocked by App Store Connect Terms of Service** | App creation reached Apple’s Terms of Service gate. The Account Holder must review and accept it before the record can be completed. Planned record: iOS, English (U.S.), bundle ID `app.pond.goldfish`, SKU `goldfish-ios-1`, full access. |
| Source bundle identity | `app.pond.goldfish` | Confirm that this exact explicit App ID is registered to the activated team before archiving. Apple associates uploads using bundle ID, version, and build number, as described in [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds). Keep this Goldfish identifier unchanged so existing local installations retain their data. |
| Source version | `1.0` (`1`) | Treat as a source value, not an accepted TestFlight version. Choose and record the candidate version/build before archive; increment the build number for every new upload. |
| Deployment target | iOS 17.0 | Recruit compatible iPhone and iPad testers and cover the supported OS range in the device matrix. |
| Public support URL | **Live** — https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/ | Verify public access again when submitting the build. |
| Feedback/support email | **Confirmed** — goldfish.pond.app@gmail.com | Configured in `Goldfish/Info.plist` and `project.yml`; use the same address in TestFlight test information. Apple says it is shown to testers and used as the invitation reply-to address in [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information). |
| Hosted privacy-policy URL | **Live** — https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/privacy | Use this exact URL in App Store Connect. |
| External human acceptance | **Pending — no U18 human sessions yet** | Automated checks and prior visual records do not replace the five-task human protocol in this plan. |

Public app copy, screenshots, support pages, and optional App Store metadata use the **Goldfish** brand and support inbox without personal attribution. Apple still uses the Account Holder’s verified legal name as the developer and seller for an Individual membership; changing that platform-provided identity requires conversion to an eligible Organization membership.

## Beta product being offered

The beta should be described as a private, local relationship journal. The current usable feature surface is:

- first-run choice between exploring fictional sample contacts and starting an empty personal pond;
- manual contact creation and editing, including contact details, birthdays, addresses, notes or memories, photos, favorites, tags, and pet identity;
- typed relationships, including directional family roles, with connection removal and short-lived Undo where exposed;
- a visual Pond and an ordered List, pond focus, saved branch disclosure, contact movement between ponds, and an Unassigned state;
- name, contact-field, tag, and relationship-oriented search;
- import from a user-selected phonebook subset or vCard file;
- selective vCard export, with an optional review of the people included and Goldfish metadata for supported connections and pond membership;
- separated sample and personal scopes, with an explicit way to leave sample mode while retaining both sets of data;
- a replayable feature tour, in-app and public privacy information, Dynamic Type layouts, Reduce Motion behavior, accessibility labels/actions, and feedback preparation through user-controlled Mail, Share, or Copy.

The source stores the core journal in the local app database and does not enable CloudKit. There is no Goldfish account, server-backed collaboration, advertising SDK, or analytics SDK in the beta scope.

## Limits that must be stated to testers

- **Location is not implemented as an end-to-end feature.** A person’s address can be stored as text, but the beta does not offer current-location capture, background location access, proximity detection, automatic geocoding, travel tracking, or location-triggered reminders. Model or map scaffolding is not a promise of a working location workflow.
- **AI and voice are not implemented.** There is no AI assistant, generative relationship inference, voice conversation, speech recognition, microphone capture, or voice-note transcription.
- **Local-only storage has local-only recovery.** There is no account or cloud sync. Removing the app can remove its local database. Testers should use fictional or non-sensitive data and export anything they need before deleting the beta.
- **vCard transfer is not a full database backup.** Unsupported app state may not round-trip, and only the reviewed export scope is included.
- **Phonebook import is optional.** iOS asks for Contacts access when that path is used; testers may create contacts manually or use the sanitized beta fixture instead.
- **Reports are user-controlled.** Goldfish prepares a report without sending it automatically. The tester chooses Mail, Share, or Copy; the confirmed support inbox is `goldfish.pond.app@gmail.com`.
- **The beta targets iPhone and iPad on iOS/iPadOS 17+.** Device and OS compatibility must be confirmed by the uploaded build before invitations are sent.

## Draft TestFlight metadata

Keep placeholders out of App Store Connect. Replace every bracketed field before submission.

### Beta app description

> Goldfish is a private relationship journal that helps you remember people, their connections, and the groups—or ponds—they belong to. Explore fictional sample contacts or begin with your own. Goldfish stores its journal locally on your device and does not require a Goldfish account.

### What to test

> Please try first-run setup, adding or importing a fictional contact, creating and removing a relationship, organizing people into ponds, Pond/List navigation, relationship search, and scoped vCard export. Check that sample contacts never appear in your personal scope. If you use larger text, VoiceOver, or Reduce Motion, tell us where an action becomes unclear or unreachable. Location, AI, and voice features are not part of this beta. Use TestFlight feedback for screenshots and observations; do not enter sensitive personal information.

### Beta review notes

> No sign-in is required. On first launch, choose “Explore a Sample” for fictional data and the guided tour, or “Start My Pond” for an empty personal journal. Contacts permission is optional and used only when the reviewer chooses phonebook import; every core contact can be created manually. There are no purchases or subscriptions. Location capture, AI, and voice are not implemented.

### Metadata values and remaining owner details

- Feedback Email: `goldfish.pond.app@gmail.com`
- Public support URL: `https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/`
- Privacy Policy URL: `https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/privacy`
- Beta review contact name, phone, and email: **[PENDING]**
- Planned primary language: English (U.S.); planned SKU: `goldfish-ios-1`.
- Category, age rating, review phone number, and any required legal seller details: **[PENDING OWNER ENTRY]**

Apple requires a beta description and feedback email for external testing, and permits beta information to differ from later App Store metadata; see [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information). Apple also recommends a clear “What to Test” entry when adding a build to a group; see [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## Fifty-person external-test plan

Use one controlled external group named **Goldfish U18 — External 50**. Prefer named email invitations for the core study so completion and follow-up can be reconciled. If recruitment requires a public link, cap it at 50 and disable it when full; Apple supports public-link tester limits and device/OS criteria, but public-link testers appear anonymously. The mechanics and privacy tradeoff are documented in [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

Recruit 50 unique testers across these primary cohorts:

| Cohort | Count | Primary coverage |
|---|---:|---|
| New relationship-journal users | 10 | First-run comprehension, personal versus sample choice, basic contact creation |
| Contact-transfer users | 10 | Contacts permission, sanitized vCard import, duplicate messaging, scoped export |
| Dense-network users | 10 | Directional roles, multiple ponds, branch disclosure, search, editing and Undo |
| Accessibility users | 10 | VoiceOver, large accessibility text, Reduce Motion, Switch Control or equivalent needs represented where recruitment permits |
| Device/OS and privacy edge cohort | 10 | Compact and large iPhones, supported OS spread, denied permissions, local-data expectations, recovery messaging |
| **Total** | **50** | |

The cohorts identify primary coverage; participants may contribute to more than one dimension, but each person counts once. Before invitations, record a matrix that includes iPhone size class, iOS version, accessibility settings, invitation method, and assigned onboarding path. Do not collect unnecessary personal or address-book data for this matrix.

### Staged invitations

1. **Internal prerequisite — not part of the 50:** after account activation, complete the technical rehearsal with a small App Store Connect internal group. External testing cannot begin from an unproven upload. Apple requires an internal group before an external group and subjects the first external build to TestFlight App Review; see [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
2. **Wave A — 10 external testers:** one or two people from every cohort. Run the five tasks below and hold expansion until all launch, privacy, data-loss, and support-routing findings are triaged.
3. **Wave B — 15 additional testers, 25 cumulative:** broaden device/OS and accessibility coverage. Repeat the full task protocol and run the update-install subset after a replacement build if one is needed.
4. **Wave C — 25 additional testers, 50 cumulative:** confirm fixes and measure the final task criteria across the full cohort. Keep automatic notification off until each wave is intentionally released.

TestFlight supports up to 10,000 external testers, but this plan intentionally limits the beta to 50. Apple notes that the first build submitted for external testing requires review, later builds for the same version may not, and only one build of a version can be in review at a time. Apple also limits a build’s testing availability to 90 days; see the [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) and [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## Five-task human usability protocol

**Status: pending. No participant result exists yet.** Run this protocol on the actual approved TestFlight build, with fictional data. Do not coach unless the participant explicitly asks for help. Record completion, time, wrong turns, requested hints, observed errors, and a 1–7 Single Ease Question after each task. Ask participants to submit a final TestFlight note or screenshot; Apple exposes TestFlight sessions, crashes, and feedback in App Store Connect, as described in the [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

Randomly assign 25 testers to begin with **Explore a Sample** and 25 to begin with **Start My Pond**. Everyone should later switch to the other context and confirm that sample and personal people remain separated.

| Task | Participant prompt | Task-level acceptance criterion |
|---|---|---|
| 1. Choose a safe starting context | “Open Goldfish. Start in the context assigned to you, then explain what data you expect to see and how you would leave the sample.” | At least 45/50 choose the assigned path without a hint; 50/50 encounter no sample records in personal scope; at least 45/50 correctly explain sample versus personal data after the task. |
| 2. Add or import a person | “Add a fictional person with one useful detail and place them in an appropriate pond.” Transfer-cohort participants use the supplied sanitized vCard or a deliberately created test contact; others add manually. | At least 40/50 complete without intervention and can reopen the saved detail; no imported record appears in the wrong sample/personal scope; denial of Contacts permission leaves a usable manual path. |
| 3. Build and reverse a connection | “Connect two fictional people with the requested relationship direction. Remove that connection, use Undo, and confirm both people remain.” | At least 40/50 complete without intervention; every successful Undo restores the same endpoints and relationship role; zero observed contact deletions or duplicate connections caused by Undo. |
| 4. Organize and find the network | “Move a person to a named pond, focus that pond, find the person or relationship using search, inspect the connected branch, then return to all ponds or the List.” | At least 40/50 complete without intervention; saved membership remains correct after navigation; accessibility-cohort participants encounter no unreachable required control. |
| 5. Review and export a safe scope | “Select one fictional person for export, review who will be included, cancel once, then export and share or save the vCard without sending private data.” | At least 40/50 correctly predict the export scope before final export; Cancel creates no intended handoff; exported scope contains no unselected unrelated personal person. Each participant can identify TestFlight feedback or Goldfish Share/Copy as a reporting route. |

### Overall human acceptance gate

These are proposed post-beta acceptance targets, not prerequisites for inviting the first testers. Begin with a five-person moderated pilot (one participant using accessibility settings), then use the following targets to evaluate the 50-person cohort:

- all five task-level criteria pass;
- at least 40 of 50 testers complete the entire protocol and at least 45 install and launch the build;
- median Single Ease Question score is at least 5/7 for every task;
- no open P0 issue (launch failure, privacy boundary breach, unrecoverable data loss, security issue) and no open P1 issue that blocks a core task without a safe workaround;
- all 10 accessibility-cohort participants can complete the five tasks with their assigned settings, with no unlabeled or unreachable required action;
- the update subset retains its fictional personal contacts, relationships, and pond membership after installing the next TestFlight build;
- sample/personal isolation has zero observed failures;
- every crash and data-integrity report is reconciled to a build, device/OS, reproduction status, and disposition.

Failure of any criterion holds expansion or release. Automated tests may support diagnosis, but they do not convert a failed or missing human criterion into a pass.

## Deployment staging sequence

Proceed in this order:

1. Confirm the Account Holder can access Certificates, Identifiers & Profiles and App Store Connect; accept any pending agreements.
2. Use Team ID `VL6L6N34D5` and the registered explicit App ID `app.pond.goldfish`, then create the matching App Store Connect app record after the Account Holder accepts the pending terms.
3. Configure Xcode signing for the activated team and create or obtain the Apple Distribution identity and App Store Connect provisioning profile. Automatic signing is acceptable if the owner chooses it; Apple explains the distribution-profile options in [Create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).
4. Confirm the candidate source revision, release configuration, version/build number, app icon, display name, iOS 17 target, Contacts usage string, empty entitlements, and privacy manifest. Resolve every intentional release difference before archive.
5. Keep the confirmed feedback email and published support/privacy URLs in both source configuration locations, and enter the final TestFlight metadata. Confirm the inbox is monitored before any invite is sent.
6. Produce a Release archive, validate it, and upload through Xcode or another Apple-supported route. Apple notes that a newly uploaded build must finish processing before it appears in App Store Connect; see [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).
7. Resolve export-compliance questions, processing warnings, privacy declarations, and beta review information. Create an internal group and install the processed build on supported physical iPhones.
8. Complete the internal technical rehearsal below. Fix blockers with a new build number and repeat the archive/upload/install path.
9. Create **Goldfish U18 — External 50**, add one approved build, enter “What to Test,” submit the first build to TestFlight App Review, and wait for approval before inviting Wave A.
10. Release the three waves only at their gates. Monitor TestFlight sessions, crashes, and feedback; stop testing or expire a build immediately if a P0 issue is confirmed.

## Internal technical rehearsal

The rehearsal must use the same processed build intended for Wave A on at least two physical iPhones representing different supported screen sizes and OS versions. Record evidence for:

- invitation acceptance, TestFlight installation, first launch, and update installation;
- both onboarding choices and clean switching between sample and personal scopes;
- manual creation, optional Contacts denial, sanitized vCard import, connection create/remove/Undo, pond movement, search, and scoped export;
- large accessibility text, VoiceOver reading/action order, Reduce Motion, and orientation/foreground-background restoration;
- local data retention across an update and explicit behavior after uninstall/reinstall;
- feedback through TestFlight plus Goldfish Share/Copy; direct Mail only after the confirmed inbox is configured;
- offline launch and core local editing, followed by reconnection for TestFlight feedback or user-directed sharing;
- crash and console review tied to the exact uploaded build.

This rehearsal is a deployment exercise, not a substitute for the 50-person protocol.

## U18 evidence register

Every row is a placeholder. Change a state to **Complete** only after attaching evidence from the exact candidate build.

| Evidence item | Required artifact | State |
|---|---|---|
| Membership activation | Apple Developer account confirms Individual membership, program resources, and renewal date | **Verified 28 September 2026** |
| Agreements and roles | Account Holder confirmation and App Store Connect role list | **Pending** |
| Signing identity | Xcode signing-team view or redacted certificate inventory showing valid Apple Distribution identity | **Pending** |
| Explicit identifier | Developer portal record for `app.pond.goldfish` | **Verified 28 September 2026** |
| App Store Connect record | App name, Apple ID, SKU, bundle ID, primary language, category, age rating | **Pending** |
| Support endpoints | Public support URL, public privacy URL, monitored feedback email, owner approval, and access-date record | **Verified publicly with HTTP 200 on 28 September 2026** |
| Candidate manifest | Source revision, clean/known worktree statement, version/build, Xcode version, SDK, archive timestamp | **Pending** |
| Archive and validation | Xcode Organizer archive identifier plus complete validation output | **Pending** |
| Upload processing | App Store Connect build page, processing result, warnings, export-compliance answer | **Pending** |
| Privacy metadata | Final App Privacy answers reconciled with the binary and published privacy policy | **Pending** |
| Internal install | Device/OS matrix, install/update results, launch result, rehearsal notes | **Pending** |
| Accessibility rehearsal | VoiceOver, accessibility text, Reduce Motion observations on the processed build | **Pending** |
| TestFlight metadata | Final beta description, What to Test, review notes, feedback email, review contact | **Pending** |
| Beta App Review | Submission timestamp, status history, approval or resolved rejection notes | **Pending** |
| External group | Group settings, invitation method, tester cap 50, device/OS criteria, notification policy | **Pending** |
| Wave A | Invitation/install counts, five-task results, findings and gate decision | **Pending human testing** |
| Wave B | Cumulative counts, five-task results, update subset, findings and gate decision | **Pending human testing** |
| Wave C | Final 50-person matrix, acceptance calculation, unresolved issues and decision | **Pending human testing** |
| Stop/rollback drill | Named owner and recorded steps to stop testing, expire the build, notify testers, and preserve issue evidence | **Pending** |

## Go/no-go gates

- **Upload gate:** membership active; agreements accepted; explicit identifier and app record confirmed; valid signing available; candidate revision/version/build recorded; support email and URLs confirmed; archive validation complete.
- **External-review gate:** processed internal build installed on physical devices; technical rehearsal complete; privacy/export-compliance metadata reconciled; beta description, What to Test, feedback email, and review contact complete.
- **Wave A gate:** first external build approved by TestFlight App Review; no open internal P0/P1; support inbox monitored; recruitment matrix prepared.
- **Wave expansion gates:** preceding wave meets its task thresholds, every crash/data-integrity report is triaged, and no open P0/P1 remains.
- **U18 acceptance gate:** all overall human criteria pass and every required evidence row is complete or explicitly waived by the release owner with a written reason.

Until those gates are evidenced, Goldfish U18 remains a beta candidate rather than a distributable or human-accepted release.
