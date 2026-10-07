# Fixture MVP implementation plan

This plan follows the completed scope/architecture work in #1–#4 and the Roam foundation recorded in #6. It tracks executable delivery; documentation and open issues do not imply implemented features.

## Current baseline

- Roam provides manual trip, itinerary, booking-record, packing and budget management with web, CLI and SQLite.
- #5 remains open because initial itinerary generation is not implemented.
- The local read-only mock backup preview is tracked in #9. Full-trip validation, risk ingestion, comparison and application remain separate deliverables.
- The manifest pins Jac 0.37.23; current local validation uses 0.37.21. #8 tracks reproducible setup and CI. Results must name their actual runtime.

## Issues and proposed pull requests

| Issue | Owner / priority | Reviewable PR sequence | Completion gate |
| --- | --- | --- | --- |
| [#7](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/7) | Integrator for contracts; Person 1 for profile/feasibility; P0 | Shared contracts/fixtures → profile intake and minimum validator | Typed fixtures; budget/timing rejection; unknown required evidence stays unresolved |
| [#8](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/8) | Named tooling owner; P0 | Pinned setup and existing planner CI → backup checks when available | Clean checkout and actual successful CI run |
| [#5](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/5) | Temporary foundation lead/pair; P0 | Validated mock initial itinerary generator | Input produces itinerary; infeasibility is explicit; existing user items are preserved |
| [#9](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/9) | Gehao Dong; P0 | Read-only mock Plan B/C previews | Two scenarios, evidence/freshness screening, no mutation, tests and recorded runtime limits |
| [#10](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/10) | Person 2; P1 | Evidenced fixture policies → risk rules and panel | Item-linked rules/evidence; missing policy remains unknown |
| [#11](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/11) | Gehao Dong; P1 | Full-trip backup validation → evidence refresh/invalidation | No unsupported valid claims; changed/expired inventory revalidated |
| [#12](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/12) | Person 4; P1 | Dependency repair proposals → atomic version-safe application | Preserve unaffected/fixed feasible items; duplicate/stale events cannot corrupt state |
| [#13](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/13) | Person 5; P1 | Comparison metrics/UI → traveler review and acceptance | No double counting; rejection does not mutate; explicit accept uses Person 4's interface |

Person numbers remain role placeholders. Each feature owner owns its logic, feature UI, tests and integration. The basic planner is a shared-foundation task, not one of the five ongoing feature-owner assignments.

## Dependency and integration order

1. Agree on #7 contracts and common fixtures. #8 and #9 can proceed independently; #9 stays a limited draft preview.
2. Implement #5 against validation and mock inventory. Person 2 develops #10 with the same fixtures.
3. Integrate #11 with profile validation, policy evidence and risk flags.
4. Person 4 implements #12 proposal/application services. Person 5 implements #13 against authoritative financial outputs and that application interface.
5. Demonstrate the connected mock flow: profile → generated plan → validation → risks → backups → simulated disruption → repair → compare → review/accept.

Independent module demos should use agreed fixtures while upstream services are in progress. They must identify mocked/incomplete interfaces and cannot mark an unchecked alternative valid. Shared schemas, orchestration, common adapters, fixtures and CI each need one named owner at a time; the integration role can rotate.

## Pull request and closure rules

- Open a real PR only when a branch contains a scoped code/document change. Planned PR titles live in the associated issue until then.
- Split proposal generation from transactional application, and contract changes from dependent feature integration when useful for review.
- Record actual checks, environment, supported cases and unresolved limitations. Do not claim clean-checkout, browser or pinned-version validation from a different check.
- Close an issue only when its acceptance criteria are satisfied; a planning PR does not close implementation issues.
- Rejection leaves the current trip unchanged. Only explicit acceptance invokes version-safe simulated application. No real booking, cancellation, payments or claims are included in this milestone.

See [architecture](ARCHITECTURE.md), [roadmap](ROADMAP.md), [progress](PROGRESS.md) and [component ownership](../CONTRIBUTING.md) for the product and interface boundaries.
