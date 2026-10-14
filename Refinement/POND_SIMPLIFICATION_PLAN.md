# Goldfish pond simplification — 13 October 2026

## Status and authority

Consolidated implementation plan from the Goldfish chat and the approved three-state interface revision. This defines the target behavior; the execution status below records partial implementation, not a verification or release claim. It supersedes conflicting interaction and visibility requirements in POND_FOCUS_IMPLEMENTATION.md and the older goldfish-work/Refinement/POND_DISCLOSURE_PLAN.md; their dated implementation evidence remains historical.

The release checkout already contains uncommitted changes in GoldfishGraphScene, GraphContainerView, GraphLayoutTests and PondDisclosureTests. Preserve and review those drafts before extending them. The last Goldfish chat reports 14 failed assertions within the overview-layout test, two overlap-correction lifecycle issues, and incomplete simulator checks. Reproduce those findings; do not treat the assertion count as 14 independent bugs or older passing runs as validation of today's changes. The last reported TestFlight version is 1.0 (4); verify distribution state when preparing a release.

## Execution status — 13 October, resumed after “go”

Implementation has started with the independently testable data and draft safeguards. The three-state pond redesign is not complete. Checkpoints remain open until their required simulator evidence is recorded; a compiling change is not a passed checkpoint. See the implementation evidence appended to [the audit](APP_CONSISTENCY_AUDIT.md).

The current simulator can render the app and execute native accessibility actions, but coordinate input repeatedly fails with `noWindowsAvailable`, including after reconnecting the control session and raising the window. This is a tool failure, not evidence that pond gestures work or fail. At the final rendered-build check, the Mac was also locked and the tool explicitly required manual unlock. Direct touch/drag, VoiceOver, largest-text and small/large-device gates remain pending. No release is approved by the current evidence.

## Execution status — 14 October

The first implementation of the three browsing presentations is now in the working tree: no default overview card, compact selected panel, selection-only taps, explicit Connections, optional path mode, and one return control. Exploration snapshots track explicit steps, preserve data edits, restore the starting overview, and do not add history for pagination or inspection. Search/List origins are recorded, the scene stays mounted across Pond/List, and interrupted gestures are cancelled when browsing becomes inactive. Settings contains the removed layout/zoom capabilities. Numbered badges, default relationship/age captions, repeated sample banners and duplicate membership text have been removed from the touched surfaces.

All **330 automated tests pass** on the 14 October working tree. This is an implementation milestone, not acceptance of checkpoints 2–4. Simulator access initially allowed inspection of the previous build; coordinate taps still failed. The Mac locked again during testing, preventing visual and interactive review of the new build. See the dated evidence in [the audit](APP_CONSISTENCY_AUDIT.md).

Subsequent header review: compact Pond/List and actions now share a stable row, with scope beneath. Simulator review on iPhone 17 Pro confirmed normal-size selection/expansion/List return and header actions. Largest-text review reproduced and fixed a Connections-label width overflow; the rebuilt selection/expansion/All ponds flow fit the screen. Light and Dark overview renders were inspected. Direct coordinate input still fails with `noWindowsAvailable`; native accessibility activation is not gesture or VoiceOver validation. See the audit's subsequent header evidence and final binary identity. The earlier lock blockers were temporarily resolved for these bounded checks.

The user subsequently chose the People behind indicator and edge swipes between Pond/List. The dot is replaced by up to two backing medallions, retained while any hidden people remain. Right-edge inward goes to List; left-edge inward returns to Pond. Full automated build-5 suite passes 333 tests; direct gesture verification remains pending because tool coordinate input fails. The user also authorized GitHub push and TestFlight upload; see RELEASE_1_0_5.md for actual distribution status, separate from the unfinished acceptance matrix.

Remaining work includes mandatory simulator journeys and their resulting fixes, readable density-driven batching/panning, complete gesture/accessibility and interruption verification, remaining safeguard acceptance flows, clean-store profile triage, and final release preparation. The guided tour still uses its contextual pond switcher; its revised selection/Connections instructions and completion flow need a fresh simulator replay. The legacy profile-home/tour helper remains separate from ordinary All ponds restoration; ordinary browsing uses the new session-origin restoration.

## Product contract: three states

The watercolor, pond composition and restrained movement carry the visual character. Capabilities do not automatically earn controls on the canvas.

| State | Default surface | Conditional surface |
| --- | --- | --- |
| Overview | Search, Add, Settings, Pond/List switch, ponds and named contacts. No permanent inspector or My ponds card. | Recenter only after displacement from overview framing; compact sample indicator when applicable. |
| Contact selected | Selection ring and compact two-row panel: name plus one context line; Connections and More below. One return control. | Open contact and optional path tracing through More; editing and sharing inside contact details. Exact hidden-connection count in the Connections action, such as “Show 3 connections.” |
| Connections expanded | Same compact selection surface, selected branch and its relationship lines; readable surrounding context. | The Connections action becomes Show more while another batch remains. Previous-person navigation uses the same return control. Focused edge label only when it adds useful explanation. |

Two rows describe logical groups, not a fixed height: wrapping and accessibility text may increase height. Panel height follows content. Do not reserve a tall empty footer. Use one source for usable graph bounds so the panel is not subtracted twice. Keep Search/Add/Settings and Pond/List in one stable top-level location across all three states; the selected panel does not repeat them.

These are three browsing presentations, not the complete application state machine. Search, path tracing, editing, loading and error recovery are temporary modes or destinations. Give each an entry, exit and restoration rule; do not add a new permanent canvas toolbar for each mode.

## Interaction and navigation decisions

- Tap selects only. It does not reveal neighbors, collapse a branch, or automatically refit the camera. Keep the selected identity and inspected branch in the usable canvas; if unavoidable panel occlusion requires an adjustment, use the smallest necessary translation, not a new branch zoom.
- Connections explicitly expands. Retain the existing bounded batch of at most four new contacts per action as an upper limit, not a promise to fit four on every screen. Show more uses the same primary-action slot, rather than adding a third action or floating button. Derive counts from unique eligible contacts; do not imply graph distance or unread activity. The action describes the next batch: “Show 3 connections” means three newly visible people, not three edges or three total neighbors. If all eligible neighbors are visible, show a disabled “Connections shown” action; if there are none, show noninteractive “No connections” text beside More. Never open a no-op expansion or force an editing suggestion into browsing.
- Existing identities and reserved positions stay anchored through disclosure. Widen or translate the camera only when required to reveal the new batch. Unrelated ponds do not rearrange during exploration.
- Selection never creates a Back step, regardless of whether the person is a neighbor, ancestor or unrelated contact. Only an explicit Connections action that starts exploration of a different person creates a step. Show more extends that person's current step; repeated activation never creates empty history entries. Do not infer navigation from graph ancestry.
- When starting exploration of B from an existing A branch, save A's exploration view before applying B's expansion. Back restores that view, including A's selection, disclosure and camera. Tapping B alone leaves A's exploration step unchanged; no extra Back is needed to undo an inspection. History is an ordered list of explicit exploration actions, not a reconstruction of relationship paths.
- The first selection captures the current overview as the session origin. All ponds restores that overview's disclosure and camera and clears the exploration session. Preserve exactly what was visible before the session; do not carry newly revealed branches into overview or retain a hidden per-person expansion cache. Reopening Connections starts with the first eligible batch again. Recenter remains a separate conditional action for an overview the user has panned.
- At the first exploration level the single return control says All ponds; deeper it says Back. Search/List entry instead uses Back to return to its saved origin. Browsing restoration never rolls back contact edits, memberships or saved pond moves. Reconcile snapshots against current data: prune deleted identities, retain current saved positions, and minimally adjust framing if the original view is no longer valid. Exact restoration applies only when data, viewport and layout are unchanged.
- Collapse branch, if needed, is secondary under More. Shared contacts remain visible when supported by another open branch or explicit reveal; detached cycles cannot retain themselves. Do not expose a permanent Collapse all control.
- More initially contains Open contact, Show connection path when a saved path exists, and Hide connections when applicable. Put connect, move/change pond, share and delete in contact details or a deliberate editing destination rather than duplicating the entire editor in More. Preserve confirmation, cancellation and Undo safeguards. Long-press dragging remains a shortcut. Do not offer a disabled or misleading path action for a disconnected contact.
- Relationship descriptions belong in the single context line. Pond membership is distinct from a saved relationship and never changes it implicitly. Avoid duplicating name, route and relationship in multiple rows. No permanent relationship captions, ages or symbols beneath every contact.
- Path tracing is an explicit temporary mode from More. Only that mode displays a route or breadcrumbs. While active, the same return slot says Back and exits path mode before navigating people; no additional close/clear control is needed. Selection of a different person also exits path mode. Search may reveal a matching contact and necessary context without automatically enabling a breadcrumb trail. Describe a displayed route as one saved path, not the unique connection or an inferred relationship.
- Disconnected and hidden contacts remain discoverable through Search/List. Tapping a pond title opens a contextual action to Show people in List, scoped to that pond; no permanent per-pond reveal button or fourth canvas panel is required. The selected pond's List empty state provides Add when appropriate. Restore automatic layout remains in Settings; non-drag arrangement remains available through pond management.
- Recenter appears only in displaced overview; Undo only after a reversible edit. Place conditional controls in reserved safe areas, clear of names and selected contacts. Do not accumulate floating controls.
- Gesture instruction belongs in onboarding and replay through Settings. Remove persistent tips, sample banners and repeated ordinary-use instructions; retain a compact truthful sample-mode indicator.

## Safeguards that remain implementation requirements

One coordinated transition owner governs selection, disclosure, history, camera and inspector state. Handle rapid input, interrupted/reversed animation, Back during expansion, Pond/List switching, scope changes and backgrounding without stale edges or stranded nodes. Preserve valid layout and deliberate user positioning across edits, profile return and refreshes. Correct conflicting startup offsets locally; retain corrections across refreshes and clear them deliberately on Restore automatic layout.

Gesture ownership remains stable from touch-down to completion or cancellation. Pond dragging moves only that pond and its members; background dragging pans. Contact crossing changes membership only after deliberate crossing and confirmation, and cancellation restores the original placement. Touch targets remain usable independently of marker size; overlapping targets must resolve predictably rather than selecting the wrong person.

Provide VoiceOver, larger-text, non-drag arrangement and Reduce Motion alternatives through accessible actions, details and Settings. Do not duplicate every action on the ordinary canvas. Debug diagnostics record transitions and gesture routing without contact names, notes or search content. Existing feedback/report preview and opt-in behavior remain intact.

### Cross-screen restoration contract

| Transition | State to preserve | Exit behavior |
| --- | --- | --- |
| Pond → List → Pond | Pond selection, disclosure and camera; active data scope | Switching alone neither expands nor resets. Reconcile any edits on return. |
| Search → contact details → close | Query, filters, results and scroll position | Restore the originating search for ordinary and relationship queries alike. |
| Search/List → Show in Pond | Origin snapshot plus target identity | Enter selected state without automatic expansion/path. At this external root the single return slot says Back and restores the origin. All ponds is available inside More for this case only. |
| Selected contact → details/edit → return | Browsing state and latest saved data | Preserve framing when valid; if the selected person was deleted, return to the most recent valid exploration step or the session origin. |
| Sample ↔ personal | Saved layout separately by scope | Clear transient selection, history, path, search and pending gestures; never restore an identity from the other scope. |
| Background/foreground or interrupted transition | Last valid committed browsing state | Cancel unfinished gestures and settle to a valid state without committing a crossing or edit. |

The external-origin exception avoids adding both Back and All ponds to the canvas. Record the origin in navigation state, not in extra breadcrumb UI. Ordinary canvas exploration retains All ponds at its root.

### Density and accessibility decisions

Four-per-action alone is not a density policy: repeated actions can still make the map unreadable. Layout must evaluate marker/name clearance in the actual usable viewport. Preserve readable scale and positions; prefer panning to the new batch over continually zooming the whole map out. Keep Connections on the pond: when a candidate batch cannot be laid out legibly, try a smaller batch, then pan to the local branch at readable scale. List remains a deliberate alternative under More, never an automatic replacement for Connections. If no readable one-person reveal can be produced, record a reproducible density failure and resolve it before passing this checkpoint; do not disguise it as a successful fallback. Previously visible people are not silently removed merely to fit a new batch. They may move offscreen through panning while remaining disclosed.

Use a minimum 44 × 44 point interaction target for native controls and graph identities, independent of visual marker size. When target areas overlap, provide an accessible named choice rather than an arbitrary winner. Long names may wrap or shorten visually, but selected names and accessibility labels retain the full identity. At accessibility text sizes, prioritize the selected person and local branch; permit scrolling in secondary destinations and the existing List alternative rather than shrinking text or imposing a fixed two-row height.

## Implementation sequence and exit criteria

Order work by consequence: protect saved data and drafts first, stabilize layout and interaction next, then finish copy and redundant-information cleanup. Original P0 numbers remain identifiers, not a claim that every visual defect has the same severity as a data-isolation risk.

| Checkpoint | Bounded work | Required exit evidence |
| --- | --- | --- |
| 0. Close the baseline gaps | Match a fresh simulator build to the checkout/diff; resolve coordinate input; reproduce direct contact taps, pond/background drag, nested exploration and cancellation. Inspect largest text and VoiceOver. Triage A5 using a clean isolated store, not stale review preferences. | Reproduction record distinguishes app defects from tool failures. Existing drafts reviewed individually. Actual gestures exercised in Simulator; no source-only substitute. The proposed journeys below become regression cases, not claims of current behavior. |
| 1a. Protect scope and saved data | A1 eligibility policy across management/forms/organization; A8 truthful load/retry states; A6 truthful reset/export scope and failure handling. Preserve records and existing schema. | Simulator checks of both scope directions, failed reads, profile-only reset confirmation and cancelled/failed export. No hidden-scope mutation or deletion as a side effect. Destructive checks use isolated disposable fixtures only. |
| 1b. Protect editing drafts | A2 shared dirty-state handling for contact, pond, relationship and feedback flows; unchanged forms close directly, changed forms require deliberate discard. | Enter meaningful drafts, try Cancel/Back/swipe, Keep Editing, save and reopen in Simulator. No silent loss, duplicate saves or stale discard prompts. |
| 2. Stable overview and selection | Startup/refresh correction, gesture ownership, names/titles, viewport accounting and compact selected panel. Remove permanent clutter and make tap selection-only in the same change. | Cold launch → select → details → return → refresh works on small/large phones. Direct taps and pond/background drags verified. Panel/overlay geometry tests preserve readable identities. |
| 3a. Complete pond exploration | Explicit Connections, smaller batches/panning, shared/cyclic visibility, Back/All ponds, optional path mode and interrupted animations. | Simulator journeys J1–J3 below pass, including direct node input. Overview restoration and repeated exploration are deterministic. No unverified replacement of Connections with List. |
| 3b. Restore cross-screen context | A3 search/detail/List/pond origins, deletion reconciliation, scope changes and Pond/List switching. | Simulator J4–J5 pass; both ordinary and relationship search restore query, filters and result position. |
| 3c. Verify sharing/import correctness | A9 active membership filters versus exclusion metadata; exercise the existing reviewed export/import flow and verify A6 copy against actual format omissions. No feature redesign. | Simulator review and cancellation; isolated fixture round trip and decoded-file assertions agree with the preview. No automatic send, permission grant or destructive reset. |
| 3d. Align guidance and copy | Complete A4 tour/help and A7 terminology/plurals; remove duplicate membership display in List/details. Update behavioral guidance alongside 2/3a, then finish this bounded consistency pass. | Fresh tour and replay work in Simulator; no removed control is referenced; zero/one/many summaries and accessible labels agree with actual actions. |
| 4. Verify integrated candidate | Run the evidence matrix against the combined final source. Address failures in their owning checkpoint and rerun affected checks. | Required automated, rendered and hands-on simulator evidence is complete. No unresolved required finding; physical-device-only limitations recorded separately. |
| 5. Prepare release | Review final diff, commit reviewed changes, run the required final regression suite and Release build, prepare TestFlight artifacts and verification record. | Source/build identity recorded; mandatory gates passed; prepared/uploaded/verified remain distinct. Upload and notifications require execution authorization, not this planning document. |

Checkpoint 0 blocks declaring the interaction contract validated. Independently authorized data/draft fixes may progress if simulator input is temporarily blocked, but their own simulator gates still apply. Keep one owner of the shared scene; do not parallelize overlapping changes. Each checkpoint must leave a coherent working flow and be reviewable independently.

### Five behavior journeys to prove

| Journey | Actions | Expected result |
| --- | --- | --- |
| J1 Inspect without exploring | Pan overview → select A → select B → All ponds | No connections revealed and no history created by either selection. Restore the captured overview and camera. |
| J2 Explore deliberately | Select A → Connections → select B → Connections → Show more → Back → All ponds | A expansion starts the first step; selecting B alone adds none; B expansion adds one. Pagination adds none. Back restores A's branch; All ponds restores the pre-session overview. |
| J3 Reopen with shared contacts | Repeat J2 with shared contacts/cycles → All ponds → select A → Connections | No duplicate person, no detached-cycle retention, no hidden resume state. A starts from its first batch again; saved data is unchanged. |
| J4 Return to the origin | Search → details → close; then Search or List → details → Show in Pond → Connections → Back | Details preserve search. Pond entry selects only. At the first exploration level Back restores the external origin. Nested exploration requires its own Back first. |
| J5 Interrupt safely | Start expansion → switch Pond/List; begin drag → cancel/background; change sample/personal scope | Valid settled state, preserved scope-appropriate view, no unintended membership change and no identity/history carried across scopes. |

These are proposed behavior checks for the revised implementation. The earlier simulator audit establishes the baseline only; it has not verified these new rules. Use a small interaction prototype or the first working implementation to validate them before building further navigation exceptions.

## P0 traceability

| Original P0 | Primary checkpoint | Observable acceptance |
| --- | --- | --- |
| #1 Opening alignment | 0, 2 | Stable centered opening after data and usable viewport are known, without a late rearrangement. |
| #2 Independent dragging | 2 | Pond-origin gesture moves only that pond; background panning still works. |
| #3 Selection framing | 2, 3a | Selection and panel appearance preserve branch readability; expansion fits only as needed. |
| #4 Compact inspector | 2 | Two logical rows, at most two primary actions, no redundant path or empty panel height. |
| #5 Overlapping ponds | 2 | Titles and identities remain separated after opening, refreshing and returning from details. |
| #6 Contact names | 2, 4 | Every displayed contact remains identifiable in overview and expanded states. |
| #7 Pond titles | 2, 4 | Markers, labels and lines do not obscure headings. |
| #8 Smooth expansion | 3a | No snap, stale edge or half-expanded state after repeated or interrupted input. |
| #9 Readable markers | 3a, 4 | Progressive disclosure protects identity readability and touch targets under crowding. |
| #10 Pond/List switching | 3b | Full segments respond repeatedly during and after interaction; valid exploration state persists. |
| #11 Deliberate pond crossing | 2, 3a | Prompts require deliberate crossing; cancellation changes no membership. |
| #12 Back restoration | 3a–3b | A single return control restores the expected prior person or overview and camera. |

## Review and verification rules

- **Simulator use is mandatory.** Run the app in the iOS Simulator for checkpoint 0 and every subsequent UI/interaction checkpoint, and verify the final release candidate there before checkpoint 5 completes. Exercise the actual flows and inspect transitions, not just static renders. Source review, automated model/geometry tests and physical-device checks supplement simulator verification; none replaces it.
- If simulator launch, display or interaction is unavailable, record the exact blocker and leave the affected checkpoint incomplete. Resolve access and resume the required simulator checks before declaring that checkpoint or the release candidate verified. Continue independent work where possible, but do not waive this requirement.
- Every permanent control supports a frequent task.
- A selected contact has at most two primary actions; secondary actions are under More.
- Information appears once, with one useful context line.
- Selection does not hide or materially obscure the inspected branch.
- Empty space belongs to the pond composition rather than an oversized panel.
- Accessibility alternatives remain available without default-canvas duplication.
- Verify the reported sample/three-pond arrangement, nested/shared/cyclic and disconnected contacts, a crowded pond, many small ponds and the existing 50-person fixture. Include cold/warm launch, delayed data, profile return, edits, background/foreground, rapid taps and interrupted transitions.
- Capture overview, selection, first expansion, deeper Back and returned overview on small/large phones, light/dark and larger text. Inspect transition behavior as well as final screenshots. Use one simulator at a time and shut it down afterward.
- Automated tests establish state/geometry behavior; screenshots establish rendered layout; hands-on checks establish gesture and accessibility behavior. Do not substitute one for another or claim unfinished checks passed.

### Minimum evidence matrix

| Scenario | Automated assertion | Render / hands-on evidence |
| --- | --- | --- |
| Launch, delayed data, profile return and refresh | No double viewport subtraction; stable valid positions and retained correction | Overview before/after on small and large phones, using the reported three-pond arrangement. |
| Selection and pagination | Selection does not change visible IDs; each expansion adds only its truthful batch; stable positions | Selected name and local branch clear of panel; inspect transition start, middle and end. |
| Nested navigation, shared nodes and cycles | Only explicit exploration adds history; parent snapshot restored; shared reachability retained; no data rollback | J2–J3, including overview restoration and fresh first-batch re-entry. |
| Gestures and interruption | Fixed gesture owner; cancelled crossing leaves membership unchanged; interrupted transition settles | Real touch/drag and repeated full-segment Pond/List taps; Reduce Motion variant. |
| Cross-screen and scope changes | Query/origin restored; deleted IDs pruned; no cross-scope history | Search and List → details → Pond → Back; sample/personal switch. |
| Density and accessibility | Batch limit, readable-scale panning and target geometry; deterministic fixture results | Crowded pond and many small ponds; normal → largest text → normal, VoiceOver select/expand/return, light/dark contrast. |
| Data and draft safeguards | Scoped eligibility, failed-save retention, draft dismissal, export metadata and retry cases | Audit A1–A9 flows on disposable data; verify exact warnings and available recovery actions. |

Use representative combinations, not every permutation: run all core flows on the baseline small phone; repeat layout-sensitive flows on a large phone and at largest text; cover light/dark and Reduce Motion in those same flows. Add combinations when evidence exposes a specific risk. Record screenshots/video, fixture, device, settings, source revision plus uncommitted diff identity, and result in one verification record. Installed-build observations remain separate until their source is matched.

Release requires all original P0s and A1 closed, every required checkpoint and A2–A4/A6–A9 complete, and A5 triaged with evidence. If A5 reproduces an ordinary startup/reset failure, it blocks release until fixed. An unavailable simulator or device leaves the relevant gate pending; a passing model test cannot clear it. The subsequent “go” started implementation. This document does not authorize upload or tester notification.

## Scope boundary and ownership

### App-wide additions from the 13 October review

The [app consistency audit](APP_CONSISTENCY_AUDIT.md) records observed screens, source evidence, review limitations and detailed acceptance criteria. Include these bounded fixes alongside the pond work:

The resumed simulator pass on 1.0 (4), iPhone 17 Pro / iOS 26.5, reproduced feedback/batch/pond draft loss, ordinary-search context loss, cross-scope pond edit exposure with misleading zero counts, and reset-label inconsistency. It also exercised selection, explicit expansion and return through native controls. The audit records exact steps and binary identity. Coordinate-based graph gestures and the full release matrix remain pending; do not classify the review fixture's empty production scope as a confirmed clean-install startup defect.

| Finding | Risk / commitment | Checkpoint |
| --- | --- | --- |
| A1 Sample/personal pond eligibility | P0 saved-data isolation; required | 1a; verify management, forms, organization and export together. |
| A2 Unsaved-draft protection | Draft-loss risk; required this release | 1b across editors and feedback. |
| A3 Search return context | Interaction correctness; required this release | 3b, both query types and external pond origins. |
| A4 Tour/help alignment | Behavior dependency; required | Update with 2/3a; verify fresh tour/replay in 3d. |
| A5 Missing-profile/empty-sample recovery | Investigation; startup blocker if reproduced | 0 clean isolated fixture; fix in 1a if confirmed. |
| A6 Reset/export scope and warnings | Saved-data risk; required this release | 1a warnings/failure handling; 3c format/round-trip evidence. |
| A7 Terminology, count grammar and duplicate information | Presentation consistency; required bounded cleanup | 3d, including reproduced “1 people” / “1 ponds.” |
| A8 Failed reads shown as empty data | Recovery correctness; required this release | 1a truthful error/retry and preserved draft/content. |
| A9 Active membership versus export metadata | Sharing correctness; required this release | 3c filter/review/decoded-file agreement. |

Scope extends to these demonstrated consistency gaps, not a broad settings/import/sharing redesign. Keep their acceptance evidence separate from the original twelve P0s. Profile list-context recomputation during density verification; optimize only if the measured result justifies it. Extend accessibility verification to forms and review screens. Documentation-only review has not validated runtime fixes.

Apply the information-once rule narrowly to grouped List rows and contact details as well: remove duplicate visible pond membership where the section header or hero already supplies it. Preserve accessible context and the distinction between membership and relationship. Verify these screens in the simulator after changes.

Include all twelve P0s, state/layout safeguards, the three-state simplification and accessibility/density verification. Preserve existing sample/personal isolation, relationship integrity, feedback, import and sharing. Defer new fish variants, extra ambient motion, gamification, AI features and broader import/sharing redesign.

Keep a single writer responsible for the shared graph scene and its integration contract. Interface changes and independent verification can be separate packages if delegation is later requested. Review and commit each coherent checkpoint separately so unrelated editor or export corrections can be isolated from scene changes. Do not discard existing drafts, introduce a second disclosure owner, change the persisted data schema or broaden feature scope without an evidenced need. Before replacing existing logic, map the contract to the current view model and scene responsibilities; prefer consolidating existing transitions over a wholesale architecture rewrite.

For A2, reuse dirty-state/discard behavior; a new cross-session draft-storage system is outside scope. For A1, preserve existing records and guard inappropriate operations rather than migrating pond ownership in this pass. For A6, clarify and verify the existing export route rather than building full backup/restore. Performance optimization remains evidence-triggered. The original planning pass did not start implementation. Subsequent execution and test results are tracked separately above; no agents or release actions have been started.

## Revision rationale

This revision removes graph-dependent navigation rules and invisible branch-resume state, keeps List a user choice rather than an automatic density escape, moves data/draft safeguards ahead of presentation cleanup, and splits the former oversized Stage 3 into four independently verifiable checkpoints. It adds a blocking simulator baseline for the still-unverified direct gestures and five short journeys for validating the proposed behavior. No additional feature scope is introduced, and no new behavior is claimed implemented or simulator-verified by this document edit.
