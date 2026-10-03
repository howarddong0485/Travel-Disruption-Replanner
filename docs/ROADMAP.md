# Product Scope and Roadmap

This roadmap proposes implementation stages rather than delivery dates. All milestones are currently planned; the repository contains documentation only.

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

## Milestone 4 — Dependency-aware replanning, comparison, and traveler control (MVP complete)

Implement disruption-triggered, dependency-aware replanning with a simulator or traveler-reported events, dependency traversal, and minimal graph repairs. Add separate comparison and traveler-review steps, including keeping important arrangements, rejecting suggestions, requesting replacements, and accepting a revised plan. Display labeled mock advertisements separately from organic results. The demo can simulate flight delays/cancellations, bad weather, attraction closures, and traveler changes.

**Acceptance:** the complete flow works on mock data; an arrival delay checks car, hotel, and restaurant dependencies; feasible unaffected and traveler-fixed nodes are preserved, with infeasible fixed items reported as conflicts; repairs still satisfy mandatory dietary/pet/child/accessibility requirements; comparisons show cash needs, refund loss, and projected total cost separately; the traveler can inspect changes, reject or request another option without altering the current itinerary, and explicitly accept a patch; duplicate/stale events cannot corrupt trip state.

### MVP boundaries

Included: fixture-based inventory and policies, current-trip profiles and hard filters, initial planning, deterministic validation, risk flags, backup options, simulated or traveler-reported disruptions, dependency-aware repairs, transparent alternative comparison, traveler review and acceptance, basic rejection/replacement feedback, and mock ads.

Deferred: consented cross-trip memory, advanced soft-preference modes, expanded landmark discovery, long-term preference learning, actual booking or cancellation, insurance purchase, live operational monitoring, real claims submission, payments, and real sponsorships. Insurance preferences may be captured in the MVP but do not imply coverage or a transaction.

## Milestone 5 — Live integrations

Replace selected mock adapters with approved providers, add freshness and quota handling, choose a flight-status source, and introduce live event ingestion. Revalidate inventory and terms before consequential actions. Label live and simulated modes clearly.

**Acceptance:** source and timestamp provenance remain visible; provider failures are handled without fabricated results; credentials remain server-side; integration terms and operating costs have been reviewed.

## Milestone 6 — Insurance, claims, and commercial features

Implement coverage records separately from traveler preferences. Explore claim-document preparation, evidence collection, deadline tracking, and authorized submission where supported. Evaluate real ads or sponsorships only after approving the ranking and disclosure policy.

**Acceptance:** claim estimates identify evidence and uncertainty; pending claims are excluded from available budget; submissions and purchases require traveler authorization; organic rankings remain independent of ad payments under the proposed policy.

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
| Sponsor offers a higher payment | Organic ranking and eligibility checks remain unchanged. |

## Decisions for the team

- Which stack, LLM provider, schema format, and persistence layer should the prototype use?
- Which destinations, travel modes, currencies, and party types define the first supported demo?
- What are the default transfer buffers, risk thresholds, retry limit, and contingency policy?
- How should comparison weights reflect cost, time, convenience, and experience preferences?
- Which information must a traveler confirm before a trip is considered feasible?
- Which provider access is obtainable, and what API budget is acceptable?
- Is the sponsorship policy approved, and which quality metrics would trigger stopping a campaign?
- What license, privacy/retention rules, and deployment model should be adopted?
