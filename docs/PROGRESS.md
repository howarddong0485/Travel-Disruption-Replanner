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

The module includes an independent two-scenario demo, eight unit tests and one isolated service integration test. See [the weekly plan](GEHAO_DONG_PLAN.md) for contracts and limitations. It does not implement automatic risk ingestion, full-trip constraint validation, changing inventory, comparison or acceptance.

## Current limits and next milestone

Roam stores manually entered plans and booking details. It does not generate AI itineraries, search live inventory, make reservations, monitor disruptions, analyze cancellation policies, generate fully validated backups, or perform dependency-aware repairs. It is a local personal prototype with public service endpoints, not a deployed multi-user service. Costs use one currency per trip with no exchange-rate conversion; times are destination-local with no automatic timezone conversion.

The next integration milestone is the documented fixture-based flow: profile and hard filters → plan → validate → risks → backups → simulated disruption → dependency-aware repair → compare → traveler review and explicit acceptance. Shared contracts, named owners, an LLM provider, and deployment choices still need agreement.

## Latest verification boundary

For this delivery, Jac 0.37.21 passed the eight backup unit tests, static checks for all three app entries, the client production build and the storage-free demo. The manifest still pins 0.37.23; that version was not available for this check. The backup service integration test and all three existing service regressions also passed after rerunning with Jac's normal Postgres cache/socket paths and cache access. Earlier attempts failed at environment provisioning. Browser behavior was documented in the earlier local acceptance record; no fresh browser check was performed for this delivery. Issue #8 tracks pinned-runtime/clean-checkout verification.

## Validation available

The application includes the following documented checks, run from `travel-planner/` after installing its dependencies:

```sh
jac check --nowarn
jac test server/main.test.jac
jac test backup/test_planner.jac
jac test server/test_backup.jac
jac build travel --as client
```

The server tests use temporary databases and do not modify saved trips. These commands describe the available validation workflow; this report does not assert a fresh application test run. For this documentation update, verify relative links and run `git diff --check`.
