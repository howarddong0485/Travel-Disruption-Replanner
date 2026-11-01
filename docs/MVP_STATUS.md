# Mock MVP status and remaining work

Updated **2026-11-01** for delivery on `main` through PRs #30, #31, #32,
#35 and #36. Pre-merge review corrections and their final evidence are recorded below. The separately authored
P1/P2 source PRs retain their own review status; importing their code does not
record contract approval on their owners' behalf.

## Remaining implementation by role

| Role | Implemented on main | Remaining implementation | Implementation attribution |
| --- | --- | --- | --- |
| **P1 — personalization and feasibility** | Structured profiles, hard/soft requirement models, per-place eligibility, ledger, profile loading, hard-requirement/fact forms and full-trip checks for connected backups. | Complete basic interest/pace/soft-preference intake and use it consistently in the supported mock workflow. Agree on the shared full-trip validator boundary with the integrator. | Daniel Hu: profile/filter/budget (#22, #24, #27). P3: profile loader/forms, whole-trip backup validation and adapters. P2: shared itinerary/evidence/policy/risk schema proposal. |
| **P2 — policies and risks** | Evidenced policy extraction, cancellation evaluation, risk rules, unknown handling and tests. Connected backups consume results and display selectable risk summaries. | Complete the Roam risk/policy panel: affected items, rule/severity, cited source/excerpt, checked time, missing evidence, cancellation deadlines and refund terms. Provide the supported policy-input/review flow in the UI. | czhobro: policy/risk/schema (#16). P3: saved-trip evidence/freshness adapter, risk selection/summary UI and comparison consumption. |
| **P3 — proactive backups** | Up to five venue/provider, rescheduling and connected-node plans across ten supported categories; full-trip checks, refresh/invalidation, immutable observations/history, UI, actual-candidate handoff and engineering verification. | No additional implementation gap identified within the current supported P3 mock scope. Cross-owner contract confirmation remains delivery work. | Gehao Dong: backup logic/UI and connected integration (#30, #31, #32, #35, #36). Uses P1 filtering/ledger, P2 policy/risk and P4 transactions. P4 contributed earlier navigation/guided demo. |
| **P4 — disruption repairs** | Delay/interruption simulation, dependency traversal, protected nodes, bounded combinations, event deduplication, version checks and atomic explicit acceptance. Connected P3 proposals can use the transaction. | Route legacy `propose_replan`/`combine_replan` through shared evidence/eligibility/ledger/comparison contracts; it still uses a separate synthetic catalog and validator. Regenerate relevant backups after accepted repairs and verify the lifecycle (#18). | JackyLiuhh: original engine/transaction/UI (#19), Roam foundation, theme and guided demo (#21, #25). P3: Jac migration and connected-candidate refresh/revalidation/application adapter. |
| **P5 — comparison and traveler control** | Before/after items and times, deterministic money comparison, keep/reject/request-another/accept, stale-result guards and matching-version application. | Unify comparison across connected backups and legacy repairs; implement payment-timing-aware cash due now with evidenced usable credits/received refunds; complete convenience/experience tradeoffs and explanations. Surface shared time/travel metrics consistently. | P4: original review UI, navigation and theme. P3: connected comparison contract/calculator, review UI and integration checks. P1/P2 supply authoritative ledger/policy inputs. |

P1/P2/P4 interfaces are normal dependencies of P3; their original algorithms
remain those owners' contributions. In import commit `e422b0f`, P1's 12 files
and P2's 21 files match their documented source commits unchanged. New adapters,
comparison/UI and integration checks are attributed separately.

Current code returns `cash_needed_now_minor = None` because payment timing is
not represented. A new purchase quote is not an amount due now. Completing the
broader comparison requirement needs explicit timing/receipt/credit inputs and
tests, rather than substituting quotes. The text-to-profile clarification agent
and model-generated comparison explanations remain architectural designs;
structured intake and deterministic comparison already work without live models.

## Shared foundation still missing

[#5](https://github.com/howarddong0485/Travel-Disruption-Replanner/issues/5)
remains open: destination, dates, budget and current requirements do not yet
generate a reproducible initial itinerary from mock inventory. Demo loaders
create predefined samples. The generator needs explicit infeasibility and
unknown states, preservation of manually entered items, and explicit
transactional, idempotent import. This belongs to the shared foundation,
coordinated with P1.

## Delivery gates

- Agree on proposed contracts, financial semantics, risk thresholds and shared
  validator/application ownership; use the [review packet](CONTRACT_REVIEW.md).
- Reconcile source #22, #24, #27 and #16 with their unchanged code now included
  on main; their separate review/PR state remains with their owners.
- The howarddong stack **#30, #31, #32, #35, #36** is delivered. Remaining code
  above and cross-owner confirmation continue in the parent issues.

## Verification and scope

The [GitHub-hosted verification run](https://github.com/howarddong0485/Travel-Disruption-Replanner/actions/runs/41315449524)
passed for the earlier `83fee96` baseline on Ubuntu 24.04/Linux x86_64, Python 3.14 and Jac
0.37.23: **387 tests**, **four app checks**, **two client builds**, the **46-module
sealed package**, and source/sealed non-development HTTP/CLI checks. The pre-merge fixes passed the full local sequence with **427 reported tests**,
four app checks, both clients, sealed build and source/package smoke checks.
Fifteen added regressions cover the backend findings, foreign-write rejection and ordinary item/category changes;
browser checks cover current-state listeners and unconfirmed edits. Supplemental
venue hours are refreshed from the accepted provider. Changed item facts lose
old evidence until explicitly confirmed; derived opening-hours references are
removed with the cleared evidence so an unresolved edit can still be saved.
The UI was verified before confirmation, after confirmation and after editing
previously confirmed facts without reconfirming. Validator `roam.planning-validator.v4` invalidates old
proposals, enforces every selected activation and expires financial review at
policy boundaries. Dated supplemental hours govern same-venue reschedules;
closed-day evidence blocks them. Requesting other plans excludes already shown
candidate identities and reports exhaustion without changing the itinerary.
All confirmed opening intervals are retained separately, and ordinary item edits
invalidate affected evidence transactionally. Older contexts require confirmation
once when the invalidation guard is installed.
See [final PR checks](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/36/checks)
for hosted verification of the merge revision. These checks cover implemented paths; they do not
implement the gaps above or establish completion of the whole MVP.

Connected inventory is synthetic **Boston/USD**, bounded to eight affected nodes
and 256 combinations. Live providers/monitoring, real bookings,
cancellations/payments, insurance claims, cross-trip memory and production
multi-user deployment are later work. Optional model selection has deterministic
fallback; no live model call was required for this verification.

See [setup and packaging](LOCAL_VERIFICATION.md), [architecture](ARCHITECTURE.md),
[roadmap](ROADMAP.md) and the [dated progress record](PROGRESS.md).
