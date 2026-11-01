# Backup change explanations

Fresh synthetic Plan B/C results now explain what changes from the original
sample itinerary. The same component appears in Roam's Backup plans panel and
the standalone `backup_refresh` app. The calculations are module-owned, with no
shared-agent dependency, recommendation score, acceptance or booking behavior.
The [unified workflow](WORKFLOW.md) also uses these explanations for saved-trip
inputs; missing original facts leave the affected metrics unknown.

## Try it

Run `jac run --host 127.0.0.1 --port 8340 backup_refresh` from `travel-planner/`,
choose **Find backup plans**. Each candidate's
**What changes?** section shows the original/replacement item, original and
proposed whole-trip totals, their difference, budget remaining, and start/end/
duration changes. In the explicit `?diagnostics=1` view, **Calculation details** exposes quotes and original/proposed
times with their timezones. It supports keyboard expansion.

With the family profile and USD 600 budget:

| Scenario | Plan B | Plan C |
| --- | --- | --- |
| Rain, original inventory | USD 440 total; USD 30 more; same time | USD 470 total; USD 60 more; starts 15 minutes later, lasts 15 minutes longer |
| Rain, first inventory option price increase | Covered botanical hall: USD 470 total; USD 60 more | Covered market visit: USD 425 total; USD 15 more |
| Delayed arrival, original inventory | USD 395 total; USD 15 less; starts 60 minutes later | USD 425 total; USD 15 more; starts 90 minutes later |
| All providers fail | No current option; retry message | No current option |

The expanded workflow selects alternatives after full validation. The rejected
USD 640 gallery and its original metrics remain in the diagnostic decision record
and immutable snapshot. Stateless legacy fixture endpoints retain the original
two-candidate output. See [SELECTION.md](SELECTION.md).

## Meaning and boundaries

- Original planned total = all original whole-party quotes + reserve. Retained
  items' existing payments are already included in their total quotes.
- Proposed total comes directly from the full-trip validator: proposed quotes +
  reserve + the replaced item's retained payment. No refund is assumed.
- Planned cost difference = proposed total minus original total. This is **not
  an amount due now**, a refund estimate or a claim that the original disrupted
  itinerary is feasible. Budget remaining may be negative.
- Missing/stale quote evidence, incomplete party pricing, currency mismatch or
  inconsistent payment history leaves the affected metric unknown, with a reason.
  Unknown budget does not erase otherwise supported totals or cost differences.
- Time differences resolve local times to UTC. Cross-midnight, cross-timezone
  and explicit DST folds use elapsed minutes; ambiguous/nonexistent times and
  nonpositive durations remain unknown.
- A cheaper or shorter proposal can still be rejected. Metrics do not change
  validation status or rank candidates. Selection groups passing options ahead of
  unresolved options and preserves provider search order within each group.
  Sample reports retain `standalone_fixture`;
  saved-trip reports use `saved_trip_mock` and do not claim shared validation.

## Freshness and history

`backup/changes.jac` computes a versioned `changes` object from the original
trip, the refreshed candidate and its validation result. `backup/refresh.jac`
attaches it to each result. The current report expires at the earliest supporting
deadline, including evidence for the original target used in the comparison.
The existing UI clears the comparison together with the current result after
input changes, expiry, failures or another tab's refresh.

Snapshots save these metrics with their original inputs. History labels them
**Changes when recorded**; reopening never restores a current conclusion.
Older snapshots without metrics still load and explicitly say that metrics were
not recorded. They are never backfilled or recalculated using later prices.
The database schema and existing endpoint signatures are unchanged.

The deterministic `jac run backup/refresh_demo.jac` output also includes the
change object for each inventory transition.

## Change-explanation slice verification — 2026-10-28

For the later combined verification, see [WORKFLOW.md](WORKFLOW.md).

Local runtime: Jac 0.37.21; manifest-pinned 0.37.23 is not verified.

- 12 new metric tests plus one legacy-history compatibility test pass.
- Focused metrics/refresh/history/HTTP suite: **45 passed**.
- Complete service/backup suite: **93 passed, 1 existing MockLLM selection
  failure** in `server/main.test.jac`. All new tests pass.
- Four app checks and the standalone `backup_refresh` client build pass.
- Deterministic CLI prints eight JSON observations with change metrics.
- Browser checks cover the two scenarios, price increase, provider failure,
  input-change clearing, reload without a current result, saved historical
  amounts and keyboard disclosure. At 390px the document width is 390px; no
  browser console errors were observed.
- HTTP tests compare the saved-trip SQLite dump before/after operations. The
  browser uses a separate temporary history database and creates no travel DB.

The previously recorded full-travel generated JavaScript build blocker remains
outside this change; no full-app build or clean-install CI success is claimed.
