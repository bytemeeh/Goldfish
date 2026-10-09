# Goldfish TestFlight readiness

**Prepared:** 9 October 2026

The release candidate has passed the current simulator test suite, and distribution signing is available. App Store Connect could not be checked because the Chrome session had expired and is awaiting account sign-in. No current ASC upload, review, TestFlight group, or processed-build state is claimed here. The source and signed archive declare version 1.0, build 3. The device archive and local App Store export succeeded.

## Verified for this release pass

| Item | Evidence / current value |
|---|---|
| Automated checks | 315 tests passed. Result bundle: `/tmp/goldfish-release-2026-10-09/ReleaseCandidateTests.xcresult`. |
| Distribution signing | Valid Apple Distribution identity and `Goldfish App Store 2026` provisioning profile; profile expires 2 October 2027. Team `VL6L6N34D5`; bundle ID `app.pond.goldfish`. |
| Bundle ID / team in source | `app.pond.goldfish` / `VL6L6N34D5`. |
| Current source version | 1.0 (3), confirmed in source and signed archive. |
| Support page | `https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/` — HTTP 200 via curl on 9 October 2026. |
| Privacy page | `https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/privacy` — HTTP 200 via curl on 9 October 2026. |
| Feedback email | `goldfish.pond.app@gmail.com`, configured in `Goldfish/Info.plist` and `project.yml`. |
| TestFlight audience | The intended audience is approximately 50 testers; the actual existing tester count is unverified. Current group membership, build access, and notifications need an ASC check before rollout. |

The browser sign-in is the only known access blocker to confirming the current ASC state. After sign-in, check the existing app record and group; do not assume the historical app-creation/Terms-of-Service notes remain true. `get_site` and credential lookup both returned `NOT_FOUND` for site `appgprj_6ab957fad0048191856ed604429fdadd`. Do not edit or publish hosted source from this workspace. Ready-to-apply page copy is in [SUPPORT_SITE_UPDATE.md](SUPPORT_SITE_UPDATE.md).

## Product facts for release copy

Goldfish is a local relationship journal. It supports manual contact records, typed relationships, Pond and List views, pond membership, search, optional phonebook/vCard import, vCard export, and selected-contact `.goldfish` sharing/import. The `.goldfish` review screen shows people, relationship and pond counts, pond names, and whether notes are included. A bundle can include contact details, photos, saved locations, relationships between selected people, and pond memberships for selected people. It is a user-directed file copy, not synchronization. Existing contact details and pond assignments are preserved on import; missing details may be added. See `Views/GoldfishShareImportView.swift`, `Services/GoldfishContactBundle.swift`, and `Views/ContactExportSelectionView.swift` for precise behavior.

Contacts are stored in the local app database. The app does not enable CloudKit, require a Goldfish account, or include advertising or analytics SDKs. Phonebook access is optional and selected by the user. MapKit can display saved locations, but Goldfish does not provide location tracking. The five named welcome-motion variants are DEBUG-only preview choices. Production onboarding uses the default Swift Current transition (1.8 seconds); Reduce Motion uses a short fade. The Pond uses a faint watercolor background in light appearance and a faint koi watermark in dark appearance.

Avoid old package claims about iCloud sync, a live contact map/proximity feature, background location, analytics labels, or “Data Not Collected” unless the shipped binary and App Store privacy questionnaire support them. Hosted policy pages returned HTTP 200, but their contents still need the `.goldfish` sharing details in `SUPPORT_SITE_UPDATE.md` applied and reviewed.

## TestFlight copy

The current beta description, What to Test, and review notes are in [AppStore_Submission_Package.md](../AppStore_Submission_Package.md). Use the existing tester group first. Add the candidate build to that group once it has processed and any required first external-build review is approved. Apple says TestFlight requires beta description and feedback email; see [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information). Testers can be added to a build through an existing group; see [Add testers to builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds).

Do not create a replacement group or invite new testers unless the current audience needs expansion. Record the actual group, eligible tester count, current build, and notification state from ASC.

## Remaining release work

- Restore App Store Connect access, confirm existing app record, agreements, current TestFlight group, and tester count.
- Commit and push the verified build 3 source revision.
- Archive and local App Store export succeeded. Complete upload, confirm build processing, and resolve Apple’s export-compliance questions.
- Enter or verify TestFlight metadata and current App Review contact details. Send the processed, approved build to the existing tester group.
- Review the actual hosted support and privacy page contents after the additions in `SUPPORT_SITE_UPDATE.md` are applied.
- For public App Store release, finish the App Privacy questionnaire, category, age rating, copyright, screenshots, localization, and store listing fields in App Store Connect. Use only screenshots of current app behavior.

No fixed two-device rehearsal, 50-person usability threshold, or phased recruitment schedule is an upload prerequisite. Test the processed build with the existing audience and resolve any release-blocking issues found before public release.
