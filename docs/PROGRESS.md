# Project progress

This report separates delivery on `main` from implementations still under review. Dated verification records identify the code, runtime and scope that were actually checked.

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
- Assigned five feature-owner roles above a shared basic-planner foundation, with interface coordination and review expectations in [CONTRIBUTING.md](../CONTRIBUTING.md). Person numbers remain placeholders.
- Established the proposed sponsorship policy: clearly labeled mock ads, separate sponsored placements, and zero sponsorship weight in organic recommendations.

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

## Current limits and next milestone

Roam stores manually entered plans and booking details. It does not generate AI itineraries, search live inventory, make reservations, monitor disruptions, analyze cancellation policies, generate fully validated backups. It is a local personal prototype with public service endpoints, not a deployed multi-user service. Costs use one currency per trip with no exchange-rate conversion; times are destination-local with no automatic timezone conversion.

The next integration milestone is the documented fixture-based flow: profile and hard filters → plan → validate → risks → backups → simulated disruption → dependency-aware repair → compare → traveler review and explicit acceptance. Shared contracts, remaining named owners, and deployment choices still need agreement. Optional Jac LLM selection is available in the standalone replanning prototype.

## Latest verification boundary

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
