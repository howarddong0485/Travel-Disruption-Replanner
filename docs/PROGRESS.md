# Project progress

This report records the Roam foundation at commit `47719ca` (October 4, 2026) and the read-only mock backup preview added by this change. It separates implemented behavior from the remaining disruption-replanning design.

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
jac build travel --as client
```

The server tests use temporary databases and do not modify saved trips. These commands describe the available validation workflow; the dated verification records above identify what was actually run. For documentation-only changes, verify relative links and run `git diff --check`.

## Disruption replanning and business theme

Roam now includes a synthetic disruption simulator, dependency traversal, per-item backup combinations, optional typed Jac LLM selection, and atomic version-safe acceptance. The separate Chicago demo covers arrival-delay cascades and fixed-item conflicts. See the [replanning guide](../travel-planner/replan/README.md) for setup, endpoints, tests and limits. Shared profile/eligibility validation, policy evidence and cross-agent review integration remain tracked in [issue #18](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/18).

The web workspace uses a navy, slate and white business palette, with a flat trip overview and shared theme colors across backup and replanning panels.
