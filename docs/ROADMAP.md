# Product Scope and Roadmap

Updated **2026-11-01**. This roadmap defines completion targets; [MVP_STATUS.md](MVP_STATUS.md) records current implementation and remaining work. Jac/SQLite, pinned setup and CI are in place on the connected review branch. Initial generation, full policy UI, unified repairs/comparison and coordinated merges remain open.

| Milestone | Current review-branch state |
| --- | --- |
| Shared foundation | Runtime/storage/CI implemented; shared-contract approval pending. |
| General planner | Manual CRUD, structured requirements, filters and ledger implemented; initial generation missing. |
| Risks and backups | Core modules and connected multi-plan flow implemented; complete policy/risk UI pending. |
| Replanning and review | Atomic prototype and connected backup acceptance implemented; shared legacy path, regeneration and full comparison pending. |
| Live integrations / insurance | Later milestones. |

## Feature priorities

Key features: personalized, budget- and constraint-aware planning; risk and cancellation awareness; proactive backup planning; disruption-triggered, dependency-aware replanning; transparent alternative comparison; and traveler review and plan control. Current-trip profiles and mandatory dietary, pet, child, and accessibility filters are core requirements, including during backups and repairs. Replanning and downstream dependency checks are one feature; comparison and traveler confirmation are separate steps.

Supplemental features: consented cross-trip memory, advanced soft-preference modes, expanded landmark discovery, and long-term preference learning. Basic interest matching, “not interested” feedback, and requesting a replacement remain part of the core workflow.

## Milestone 1 — Shared foundation

Agree on a language/framework, schema format, LLM interface, and storage approach. Define contracts for profiles, itinerary graphs, policies, risk flags, alternatives, disruptions, and the budget ledger. Assign the five component owners and create shared mock fixtures.

**Acceptance:** all owners can exchange schema-valid fixtures; money/time conventions are documented; the validator rejects basic budget and timing violations; CI runs the chosen checks once code is introduced.

## Milestone 2 — General travel planner

Implement profile intake, mandatory filters, place tagging, a budget ledger, mock search tools, and initial itinerary generation. Support dining preferences, mandatory dietary/pet/child/accessibility filters, interests, and basic “not interested” replacement requests. Show estimated costs and known policy restrictions.

**Acceptance:** a valid fixture trip fits its budget and mandatory requirements; contradictory constraints produce an explicit infeasible result; unsupported eligibility remains unknown; preference feedback affects subsequent suggestions.

## Milestone 3 — Risks and proactive backups

Add policy extraction, cancellation tracking, risk rules, and multiple backup plans for vulnerable portions of the itinerary. Include weather exposure, tight timing, long drives, restrictive bookings, and limited hours.

**Acceptance:** each risk cites its rule/evidence; each proposed backup passes full-trip validation, including mandatory traveler filters; backup prices and availability have timestamps; an unavailable backup is not shown as reservable; valid backups can be compared using the same deterministic metrics as later repairs.

## Milestone 4 — Dependency-aware replanning, comparison, and traveler control (MVP completion target)

Implement disruption-triggered, dependency-aware replanning with a simulator or traveler-reported events, dependency traversal, and minimal graph repairs. Add separate comparison and traveler-review steps, including keeping important arrangements, rejecting suggestions, requesting replacements, and accepting a revised plan. The demo can simulate flight delays/cancellations, bad weather, attraction closures, and traveler changes.

**Acceptance:** the complete flow works on mock data; an arrival delay checks car, hotel, and restaurant dependencies; feasible unaffected and traveler-fixed nodes are preserved, with infeasible fixed items reported as conflicts; repairs still satisfy mandatory dietary/pet/child/accessibility requirements; comparisons show cash needs, refund loss, and projected total cost separately; the traveler can inspect changes, reject or request another option without altering the current itinerary, and explicitly accept a patch; duplicate/stale events cannot corrupt trip state.

### MVP boundaries

Included: fixture-based inventory and policies, current-trip profiles and hard filters, initial planning, deterministic validation, risk flags, backup options, simulated or traveler-reported disruptions, dependency-aware repairs, transparent alternative comparison, traveler review and acceptance, and basic rejection/replacement feedback.

Deferred: consented cross-trip memory, advanced soft-preference modes, expanded landmark discovery, long-term preference learning, actual booking or cancellation, insurance purchase, live operational monitoring, real claims submission, and payments. Insurance preferences may be captured in the MVP but do not imply coverage or a transaction.

## Milestone 5 — Live integrations

Replace selected mock adapters with approved providers, add freshness and quota handling, choose a flight-status source, and introduce live event ingestion. Revalidate inventory and terms before consequential actions. Label live and simulated modes clearly.

**Acceptance:** source and timestamp provenance remain visible; provider failures are handled without fabricated results; credentials remain server-side; integration terms and operating costs have been reviewed.

## Milestone 6 — Insurance and claims

Implement coverage records separately from traveler preferences. Explore claim-document preparation, evidence collection, deadline tracking, and authorized submission where supported.

**Acceptance:** claim estimates identify evidence and uncertainty; pending claims are excluded from available budget; submissions and purchases require traveler authorization.

## Essential demo and test scenarios

| Scenario | Expected result |
| --- | --- |
| Family with a pet and dietary requirements | Mandatory requirements are validated with evidence during initial planning, backups, and repairs; unknowns are surfaced. |
| No feasible itinerary within budget | Explain infeasibility and possible user-approved changes; do not exceed budget silently. |
| Rain affects an outdoor activity | Offer feasible indoor backups and preserve unrelated bookings. |
| Delayed arrival crosses car pickup and hotel deadlines | Check all affected dependencies and show any action needed with the provider. |
| Cancellation incurs a fee | Show the fee, cash required, and total trip cost without double counting prior payments. |
| Policy is missing or ambiguous | Mark refund exposure unknown and request review rather than asserting eligibility. |
| Backup price changes or inventory disappears | Refresh, revalidate, and remove invalid options. |
| Traveler rejects an alternative | The active itinerary stays unchanged; requesting another option produces a newly validated proposal. |
| Traveler wants to keep a booking | Preserve it when feasible; otherwise show the conflict for traveler review. |
| Traveler accepts a repair | Apply only the reviewed patch against its matching trip version; no external booking or cancellation occurs in the MVP. |
| Duplicate event or outdated patch | Process idempotently or recompute; preserve current trip state. |
| Local midnight or daylight-saving boundary | Compare instants correctly while displaying local rules and deadlines. |

## Decisions for the team

- Approve shared contract versions and ownership for the implemented Jac/SQLite stack; model calls remain optional.
- Decide any expansion beyond the current bounded Boston/USD mock inventory and supported party facts.
- What are the default transfer buffers, risk thresholds, retry limit, and contingency policy?
- How should comparison weights reflect cost, time, convenience, and experience preferences?
- Which information must a traveler confirm before a trip is considered feasible?
- Which provider access is obtainable, and what API budget is acceptable?
- What license, privacy/retention rules, and deployment model should be adopted?
