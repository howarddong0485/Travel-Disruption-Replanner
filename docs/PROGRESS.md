# Project progress

## Current status — 2026-11-01

Use [MVP_STATUS.md](MVP_STATUS.md) for the P1–P5 implementation gaps,
contribution attribution and remaining delivery gates. The connected code baseline
`83fee96` passed [GitHub CI](https://github.com/howarddong0485/Travel-Disruption-Replanner/actions/runs/41315449524):
387 tests, four app checks, two client builds, the sealed package and both
source/package HTTP/CLI checks. The howarddong stack is delivered; source-PR coordination, cross-owner contract confirmation and the remaining role features stay open.

The dated sections below are historical verification records. Their old runtime,
build failures and incomplete integration describe those earlier revisions; use
the status page and [verification guide](LOCAL_VERIFICATION.md) for current results.


This report separates delivery on `main` from implementations still under review. Dated verification records identify the code, runtime and scope that were actually checked.

## Person 3 publication verification — 2026-11-01

The current mock-MVP Person 3 implementation and local engineering checks are
complete on the #36 review branch. The full `scripts/setup.sh` and
`scripts/verify.sh` sequence passed again in the current checkout using Jac
0.37.23: **387 tests**, **four application checks**, **two client builds**, the
3/5/5 planning scenarios, a complete sealed package, and both source/package
HTTP and CLI checks. Acceptance stores the reviewed candidate; rejection keeps
active items unchanged. The sealed runtime ran outside the checkout with source
compilation forbidden.

This repeat run is separate from the clean source-only installation recorded on
October 30. Shared-owner contract approval, source/stack review and merge remain
delivery gates. The GitHub workflow is included in this follow-up; its actual
hosted result must be recorded separately. No live integration is claimed.

## Local clean setup, sealed package and runtime verification — 2026-10-30

The local follow-up to #36 resolves the engineering blockers using the pinned
Jac **0.37.23**, without changing the shared feature contracts or imported owners'
modules. These follow-up changes are part of review PR #36 and remain unmerged.

- `scripts/setup.sh` verifies the official binary checksum, creates an independent
  Python 3.14 venv, and installs declared development/client dependencies.
- `scripts/build_jab.jac` corrects the upstream sealer's precompiler working
  directory. We traced the same-named class errors to original-checkout versus
  staged-copy paths. All type checks and JIR/manifest validation remain enabled;
  no installed runtime files are edited. Raw `jac build travel` still requires
  this project compatibility entry point on 0.37.23.
- A read-only root `application_info` export ensures the sealed entry has server
  bytecode. The CLI now explicitly supplies creation IDs, fixing bridge defaults
  that were still missing under 0.37.23. Existing server defaults are unchanged.
- A fresh source export, with no `.jac` or copied dependencies, completed the
  actual setup and verification scripts on macOS arm64/Python 3.14.7:
  **387 tests**, **four app checks**, **two client builds**, three planning CLI
  scenarios, and a sealed **46-module manifest** all passed.
- Source and packaged non-development servers passed root/asset, comparison,
  rejection/no mutation, exact acceptance/version and CLI new/add/show checks.
  The package ran outside the checkout with source compilation forbidden. The
  earlier homepage 404 was not reproduced in either clean environment.
- Packaged-browser verification rendered the connected options and accepted the
  gallery alternative, saving the expected USD 375 total without console errors.
- `.github/workflows/jac.yml` runs the same scripts on Ubuntu 24.04 with pinned
  action commits and retained logs. A successful actual GitHub-hosted run must
  be recorded separately from these local checks.

See [reproduction and packaged run commands](LOCAL_VERIFICATION.md) and the
[shared contract review packet](CONTRACT_REVIEW.md). Owner approval, source/stack
PR merges and the remote CI record remain delivery gates. This is still a
synthetic mock MVP, not a public multi-user deployment or live-provider result.

## Connected backup planning — 2026-10-30

Work on `codex/connected-backup-planning`, stacked on the candidate-selection
branch, now connects Person 1's profile,
mandatory-filter and budget implementations, Person 2's policy/risk analysis,
Person 3's alternative generation, Person 4's versioned proposal transaction,
and a deterministic comparison/acceptance UI in Roam. Source commits and the
proposed shared contract are recorded in [the integration guide](../travel-planner/planning/README.md).
Tracked in #34 (integration) and #33 (candidate selection). Publishing these
branches does not merge upstream PRs or establish team-wide approval of the
proposed contract. Parent #11 remains open for review and delivery.

- Ten detected/reported risk categories can produce up to five alternatives,
  including different venues/providers, rescheduling, and connected changes to
  multiple itinerary nodes. Search is bounded to eight affected nodes and 256
  combinations. Each complete itinerary is checked with P1 and P3 validators.
- The shared contract carries the saved trip version, content identity, evidence
  deadline, validation, changed nodes and deterministic comparison. Acceptance
  refreshes inventory and revalidates before applying P3's actual candidate in
  P4's existing transaction. Rejection leaves the itinerary unchanged. Retries,
  reviewed proposals, trip edits and changed provider facts cannot restore an
  obsolete selectable proposal.
- Original/proposed totals include reserve. Retained payments count once;
  potential cash refunds, credit and confirmed refunds remain separate. Quotes
  are not presented as cash due now. Missing facts and uncertain cancellation
  liability remain unresolved. An optional model only selects supplied validated
  IDs, with deterministic fallback.
- The normal **Backup plans** page and **Try connected backup plans** entry use
  the connected flow. The earlier guided demo explicitly retains its legacy
  inventory. Imported owner modules are preserved at the documented PR heads.

Verification uses the manifest-pinned **Jac 0.37.23**, the working local venv,
temporary test databases, and isolated browser-demo SQLite files:

- Full service, backup, planning, profile, filter, budget, schema, policy and risk
  regression: **387 passed**. The previously failing MockLLM test passes after
  installing the project's declared development capabilities.
- Static checks: **four application entries passed**. The Roam and standalone
  backup client builds pass. The CLI demonstrates three weather choices, five
  arrival-delay choices, and five connected two-node closure alternatives.
- Development-browser checks cover comparison, rejection and replacement,
  transactional acceptance, requirements that disable acceptance, and a 390px
  layout. No real provider, model, booking, payment or cancellation is exercised.

This implementation record preceded the clean setup/packaging follow-up above.
That follow-up adds a verified project build command and clean non-development
source/package checks; GitHub-hosted CI and public deployment remain unverified.
Restart after backend edits in development mode because HMR may retain imported
modules. The dated records below describe earlier standalone slices and retain
their original verification limits.

## Backup candidate selection and backfill — 2026-10-29

Local work on `codex/backup-candidate-selection`, based on `5e8604c` from the
workflow stack, extends Gehao Dong's module-owned search and refresh flow.
At this October 29 checkpoint the slice had not been committed or pushed.
Its publication and the subsequent integration are tracked in #33 and #34 above.

- The workflow evaluates four supported candidates per scenario before selecting
  up to two Plan B/C cards. Rejected and failed-provider options can be replaced
  by other fully evaluated candidates; hard requirements are never relaxed.
- Passing options precede received but unresolved options. Selection preserves
  search order within each group; it does not optimize or rank by price.
- One/no-option outcomes have explicit messages. All evaluated candidates and
  selection decisions are saved; normal demo pages continue to hide diagnostics.
- Older history remains readable. Validator-version checks prevent old-policy
  retries from restoring current results. Saved trips are unchanged.

Jac 0.37.21: **117 passed, 1 existing replanning MockLLM failure**, with all 12 new
tests passing. Four app checks, the standalone client build and eight CLI
observations pass. Browser verification covers backfill, no solution, saved-trip
unknowns, diagnostic history, default presentation and a 390px layout. The full
Roam build, pinned Jac 0.37.23 and shared team integration are not established by
these checks. See [SELECTION.md](../travel-planner/backup/SELECTION.md).

## Unified backup workflow and demo presentation — 2026-10-29

Gehao Dong's `codex/backup-workflow` branch extends the unmerged storage/history
stack (#30 → #31). It is separate from delivered `main` at `06009b1`.

- Sample and saved-trip inputs now share search, initial validation, refresh of
  the same provider IDs, revalidation, immutable saving and rendering.
- Saved-trip mapping keeps missing traveler/timing/quote/route facts unresolved.
  Per-trip history namespaces, expected revisions, retries and content checks
  prevent obsolete observations from becoming current after trip edits.
- Plan B/C explain original/proposed totals, cost differences, budget remaining
  and elapsed-time changes when supported. History preserves recorded values.
- The normal website and guided demo omit developer check logs, history,
  inventory IDs, raw source URIs and fault-injection controls. They retain the
  alternatives, cost/time comparison, concise failure/uncertainty messages and
  simulated-inventory label. Diagnostics require the standalone app's explicit
  `?diagnostics=1` URL. Returning to the plain URL restores normal inventory.

Jac 0.37.21 regression: **105 passed, 1 existing replanning MockLLM failure**,
including all 25 new metric/history-compatibility/workflow tests. Four app checks
and the standalone backup client build pass. The known full-travel generated
`replan/frontend.js` build blocker was last reproduced on October 28; full Roam
browser success, pinned Jac 0.37.23 and clean-install CI are not claimed.

Issue #11 remains open for shared contracts and downstream handoff. This branch
does not merge the existing draft PRs or change the active itinerary. See
[WORKFLOW.md](../travel-planner/backup/WORKFLOW.md) for demo/diagnostics instructions,
storage boundaries and the detailed verification record.

## Backup refresh delivery — 2026-10-28

Gehao Dong's next standalone slice adds synthetic inventory refresh and stale-result
invalidation on top of main `fc118b0`, preserving the guided workflow from PR #25
and the ownership update from PR #26. The sample panel remains in **Backup plans**
under **Explore validation with a sample trip**.

- Price increases, one/both alternatives sold out, expired evidence and one/both
  provider failures trigger fresh whole-itinerary checks. A fresh observation can
  recover a candidate; previous passing quotes are never a fallback after failure.
- The sample date stays fixed. Input changes, refresh and evidence expiry clear
  old results. Core refresh never renews retained trip/risk evidence; the demo
  separately supplies fresh synthetic fixtures. Missing facts remain unresolved.
- Reports include observation IDs, evidence fingerprints and validity deadlines.
  These are transient fixture results, not persisted or authoritative trip versions.
- Saved trips remain unchanged. The existing preview calls keep their behavior;
  the same validation component also runs as the independent `backup_refresh` app.

Verification after rebasing onto `fc118b0`, with local Jac **0.37.21**:

- `jac check --nowarn`: all four application entries passed.
- Combined service and backup suite: **64 passed, 1 failed**, including all 16 new
  refresh tests and the guided-demo regression. The remaining failure is the
  existing replanning MockLLM selection test at `server/main.test.jac:217`.
- `jac build backup_refresh --as client`: passed. `jac build travel --as client`
  still fails on the generated computed key in `replan/frontend.js`.
- Before the rebase, standalone browser checks verified all inventory modes,
  recovery, input-change clearing and invalid-budget errors. This delivery does
  not claim a successful full-Roam browser run or a pinned 0.37.23/clean-install CI run.

See [the refresh guide](../travel-planner/backup/VALIDATION.md#refreshing-synthetic-inventory)
for commands and precise scope. This is partial progress on issue #11: shared
risk/profile/validator/ledger integration, persistence, live inventory and downstream
handoff are not delivered by this change. The dated records below remain historical.

## Jac migration verification — 2026-10-24

The migration based on `20505d5` converts all eight project-owned Python files to Jac: the standalone validator, records, fixtures, CLI and tests, plus the disruption simulator, mock inventory and replanning engine. Module paths and service signatures are preserved. The 26 validation cases now run with `jac test backup/test_validation.jac`. Python standard-library imports remain supported through Jac.

Verified with local Jac **0.37.21**, using an isolated temporary runtime cache and Postgres test instance:

- `jac check --nowarn`: all three application entries passed.
- The combined Jac suite (`server/main.test.jac`, `server/test_backup.jac`, `server/test_validation.jac`, `backup/test_planner.jac`, `backup/test_validation.jac`): **47 passed, 1 failed**. Both HTTP backup integration tests passed; their test databases are temporary.
- The remaining MockLLM selection failure was reproduced in the unchanged `20505d5` snapshot: its original Jac suite had **21 passed, 1 failed**, and its Python validation suite had **26 passed**.
- Compared complete serialized results for seven scenarios, two profiles and five budgets: **70 of 70** matched the original Python implementation, including check messages, costs, proposed items and snapshot fingerprints.
- `jac build travel --as client` still fails on the generated computed dictionary key in `replan/frontend.js`. The unchanged snapshot produced the same error at the same generated statement. This migration does not establish a successful client build or browser verification.

The manifest still pins Jac 0.37.23; that version was not available for these checks. The dated records below describe earlier implementations and commands.

## Progress snapshot — 2026-10-21

- **Delivered on main:** the October 13 baseline `0bb9bfff` includes the Roam foundation, read-only backup previews in [PR #15](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/15), the business theme in [PR #21](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/21), and standalone mock replanning in [PR #19](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/19). On October 21, main advanced to `6526fc5`, incorporating PR #23 and its progress documentation.
- **New since the Week 3 report:** [PR #23](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/23), implementation commit `e7c9d76`, adds standalone full-itinerary backup validation and is now merged. It partially implements [issue #11](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/11); the parent issue remains open.
- **Other work under review:** [draft PR #16](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/16) contains proposed policy/risk contracts and logic, including an October 14 change making PolicyAgent LLM extraction opt-in. [PR #22](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/22) contains a draft traveler-profile contract, fixtures and structural checks. Neither is merged or an agreed shared integration.
- **Open issues:** #5, #7, #8, #10, #11, #12, #13 and #18. There are no newly completed issues beyond the Week 3 delivery recorded above.

### Standalone backup validation in PR #23

The independent validator checks each synthetic replacement in the full proposed itinerary: mandatory dietary/pet/child/accessibility requirements, budget including reserve and retained original payments, scheduling, opening windows, timezones/DST, transfers, dependencies, and fixed/completed items. Missing or expired evidence remains unresolved. A passing result is explicitly `passed_fixture_checks` with `standalone_fixture` scope.

Seven sample scenarios, family/solo profiles, a CLI and a read-only Roam validation lab are implemented. Input changes and evidence expiry invalidate displayed results. Saved trips are not changed. See [the validation guide](../travel-planner/backup/VALIDATION.md) for commands, semantics and remaining integration work.

Fresh checks on October 21:

- `python3 -m unittest backup.test_validation -v`: **26 passed**.
- Rain scenario, USD 450 budget: Plan B passes the implemented fixture checks at USD 440; Plan C is invalid at USD 470.
- Delayed-arrival scenario, USD 400 budget: Plan B passes at USD 395; Plan C is invalid at USD 425.
- Missing-evidence and expired-evidence scenarios return `needs_validation` for the affected candidate, with unknown total cost.
- Jac tests, client build and browser checks were not rerun. Even `jac --version` failed during launcher initialization with `could not publish the extracted runtime`.

The October 17 PR record remains the earlier Jac verification boundary: Jac 0.37.21 passed all three app checks; the combined suite had 21 passes and one existing replanning LLM failure; the client build failed in generated replanning JavaScript. Both failures were also reproduced on the then-current base main. These results do not establish a successful current full-app build or pinned-runtime verification.

Issue #11 remains open for shared RiskFlag/profile/authoritative-validator/ledger integration, dynamic inventory/provider-failure refresh, versioned persistence and downstream handoff. PR #23 landed on main on October 21. The recorded full-app validation blockers remain unresolved; merging the implementation does not establish successful Jac tests, a client build or browser validation.

## Completed planning and design

- Defined six core capabilities: constraint-aware planning, risk and cancellation awareness, proactive backups, dependency-aware replanning, alternative comparison, and traveler review/control.
- Documented agent responsibilities, deterministic orchestration, shared data contracts, validation, and replanning in [ARCHITECTURE.md](ARCHITECTURE.md).
- Defined MVP boundaries, acceptance criteria, supplemental features, and future work in [ROADMAP.md](ROADMAP.md).
- Documented candidate data providers, evidence limitations, and the mock-to-live integration strategy in [DATA_SOURCES.md](DATA_SOURCES.md).
- Assigned five feature-owner roles above a shared basic-planner foundation, with interface coordination and review expectations in [CONTRIBUTING.md](../CONTRIBUTING.md). Later owner confirmations are recorded in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Implemented local planner: Roam

The [travel-planner](../travel-planner/README.md) directory contains the initial Jac 0.37.23 application:

- A responsive web workspace for creating/editing trips and managing itineraries, bookings, packing lists, notes, and budgets.
- A CLI for creating and listing trips, adding items, changing completion/payment state, and deleting records.
- A shared SQLite service with stable IDs, transactional writes, trip/item validation, and cascade deletion.
- Trip-local date/time handling, chronological itinerary ordering, currency amounts stored in cents, and separate completion/confirmation and payment state.
- Budget totals derived from itinerary, booking, and expense records without duplicating booking costs.
- Server tests covering record lifecycle, exact amounts, invalid inputs, trip isolation, persistence across sessions, ordering, and cascade deletion.
- Setup, CLI examples, storage behavior, limitations, and validation commands documented in the planner README.

The implementation was added in commit [`47719ca`](https://github.com/howarddong0485/Travel-Disruption-Replanner/commit/47719ca66bd4b01f72933f47132004ee5e8ce0ed). The planning documentation was introduced and refined in `243cf8d`, `479446e`, and `7a8ecdf`.

## Read-only mock backup preview

Gehao Dong's backup module adds Boston/USD Plan B/C drafts for rain-affected activities and delayed-arrival dinners in the existing Itinerary page. Synthetic inventory includes source, checked time and expiry; unavailable/unknown or stale evidence is screened out. The service returns `needs_validation` and does not write a replacement itinerary or budget.

The original delivery includes an independent two-scenario demo, eight unit tests and one isolated service integration test. See the [backup preview demo](../travel-planner/README.md#backup-preview-demo) for supported scenarios and limitations. It does not implement automatic risk ingestion, full-trip constraint validation, changing inventory, comparison or acceptance.

## Historical foundation limits — 2026-10-06

Roam stores manually entered plans and booking details. It does not generate AI itineraries, search live inventory, make reservations, monitor disruptions, analyze cancellation policies, generate fully validated backups. It is a local personal prototype with public service endpoints, not a deployed multi-user service. Costs use one currency per trip with no exchange-rate conversion; times are destination-local with no automatic timezone conversion.

The next integration milestone is the documented fixture-based flow: profile and hard filters → plan → validate → risks → backups → simulated disruption → dependency-aware repair → compare → traveler review and explicit acceptance. Shared contracts, remaining named owners, and deployment choices still need agreement. Optional Jac LLM selection is available in the standalone replanning prototype.

## Historical verification boundary — 2026-10-13

The PR #19 merge-conflict fix was verified on October 13, 2026 with Jac 0.37.23, including the business theme and the latest backup-preview fixes from `main`. All three app checks, the client build, and 21 tests passed (11 planner/replanning, nine backup unit tests, one backup service test). The earlier backup-only delivery used Jac 0.37.21; issue #8 still tracks clean-checkout setup and CI coverage. Browser checks were not rerun for this merge fix; the backup audit below records its separate browser verification.

For the original PR #15 delivery, Jac 0.37.21 passed the eight backup unit tests, static checks for all three app entries, the client production build and the storage-free demo. The manifest still pins 0.37.23; that version was not available for this check. The backup service integration test and all three existing service regressions also passed after rerunning with Jac's normal Postgres cache/socket paths and cache access. Earlier attempts failed at environment provisioning. No fresh browser check was performed for the original delivery. Issue #8 tracks pinned-runtime/clean-checkout verification.

### PR #15 follow-up audit — 2026-10-13

The audit reproduced two missing boundaries: whitespace-only sources passed evidence screening, and preview cards stayed visible after their evidence expired. Source screening now rejects blank/whitespace-only references. The browser clears the drafts at their earliest evidence expiry, prompts a refresh, and cleans up its timer when the preview changes or the panel unmounts. Public demo links now point to the planner README.

Fresh verification on local Jac 0.37.21:

- Backup unit tests: 9 passed, including a regression that failed before the source fix.
- Backup service integration: 1 passed, checking storage snapshots after both successful scenarios and missing, foreign, completed, undated, wrong-category, unsupported-trigger and deleted-item requests.
- Original service regressions: 3 passed.
- All three app entrypoint checks and the client production build passed.
- Storage-free demo: rain and arrival-delay each returned two `needs_validation` drafts.
- [Browser regression](../travel-planner/tests/backup_preview.browser.cjs): 9 checks passed in headless Chrome with Playwright 1.62.1 and a dedicated temporary SQLite database. Checks cover both scenarios, a 390-pixel viewport, clearing old results, visible errors, late responses after trip switches, empty states, expiry/refresh and saved-data preservation. The expiry check failed before the timer fix.
- Checked 29 relative documentation targets and Git diff whitespace.

This remains a read-only mock preview. Pinned Jac 0.37.23 was unverified in that backup-only audit; clean-checkout CI remains unverified; complete trip validation, automatic risks and accepting/applying alternatives remain separate issues.

## Validation available

The application includes the following documented checks, run from `travel-planner/` after installing its dependencies:

```sh
jac check --nowarn
jac test server/main.test.jac
jac test backup/test_planner.jac
jac test server/test_backup.jac
jac test backup/test_validation.jac
jac test server/test_validation.jac
jac test backup/test_refresh.jac server/test_refresh.jac
jac build travel --as client
```

The server tests use temporary databases and do not modify saved trips. These commands describe the available validation workflow; the dated verification records above identify what was actually run. For documentation-only changes, verify relative links and run `git diff --check`.

## Disruption replanning and business theme

Roam now includes a synthetic disruption simulator, dependency traversal, per-item backup combinations, optional typed Jac LLM selection, and atomic version-safe acceptance. The separate Boston demo covers arrival-delay cascades and fixed-item conflicts. See the [replanning guide](../travel-planner/replan/README.md) for setup, endpoints, tests and limits. Shared profile/eligibility validation, policy evidence and cross-agent review integration remain tracked in [issue #18](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/18).

The web workspace uses a navy, slate and white business palette, with a flat trip overview and shared theme colors across backup and replanning panels.

## Pre-merge review corrections — 2026-11-01

Code commit `a92e3da` fixes all five reproduced backend review findings: retain
all activations per changed item; reconcile deleted/excluded supplemental item
references while rejecting new foreign writes; preserve booking metadata on
reschedule; use identical derived activation semantics for generation/acceptance;
and bound reviewed finances by cancellation deadlines and policy evidence.
Validator v2 rejects older stored proposals.

The history and connected panels dispatch mount listeners through the current
callback and drain queued checks after loading/refresh. The history correction
was also delivered in #31 as `fe4d4df`. Browser checks in two tabs per panel
verified that another tab's update clears the old results; neither panel logged
a console error.

The full pinned local verification passed: **419 reported tests**, four app
checks, both client builds, 3/5/5 planning scenarios, the 46-module sealed package
and both source/package HTTP/CLI checks. The seven new regression cases were
added in `planning/test_review.jac` and `planning/test_service.jac`. The reported
total includes imported companion checks. See the [final PR checks](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/36/checks)
for hosted verification of the final delivery revision.

## Final review corrections — 2026-11-01

`f8dcf35` filters dependency endpoints when items leave the scheduled-node set,
invalidates evidence when item facts are edited without confirmation, and
replaces the original venue's supplemental hours with the newly observed
provider hours. The category-change and provider-hours regressions detect the
old failures. A browser reproduction changed a retained item's admission age:
before the fix, saving without confirmation still yielded selectable plans;
after the fix all three were unresolved with disabled acceptance, and explicit
confirmation restored three selectable plans without console errors.

The complete pinned local sequence passed again with **420 reported tests**,
four app checks, two client builds, the 46-module sealed package and both
source/package HTTP/CLI checks. There are eight added regression cases across
`planning/test_review.jac` and `planning/test_service.jac`; imported companion
checks are included in the reported total. The earlier 419-test run records
`a92e3da` before this follow-up. See [final PR checks](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/36/checks)
for hosted verification of the final delivery revision.


### Saving edits after confirmation

The final review additionally reproduced an HTTP save failure when edited item
facts lost their evidence but retained opening-hours records citing that evidence.
Context loading and payload validation now remove only those derived records;
independent evidence remains, and unknown/foreign references still fail validation.
The added HTTP regression covers confirm/save, edit/save without confirmation,
disabled plans, explicit reconfirmation restoring valid plans, and invalid evidence
rejection. Browser verification saved a previously confirmed dinner edit, showed
three Needs confirmation alternatives with all acceptance buttons disabled, and
reported no console errors.

The final complete pinned sequence passed **421 reported tests**, four app checks,
both client builds, CLI alternatives **3 / 5 / 5**, the 46-module sealed package,
and isolated source/package HTTP/CLI checks. Nine added regression cases cover
the pre-merge review corrections. Earlier 419/420 counts above are historical.


### Dated hours and distinct follow-up plans

The next review reproduced two additional failures: same-venue reschedules could
ignore a supported closed-day record, and Find other plans repeated the displayed
candidates. Validator v3 now uses the dated supplemental hours, preserves unknowns
when their evidence is stale/incomplete, and caps the review by that evidence.
The acceptance regression rejects a formerly selectable closed-day reschedule
before any write. Request-another accumulates stable candidate exclusions, includes
them in idempotency checks and leaves prior proposals and active items unchanged.
The HTTP bridge's literal empty-list default is normalized for old callers.

The full pinned sequence passed **423 reported tests**, four app checks, both
clients, CLI alternatives **3 / 5 / 5**, complete 46-module sealing and isolated
source/package HTTP/CLI checks. Eleven added regression cases cover the review
corrections. Browser verification advanced through **3 → 2 → 0** distinct options,
showed the exhausted-pool message, retained the itinerary and had no console
errors. The earlier 421-test record remains historical.


During this verification, sealing first stopped because documentation changed
while preparation was running. The already-passing 423-test/four-check/client
results were retained. After files were held stable, the same verification
script's sealing and source/package HTTP/CLI phases were rerun successfully;
the 46-module package and both runtime checks passed. No backend source changed
between these phases. Hosted CI runs the final committed tree from the start.
