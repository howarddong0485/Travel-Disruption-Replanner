# Connected planning contract review

This packet makes the implemented proposal reviewable by the component owners.
It records the local code and tests; it does not record approval on their behalf.
Parent #11 and the shared work in #7, #13, #18 and #34 remain subject to review.

## Boundaries to approve

| Owner | Implemented boundary | Review decision |
| --- | --- | --- |
| P1 | `profile_io.profile_from_data` loads the existing profile; `evaluate_place` owns per-place hard filters; `build_ledger` owns totals. Whole-trip checks remain in the backup validator. | Approve profile/requirement mapping and integer minor-unit/retained-payment semantics. |
| P2 | `analyze_trip` and cancellation evaluation supply evidenced risks/refund terms. Expired, future, ambiguous DST or unsupported evidence stays unresolved. | Approve the evidence/freshness adapter, manual traveler-report scope and risk thresholds. |
| P3 | `roam.alternative-plan.v1` carries changed nodes, conditions, `trip_id + base_version`, content fingerprint, validation, comparison and expiry. Search does not apply items. | Approve the bounded catalog/search scope and contract evolution policy. |
| P4 | `review_backup_plan` delegates to the existing `decide` transaction; `apply_backup` refreshes/revalidates before storing P3's actual choices. | Approve version ownership, transaction/hook behavior, retained payments and stale-provider rejection. |
| P5 | Roam consumes deterministic comparison values and offers keep/reject/request-another/explicit accept. | Approve shell/navigation changes, uncertainty wording and review behavior. |
| Integrator | The source imports are separated from adapters; API/CLI remain compatible. | Coordinate upstream merges and name the shared-contract owner before final approval. |

## Invariants demonstrated by code and checks

- `selectable` requires valid, current `integrated_mock` evidence. It does not
  assert a real reservation, live availability or real-world booking eligibility.
- Authoritative saved-trip versions and supplemental content fingerprints are
  separate. Reviewed, expired, changed-price or old-version proposals cannot
  become selectable through retries.
- Eligibility, party pricing, hours, routes, dependencies and fixed boundaries
  are checked on the complete itinerary. Missing mandatory facts remain unknown;
  hard requirements are not relaxed to fill the requested number of cards.
- Totals include reserve; retained original payments count once. Potential cash
  refunds, credit and received refunds remain distinct. Unknown payment timing
  and unpaid confirmed-booking liability remain unknown, without funding the trip.
- Rejection changes proposal state only. Generation can save observations and
  proposals; only explicit acceptance mutates active itinerary items atomically.
- The actual reviewed candidate, not the legacy replanning catalog, is applied
  in the connected flow. The older guided demo is explicitly separate.

## Independent demonstrations

After [setup](LOCAL_VERIFICATION.md), run from `travel-planner/` with the pinned
binary (`../.tools/jac-0.37.23`):

| Boundary | Demonstration |
| --- | --- |
| P1 | `jac test profile/ filter/ budget/ planning/test_context.jac` |
| P2 | `jac test schema/ policy/ risk/` and `jac run risk/demo.jac` |
| P3 | `jac run planning/demo.jac` and `jac test planning/test_engine.jac planning/test_boundaries.jac planning/test_agent.jac` |
| P4/P5 handoff | `jac test planning/test_service.jac`; `bash scripts/verify.sh` from the repository root exercises real HTTP rejection, exact acceptance, versions and CLI against source and sealed servers. |

The integration guide lists the exact source commits for the 33 unchanged P1/P2
files. Review them as dependencies, then review the adapters and new alternative
schema separately. This proposal does not replace or silently approve those
owners' upstream PRs.

## Decisions still requiring people or remote evidence

- Agree on the proposed profile/alternative/context/validation versions and
  financial semantics; source ownership remains independently demonstrable.
- Decide source-PR/stack merge order, retarget dependent PRs and resolve any
  overlapping changes with their owners.
- Obtain a successful GitHub-hosted CI run after publishing the local workflow.

The local engineering gates and their precise verification scope are recorded in
[LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md). Mock MVP verification does not
establish production deployment or the later live-integration milestone.
