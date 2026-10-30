# Selecting and backfilling backup alternatives

Gehao Dong's backup workflow evaluates the complete supported synthetic pool
before choosing Plan B/C. If an original option becomes over budget, unavailable
or otherwise invalid, another evaluated option can fill its place. Generation
and refresh leave the original itinerary unchanged.

## Selection policy

1. Search, screen and deduplicate inventory; materialize all supported candidates.
   Each scenario currently has four candidates. Rain search also records two
   excluded inventory rows, so its trace shows six searched and four evaluated.
2. Validate each complete proposed itinerary, refresh each candidate's own provider
   ID, and validate again. Failed refreshes discard prior evidence.
3. Take up to two passing candidates in provider search order. Fill any remaining
   slots with received but unresolved candidates labeled **Needs confirmation**.
   Failed requirements and provider errors never qualify for a display slot.
4. Assign Plan B/C as display labels. Provider and candidate IDs remain stable;
   a newly displayed Plan B does not inherit the previous Plan B's observations.
5. Save all inputs, evaluated options, selection decisions and selected IDs.
   Display only selected cards, or an explicit single-option/no-option message.

This is deterministic feasibility selection, with no preference score or price
optimization. Passing options precede unresolved ones; original search order is
preserved within each group. The cheap library and rooftop restaurant fixtures
deliberately fail family requirements, demonstrating that price cannot bypass
pet, dietary or accessibility constraints. Full-itinerary budget, time, transfer
and protected-item checks still apply to every candidate.

## Try the normal demo

From `travel-planner/`, run:

```sh
jac run --host 127.0.0.1 --port 8350 backup_refresh
```

Choose **Synthetic sample trip**, the family requirements, a future sample date,
and **Find backup plans**. Amounts below are whole-trip totals, including reserve
and retained original payment; they are not a new amount due.

| Scenario and budget | Plan B | Plan C |
| --- | --- | --- |
| Rain, USD 600 | Indoor discovery gallery, USD 440 | Covered botanical hall, USD 470 |
| Rain, USD 450 | Indoor discovery gallery, USD 440 | Covered market visit, USD 425 |
| Delayed arrival, USD 390 | Late noodle dinner, USD 389 | No second eligible option |
| Rain or delayed arrival, USD 300 | Explicit budget message | No options |

Normal Roam and demo pages show alternatives and useful uncertainty/failure
messages. They do not render checks, search traces, provider IDs or saved history.
Saved Roam inputs use the same selection engine; incomplete traveler, quote,
timing and route facts remain unresolved and never become a passing claim.

## Diagnostics and recorded decisions

Open the standalone app with `?diagnostics=1` to enable inventory transitions.
With rain, family requirements and USD 600:

| Inventory transition | Result |
| --- | --- |
| First option price increase, sold out, expired evidence or provider failure | Botanical hall USD 470 and covered market USD 425 fill the two slots |
| All alternatives sold out | No cards; explicit sold-out message |
| All providers fail | No cards; retry message |

**Candidate selection decisions** lists every evaluated provider and its selected,
requirements-failed, provider-unavailable or display-limit reason. The price
increase retains the rejected gallery's USD 640 total and failed budget check.
**Recorded selection decisions** preserves the original decision after reopening.
Returning to the plain URL resets hidden inventory fault controls to unchanged.

Reports distinguish selected `results`/`summary` from `evaluated_options`/
`evaluated_summary`. `selection` contains the policy version, outcome, message,
selected provider IDs and all decisions. Pipeline `provider_ids` covers all
evaluated candidates; `selected_provider_ids` covers only the displayed subset.

Storage uses validator version `backup-selection-v2` with the existing SQLite
schema. Pre-selection snapshots still load as history, without invented decisions.
Old request retries return `version_changed`; they cannot become current under the
new policy. Reopening restores controls and history, then requires an explicit
new search. Existing expiry, revision and trip-content checks remain in force.

The persisted sample/saved-trip paths and `backup/refresh_demo.jac` use the expanded
pool. Legacy preview and stateless validation/refresh endpoints keep their earlier
two-candidate fixture behavior; `run_fixture(..., expanded=True)` opts in explicitly.
Shared team contracts, live inventory, booking and applying alternatives remain
outside this module-owned slice.

## Verification — 2026-10-29

Local runtime: Jac 0.37.21; manifest-pinned 0.37.23 and clean-install CI are unverified.

```sh
jac test server/main.test.jac server/test_backup.jac server/test_validation.jac server/test_refresh.jac server/test_history.jac server/test_backup_workflow.jac backup/test_planner.jac backup/test_validation.jac backup/test_refresh.jac backup/test_history.jac backup/test_changes.jac backup/test_workflow.jac backup/test_selection.jac
jac check --nowarn
jac build backup_refresh --as client
jac run backup/refresh_demo.jac
```

- Combined regression: **117 passed, 1 existing replanning MockLLM failure** at
  `server/main.test.jac:217`. All 12 new selection/history tests pass.
- Four application checks and the standalone backup client build pass.
- Eight deterministic CLI observations cover unchanged inventory, price increase,
  sold out, all sold out, expired evidence, full/partial provider failure and recovery.
- Tests verify hard-requirement rejection, one/no-option outcomes, unresolved
  evidence, stable IDs, deterministic order, immutability, JSON selection roundtrip,
  missing providers, expiry, historical compatibility and saved-trip preservation.
- Browser checks on isolated temporary databases confirm the USD 450 backfill,
  USD 390 single dinner, USD 300 budget message, price increase, all sold out,
  provider failure, keyboard disclosure of decisions and persisted decisions after
  reload. Returning to the plain URL restores normal inventory. Saved-trip cards
  remain **Needs confirmation**; the trip/item records match their original fixture.
- Normal sample and saved-trip pages render zero diagnostic sections. At a 390px
  viewport, document width is 390px with no horizontal overflow; no browser console
  errors were observed. The shared component was exercised through `backup_refresh`.

The known full-Roam generated replanning JavaScript build blocker was last
reproduced on October 28. This slice does not establish a passing full-Roam build.
