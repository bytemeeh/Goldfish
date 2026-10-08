# Goldfish pond refinement — 6 October 2026

This is the current implementation and integration record. Earlier release documents describe their dated verification runs, not the state of this change. Goldfish only; Lines is outside scope.

## Agreed scope

1. Make the entire Pond/List segments respond and avoid redundant graph rebuilds. Diagnose the reported intermittent behavior without claiming an unproven cause.
2. Offer a bounded, local, optional view-switch history in bug reports, with an exact preview and no contact/search content.
3. Replace default direct-contact spokes with a subtle Me-to-pond-outline connector per relevant pond. Keep detailed saved relationships when a branch is explored and a temporary explicit connection path.
4. Keep pond membership independent from relationship type. Require a deliberate relationship choice when adding a connection; never silently relabel personal contacts based on a pond name.
5. Add a coherent daycare sample: You → Adriana (parent/child), Adriana ↔ Riley (friends), Zach and Aaron → Riley (parents), Selma → Adriana (caregiver). Aaron is the exact name. No inferred spouse connection or explanatory personal notes.
6. Protect personal contacts and edited or removed samples when upgrading known demo data. Keep the quality fixture at 50 people.
7. Open and focus a contact's branch within the Pond. Nested expansion keeps the original anchor. Repeated taps do not collapse a branch; Hide is explicit.
8. Dim unrelated context, frame the focused branch, and offer Back to all ponds with camera restoration and retained expansions. Collapse all is separate.
9. Bound focus traversal to opened branches and stop through Me/upstream ancestors; deduplicate shared contacts and handle cycles.
10. Keep inspector actions readable, with appropriate touch targets, Dynamic Type, VoiceOver descriptions and Reduce Motion behavior.
11. Integrate and verify model, scene, feedback, sample preservation, nested expansion and 50-person behavior. Use one simulator at a time and close it after verification.

## Execution and oversight

Cheaper execution agents own separate packages: interaction/feedback; relationship/demo data; graph focus state; and graph rendering/inspector. The orchestrator defines their shared interface, reviews changes and owns integration and verification. Parallel file ownership avoids conflicting edits; rendering follows the agreed state snapshot rather than inventing a second focus model.

## Verification

Completed implementation and review with five cheaper execution/review agents, under orchestrator integration oversight.

- Full Debug simulator suite: **274 tests, 0 failures**.
- After the final connector routing refinement: **70 graph, geometry, disclosure and 50-person tests, 0 failures**.
- Final unsigned Release build for generic iOS devices: **succeeded**.
- `git diff --check`: passed. The existing Xcode project, signing configuration, app version and persisted model schema were not changed. An explicit SwiftData import fixes the list view's model conformance lookup during compilation.
- Executed regression coverage includes nested anchored expansion, shared nodes/cycles, route-only highlights, leaving Pond for List, scope changes, camera restoration, label separation at phone widths, current-outline connector endpoints after zoom, connector retirement after pond deletion, caregiver inverses/search, deliberate relationship selection, report opt-in/history bounds, demo upgrade/deletion preservation, rollback and post-commit reentrancy.
- Simulator render captures were reviewed for the 23-person sample and the 50-person fixture. Label overlap from the five-person Family group was fixed. Connector geometry now refreshes with pond outlines and tries alternate safe entrances around headings.
- Only one simulator was used, with parallel simulator testing disabled. It is shut down and Simulator is closed after verification.

Evidence from this run is in `/tmp/goldfish-pond-integration/`: `FinalTests.xcresult`, `FinalRenderingTests.xcresult`, `final-tests.log`, `rendering-tests.log`, `release-build.log`, `final-overview.png`, and `final-50.png`. Temporary evidence files are not production or support documents and are not committed.

## Remaining verification and release work

The computer-use tool reported that the Mac was locked. Hands-on checks of repeated Pond/List taps, nested navigation, report preview, VoiceOver and large text remain pending an unlocked Mac or a physical test device. Passing model/scene tests and reviewing rendered images do not establish that every device touch is recognized. The history records requests that reach the app; it cannot record a touch that never reaches the button.

These changes are committed to the existing development branch after verification. They have **not** been uploaded as a new TestFlight build. Complete the hands-on checks before distributing this update. Existing personal relationships, including any Friend label in a Family pond, are preserved; membership does not imply a different saved relationship.

## Pond rearrangement follow-up

Long-press a pond title or empty area inside a visible pond, then drag to arrange it. The gesture moves the pond's members, including currently hidden members, with its outline and title. Saved relationships and pond memberships do not change. Contact long-press actions retain priority over pond dragging.

Placements are stored locally for each Me identity and separated between sample and personal graphs. Disclosure and graph refreshes retain the arrangement. Map options includes **Restore automatic layout**, which clears the current graph's saved positions. Cancelling a drag restores its starting position.

This follow-up used three cheaper implementation, test and review agents with parent integration oversight. Final validation: **277 Debug simulator tests passed, 0 failures**, and the unsigned Release device build succeeded. Added regression coverage checks visible and hidden member translation, attached labels/outlines/relationship paths, unchanged other ponds and Me, saved-offset reload, separate personal/sample scopes, invalid coordinates, cancellation after an earlier saved move, and automatic-layout restoration.

The 23-person simulator overview was captured and reviewed. Computer use initially became available, then reported that the Mac was locked before the final long-press interaction check. Hands-on gesture verification remains pending; the automated tests exercise the scene's shared drag implementation. Evidence: `/tmp/goldfish-pond-drag/Tests2.xcresult`, `tests2.log`, `release-build.log`, and `overview.png`. One simulator was used and closed after verification. No new TestFlight build was uploaded.

## My ponds home control — 8 October 2026

This follow-up supersedes the earlier overview connector design: the ordinary Pond overview has no central Me marker and no Me-to-pond-outline lines. The watercolor fish becomes a native **My ponds** home control. Ponds use the available map space instead of reserving a central gap.

Opening a person's branch keeps focus on that person and their connections. **My ponds** clears focus, the temporary path, map search and pond scope, then frames all visible ponds; explicitly opened branches and saved pond positions are retained. **Collapse all** remains the separate action that closes expanded branches. **Your profile** remains available in map controls.

Me is shown in the map when a requested connection path includes the user, with actual relationship lines. Guided lessons may retain the Me marker where needed to explain the starting point. Membership and relationship records are unchanged.

Three cheaper agents implemented scene, control, and regression-test changes under parent review. Review found and corrected latent Daycare/Family overlap, offset-dependent automatic placement, and a repeated-layout bug that stopped treating a marker as an obstacle after its name was hidden. Automatic geometry stays independent of user offsets; expanded ponds retain their slots when returning home.

Regression coverage includes hidden Me visibility, hit testing and search; explicit path endpoints after zoom and pond movement; guided-tour visibility; home and profile return behavior; retained branches and saved offsets; latent pond separation; repeated name placement around every visible marker; duplicate graph entries; compact headings; and ordinary-contact ripple pagination. The earlier accessibility audit's large-text SwiftUI layout, contrast, and non-drag pond-arrangement findings are separate follow-up work; this change does not establish a completed VoiceOver audit.

Final verification: **283 Debug simulator tests passed, 0 failures**, and the unsigned Release iOS-device build succeeded. The 23-person overview, expanded Daycare/Family overview, and 50-person overview were rendered and reviewed. Native control checks covered Pond/List switching, contact-to-Pond navigation, connection reveal, My ponds retaining revealed contacts, and Your profile returning cleanly to My ponds. Direct node taps and explicit path display were also exercised earlier in the integration run; later coordinate-based computer-use clicks returned `noWindowsAvailable`, while native accessibility controls remained usable. Long-press gesture and full VoiceOver checks remain separate pending verification.

Evidence is in `/tmp/goldfish-my-ponds/`: `DeliveryTests.xcresult`, `delivery-tests.log`, `release-build.log`, `expanded-overview.png`, and `overview-50.png`. One simulator was used and closed after verification. No model-schema, signing, or app-version changes were made, and this update has not been uploaded to TestFlight.
