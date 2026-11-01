# Mock MVP delivery plan

Updated **2026-11-01**. Use [MVP_STATUS.md](MVP_STATUS.md) for implemented paths,
remaining code and contribution attribution. The howarddong stack (#30, #31, #32, #35, #36) is delivered on `main`;
separate source-PR coordination and the remaining code below stay open.

## Current baseline

- Roam supplies manual trip/itinerary/booking/packing/budget CRUD, CLI and SQLite.
- P1 profile/filter/ledger and P2 policy/risk modules are imported unchanged from their source
  PRs and delivered through connected planning PR #36.
- Connected backups support full-trip validation, up to five alternatives,
  refresh/invalidation, deterministic comparison and explicit version-safe apply.
- The legacy disruption-repair path still uses separate inventory and validation.
- Manifest-pinned Jac **0.37.23** setup, checks/tests/client builds, sealed
  packaging and source/package HTTP/CLI behavior have a successful
  [hosted CI record](https://github.com/howarddong0485/Travel-Disruption-Replanner/actions/runs/41315449524).
- Initial itinerary generation remains unimplemented (#5).

## Remaining work and acceptance

| Issue / role | Next code or review work | Completion evidence |
| --- | --- | --- |
| #7 / P1 + integrator | Complete supported interest/pace intake; agree on profile, evidence and whole-trip validation boundaries; reconcile #22/#24 conflicts and imports. | Agreed fixtures/interfaces; malformed/over-budget/overlap/unknown checks retained; owner demonstration of the connected flow. |
| #5 / shared foundation | Generate initial plans from bounded mock inventory; preserve manual items and require explicit transactional import. | Reproducible previews; explicit infeasibility; repeated imports do not duplicate items. |
| #10 / P2 | Complete evidenced risk/policy UI and policy-input/review flow. | Affected items, rule, source/excerpt, checked time, deadlines/refund terms and missing evidence visible without itinerary mutation. |
| #11, #34 / P3 + integrator | Confirm cross-owner handoff/contract decisions; the backup stack and #33 implementation are delivered. | Merged code and verification recorded; affected-owner confirmation remains explicit. |
| #12, #18 / P4 | Bring legacy repairs onto shared validation/inventory/comparison; regenerate backups after accepted changes. | Delay cascade/fixed-node cases use shared contracts; stale/duplicate/concurrent cases stay safe; backups match the new version. |
| #13 / P5 | Unify comparisons/review; add payment-timing-aware cash metrics and time/convenience/experience explanations. | Known/unknown payment fixtures; original payments count once; reject preserves items; accept applies the reviewed matching-version patch. |
| #8 / tooling + integrator | Maintain delivered setup/CI and the guarded sealed-build entry from #36. | Hosted run above plus required checks on the final merge revision. |

## Review and implementation order

1. Review the [contract packet](CONTRACT_REVIEW.md), reconcile source #22, #24,
   #27 and #16 with the imports, and assign shared-contract decisions.
2. The howarddong stack is merged. Reconcile separately authored source PRs with
   the imports; preserve source authorship and resolve duplicate/overlapping diffs.
3. Deliver #5 with P1 validation; complete P2's policy/risk UI in parallel.
4. Unify the legacy P4 path and P5 comparison, then test initial preview through
   risks/backups, disruption, review, acceptance and regenerated backups.

Each feature owner owns logic, feature UI, tests and integration. The status
matrix records parts implemented by other contributors. Shared schemas,
orchestration, fixtures and CI each need a named decision owner.

## Verification and closure

From the repository root, use `bash scripts/setup.sh` and
`bash scripts/verify.sh`; see [reproduction](LOCAL_VERIFICATION.md) for the
version-specific packaging command. Required failures must fail CI. Record
actual runtime, supported cases, test revision and hosted run URL.

Close an issue after its scope is implemented, verified and delivered. Keep
partial references as `Refs #N`. Generation/rejection preserves active items;
explicit acceptance updates simulated state only. External transactions and
live monitoring are outside the mock milestone.
