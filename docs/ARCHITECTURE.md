# Architecture and LLM Inputs

This document is a proposed implementation contract. The repository does not yet implement these components. Start with a modular application and shared typed data contracts; an agent does not need its own service or deployment.

## Product feature boundaries

The six MVP key features are personalized, budget- and constraint-aware planning; risk and cancellation awareness; proactive backup planning; disruption-triggered, dependency-aware replanning; transparent alternative comparison; and traveler review and plan control.

Current-trip profile intake and mandatory dietary, pet, child, and accessibility filters are core requirements throughout initial planning, backups, and repairs. Cross-trip memory, advanced soft-preference modes, expanded landmark discovery, and long-term preference learning are supplemental. Basic “not interested” feedback and requesting a replacement belong to the core user flow.

Disruption handling and dependency traversal form one replanning feature. The MVP receives simulated or traveler-reported events; automatic live monitoring is a later integration. BackupAgent proposes alternatives, ComparatorAgent compares validated alternatives before and after disruptions, and the review UI obtains the traveler's decision before the orchestrator applies a patch.

## Component responsibilities

| Component | Implementation | Inputs → outputs |
| --- | --- | --- |
| Orchestrator | Deterministic code; graph traversal “walkers” | Trip state and events → ordered component calls, validated state transitions, trace records |
| ProfileAgent | LLM | Traveler text and existing approved preferences → structured `TravelerProfile` and clarification requests |
| PlannerAgent | LLM plus tools | Profile, constraints, candidate inventory → proposed `ItineraryGraph` |
| PolicyAgent | LLM extraction plus code checks | Booking-specific terms and source metadata → `RefundPolicy` with evidence and unknown fields |
| RiskAnalyzer | Rules plus optional bounded LLM classification | Itinerary, policies, weather evidence → `RiskFlag` records |
| BackupAgent | LLM plus tools | Flagged nodes, dependencies, budget, candidate inventory → validated `AlternativePlan` candidates |
| ReplanAgent | LLM plus tools | Disruption, affected graph, boundary constraints, refreshed alternatives → proposed graph patches |
| ComparatorAgent | Code plus LLM explanation | Valid candidates and verified metrics → comparison rows and an explained recommendation |
| ConstraintValidator | Deterministic code | Proposed plan, profile, ledger, evidence → pass or structured validation errors |

The LLM may estimate subjective experience fit, but it must label that estimate and tie it to stated interests. It must not calculate authoritative totals, invent inventory, infer refund entitlements without evidence, or override hard constraints.

## Shared data contracts

Define these contracts in `schema/` before implementing agents. The field lists below establish scope; they are not finalized schemas.

| Contract | Minimum information |
| --- | --- |
| `TravelerProfile` | Party composition, child ages where needed, pet details, dietary requirements, interests, accessibility requirements, pace, hard constraints, soft preferences, risk tolerance, consented memory |
| `TripRequest` | Origin, destinations, date ranges, time zones, total budget, budget currency, contingency reserve, flexibility, insurance preferences by booking category |
| `ItineraryNode` | Stable ID, kind, location, start/end, local time zone, provider reference, price evidence, booking status, policy reference, requirements, source freshness |
| `ItineraryEdge` | Source ID, target ID, relation (`precedes`, `depends_on`, `alternative`), minimum transition time where applicable |
| `ItineraryGraph` | Trip ID, version, active nodes and dependency edges, linked alternative plans, creation/update times |
| `RefundPolicy` | Booking and fare/room scope, cancellation deadline and time zone, refundable amount or rule, fees, cash/credit distinction, no-show terms, source reference, retrieved time, extraction confidence, unknowns |
| `RiskFlag` | Affected node IDs, category, severity, triggering rule, evidence, mitigation, evaluation time; probability only when supported |
| `AlternativePlan` | ID, replaced node IDs, candidate nodes/edges, activation conditions, boundary constraints, cost breakdown, validation result, checked time, expiry if supplied |
| `DisruptionEvent` | Unique event ID, type, source, affected references, observed and effective times, payload, confidence or verification state |
| `PlanPatch` | Base graph version, removed/replaced/added nodes and edges, reason, affected dependencies, validation results |
| `BudgetLedger` | Itemized payments, commitments, estimates, fees, credits, confirmed refunds, pending claims, contingency, currency conversion evidence |
| `ComparisonResult` | Candidate IDs, deterministic money/time metrics, convenience factors, subjective experience fit, uncertainties, recommendation rationale |

Use explicit currency codes and integer minor units for monetary values, with currency-specific precision. Do not mix currencies without a dated exchange-rate record. Store instants unambiguously and retain IANA time zones for local deadlines, opening hours, and daylight-saving transitions. Missing information stays unknown; it is not silently interpreted as zero, refundable, pet-friendly, or available.

An `alternative` edge links a current item to a candidate plan. Inactive backups do not count as booked itinerary nodes or incur booked costs. Active time/dependency edges must be acyclic; alternative links are excluded from that check.

## What is actually fed into the LLM?

Give each agent a small, structured task packet rather than the entire database or unfiltered search results:

1. **Role and operation:** what this component may propose and the exact output schema.
2. **Relevant traveler constraints:** mandatory requirements, preferences, remaining budget, and explicitly approved memory.
3. **Task-specific state:** the initial trip request, risky nodes, or affected subgraph with fixed boundary conditions.
4. **Retrieved evidence:** a bounded set of normalized candidates and relevant policy excerpts with stable source IDs and timestamps.
5. **Available tools:** allowed search/detail operations and their input/output contracts.
6. **Prior validation errors:** only errors relevant to the current repair attempt.

For example, a ReplanAgent request might contain the following illustrative JSON. Referenced IDs resolve to evidence supplied in the same request or through an allowed tool; they are not permission to fabricate details.

```json
{
  "task": "repair_itinerary",
  "trip_id": "demo-trip",
  "base_graph_version": 3,
  "event": {
    "id": "demo-delay-01",
    "type": "flight_delay",
    "affected_node_ids": ["flight-01"],
    "delay_minutes": 120
  },
  "constraints": {
    "currency": "USD",
    "max_additional_outlay_minor": 20000,
    "pet_required": true,
    "dietary_requirements": ["vegetarian"]
  },
  "affected_node_ids": ["flight-01", "car-01", "hotel-01", "dinner-01"],
  "fixed_node_ids": ["museum-next-day"],
  "candidate_ids": ["later-pickup-01", "dinner-backup-02"],
  "evidence_ids": ["arrival-update-01", "hotel-terms-01", "restaurant-hours-02"],
  "validation_errors": [],
  "required_output": "PlanPatch"
}
```

The production packet must also include the actual node details, relevant policies, fixed-node timing/location boundaries, and candidate evidence. This compact example shows the envelope, not a sufficient standalone planning prompt.

### Context by agent

- **ProfileAgent:** traveler text and approved existing profile; return unknowns and questions instead of guessing material requirements.
- **PlannerAgent:** normalized profile, travel windows, candidate inventory, transit estimates, and spending limits.
- **PolicyAgent:** relevant booking terms with source URL/document ID, booking scope, and retrieval date. Preserve supporting excerpts for extracted fields.
- **RiskAnalyzer's optional LLM call:** activity description and evidence for a narrow classification such as weather sensitivity; rules determine resulting flags.
- **BackupAgent:** risk flags, vulnerable nodes, connected constraints, and refreshed replacement inventory.
- **ReplanAgent:** affected subgraph, unchanged boundary nodes, event details, backups, refreshed inventory, and available budget.
- **ComparatorAgent's LLM call:** validated comparison metrics and traveler priorities; generate an explanation without changing computed values.

Treat provider text, reviews, and uploaded policy text as untrusted data, not instructions. Restrict tool access by role. Omit credentials, payment details, and unnecessary personal identifiers from prompts and logs. Version prompts and schemas so a planning decision can be reproduced.

## Initial planning lifecycle

1. Parse the profile and resolve missing information that affects feasibility.
2. Fetch mock or live candidates through normalized tool adapters.
3. Build a candidate itinerary using only supported inventory references.
4. Extract applicable booking policies and attach evidence.
5. Run schema, budget, timing, policy, and traveler-constraint validation.
6. Send structured errors back for a bounded retry count, configurable as `N`.
7. Analyze risk and generate multiple backups for vulnerable parts where feasible.
8. Validate each backup in the full trip context, compare valid alternatives through ComparatorAgent, and present the itinerary and alternatives for traveler review. Support rejection or a replacement request without silently relaxing hard constraints.

After retry exhaustion, return an explicit infeasible or incomplete result with reasons and possible constraint changes. Do not quietly increase the budget or relax requirements.

## Disruption-triggered, dependency-aware replanning

1. Deduplicate the disruption by event ID and load the current trip version.
2. Locate directly affected nodes and traverse dependency edges to find potentially affected bookings.
3. Recalculate time and location feasibility; expand the repair scope if a boundary becomes invalid. For arrival changes, check pickup windows, hotel check-in/no-show rules, meal reservations, and next-day transport.
4. Preserve completed, fixed, and unaffected feasible nodes. If a fixed node becomes impossible, report the conflict for traveler review.
5. Refresh relevant backups, inventory, and terms. A stored Plan B is a starting point, not a guarantee of current availability.
6. Generate candidate patches. Validate each patched full graph, including boundaries and the ledger.
7. Compare valid candidates and show exactly what changes and why. Let the traveler reject a proposal or request another option without changing the active itinerary; require explicit acceptance before applying any patch.
8. Apply the traveler's selected patch atomically only if its base version still matches. Otherwise recompute against the newer version.
9. Record the decision and rerun risk analysis and backup generation for changed portions.

The MVP updates simulated trip state only. Future booking, cancellation, purchase, and claim-submission actions require explicit traveler authorization and separate execution/status tracking. A failed external action must not appear as a completed reservation.

## Traveler review and plan control

The UI shows which items will be added, removed, or replaced, the reasons, and the computed comparison metrics. Travelers can mark arrangements as fixed before requesting a repair. If keeping an item becomes infeasible, surface the conflict instead of silently replacing it or treating the plan as valid.

Rejecting a suggestion leaves the active itinerary unchanged; a replacement request generates a new validated candidate. Accepting a proposal applies only the reviewed patch against its matching base version. In the MVP this updates simulated trip state and does not make or cancel external bookings.

## Validation and comparison

Hard checks include budget ceilings, timing conflicts, minimum transfer times, opening hours, verified pet/child/dietary eligibility where required, booking-policy deadlines, inventory references, and graph consistency. Unknown evidence for a mandatory condition produces an unresolved result, not a pass. Numeric thresholds such as connection buffers and long-drive limits are configurable.

Compare money in separate columns to avoid double counting:

- **Additional cash needed now:** replacement purchases plus fees due now minus refunds already received and usable credits actually applied.
- **Refund loss:** previously paid amounts that are unrecoverable for canceled items under the applicable policy. Show pending/uncertain amounts separately.
- **Projected total trip cost:** prior payments plus future/new payments minus confirmed cash refunds, with pending refunds shown as a separate scenario. Credits reduce a purchase only when applicable and applied.
- **Budget headroom:** total budget minus projected total cost, with contingency and cash-flow needs also displayed.

Refund loss is explanatory; do not add it again if original payments are already included in projected total cost. Unapproved insurance claims do not fund the trip. Use deterministic calculations for travel time and cost. Normalize any ranking metrics and disclose weights; the weights are a team decision, with user priorities allowed to influence soft preferences. Sponsorship is excluded from organic ranking.

## Policy, insurance, and claim boundaries

Supplier cancellation terms, supplier disruption remedies, and insurance coverage are separate records. Use booking-specific terms and evidence rather than a generic company policy when determining an estimate. Ambiguous or conflicting terms require review.

Insurance preferences belong in intake; actual coverage requires a separate policy record with insured items, coverage dates, exclusions, limits, deductibles, and evidence. Proposed future claim states are `draft`, `awaiting_user_review`, `submitted`, `pending`, `approved`, `denied`, and `paid`. Store event evidence, receipts, deadlines, and submission references. Never equate submitted or approved with paid.

## Reliability and privacy

- Use mock fixtures for repeatable demos; mark mock data and simulated events visibly.
- Set provider-specific freshness policies and show stale or unavailable data instead of fabricating a result.
- Put tool timeouts, bounded retries, and structured errors around external calls.
- Track trip versions, event IDs, agent/tool calls, validation failures, latency, and cost without logging sensitive payloads by default.
- Store trip memory only with consent; support correction and deletion. Set retention rules before production use.
- Keep secrets in environment configuration or a secret manager, never in source control or browser-delivered code.
