# Standalone backup validation

This module validates synthetic Plan B / C proposals against an entire sample
itinerary. It is independent of teammates' schemas and services. The fixture
panel lives inside Roam, and never reads or writes saved trips. Week-one
`preview_backups` behavior is unchanged.

## Run

From `travel-planner/`:

```sh
jac run backup/validation_demo.jac -- --scenario rain
jac run backup/validation_demo.jac -- --scenario arrival_delay --budget 400
jac run backup/validation_demo.jac -- --scenario missing_evidence
jac test backup/test_validation.jac
jac test server/test_validation.jac
jac run --host 127.0.0.1 --port 8310 travel
```

Open `http://127.0.0.1:8310/`, select a trip, open **Backup plans**, expand **Explore validation with a sample trip**, and choose
**Refresh and recheck Plan B / C**. Select or create a trip to access the panel; sample checks do not use its saved data. A USD 400 family budget rejects
both rain options; USD 600 allows them. Empty budget means unknown, not zero.
Changing a control clears prior results. Results clear within 15 minutes, or
earlier when contributing evidence expires, and can be refreshed again.

Seven scenarios cover rain, late dinner, missing evidence, hard requirement
conflicts, schedule conflicts, protected targets, and stale evidence. Family
requirements include two adults, an eight-year-old child, vegetarian meals, a
dog, and wheelchair access. The solo profile has no additional hard requirements.
The CLI uses a fixed aware clock by default; `--now` changes it. The web demo uses
the current server clock and places the sample trip seven days later.

## Semantics

- `passed_fixture_checks`: every implemented check passed using synthetic facts.
- `invalid`: at least one definite violation. Missing facts remain visible too.
- `needs_validation`: no definite violation, but evidence or inputs are incomplete.

Each proposal replaces exactly one existing item, retaining its ID. Fixed and
completed items cannot be replaced. The validator copies inputs and returns a
whole proposed itinerary, check reasons, costs, and the base-trip fingerprint.
Each candidate is checked independently; Plan B / C order is not a ranking.

Times carry an IANA timezone and are compared in UTC. Nonexistent DST times
fail; ambiguous times require an explicit fold. The entire visit must fit an
operating window and trip dates. Consecutive blocking events need fresh,
venue-matched transfer estimates. Explicit dependencies must fit and be acyclic.
Only lodging may be nonblocking; a check-in appointment should be its own
blocking item.

Hard requirements apply to all applicable itinerary items, including unchanged
ones. Dietary requirements apply to meals; pet, wheelchair and child admission
requirements apply across the itinerary. Indoor evidence is required for the
rain replacement. Soft interests never override hard failures.

Prices are integer USD cents for the entire party, including taxes and fees.
The projected total includes all proposed items, the reserve, and the replaced
item's original payment. No refund is assumed. Payments on retained items are
already part of their total quotes and are not counted twice. Missing quotes,
party coverage, payment history or foreign currencies leave the total unknown.
Each source has an observation and expiry time; expired or blank evidence cannot
establish a pass. Fixtures make no claims about real venues or availability.

## Files and scope

- `validation_models.jac`: module-owned input records.
- `validation.jac`: pure validator, with no database or provider dependencies.
- `validation_fixtures.jac`: synthetic facts and isolated scenario runner.
- `validation_demo.jac`: reproducible CLI.
- `test_validation.jac`: 26 native Jac boundary tests.
- `validation_frontend.jac`: Roam fixture panel.
- `server.main.preview_backup_validation`: thin local demo entry point.
- `refresh.jac`: independent synthetic observations and fresh full-trip checks.
- `refresh_demo.jac` / `refresh_app.jac`: CLI sequence and standalone web entry.
- `test_refresh.jac` / `server/test_refresh.jac`: refresh boundaries and saved-trip isolation.
- `server.main.refresh_backup_validation`: refresh entry point used by the panel.

The validator is not the authoritative shared project validator. Shared risk,
profile, budget and itinerary mapping, real inventory, persistence, acceptance,
and applying changes are not integrated. All passing statuses explicitly retain
the fixture scope.

## Refreshing synthetic inventory

The versioned-history follow-up saves observations and adds history to this panel; see
[saved refresh history](HISTORY.md) for storage, restoration and retry semantics.
The stateless refresh endpoint described below remains available for compatibility.

The original refresh slice uses `refresh_backup_validation`, while the existing
`preview_backup_validation` and Week 1 preview calls retain their behavior.
Choose **Inventory on next refresh**, then **Refresh and recheck Plan B / C**.

| Inventory snapshot | Expected family / USD 600 result |
| --- | --- |
| Fresh original prices | Plan B USD 440, Plan C USD 470: both pass fixture checks |
| Plan B price increase | Whole-party quote rises by USD 200; total USD 640 is rejected |
| Plan B sold out | Plan B rejected; Plan C still passes |
| Both sold out | No passing alternative, with availability reasons |
| Expired evidence | Plan B needs validation; old price is not shown as a current total |
| Both providers fail | Both need validation; old prices, policies and routes are discarded |
| Plan B provider fails | Plan B needs validation; Plan C is checked independently |
| Fresh original prices again | New observation can recover both candidates |

Snapshots are independent, not cumulative price adjustments. The sample date
stays fixed across refreshes, even across midnight. Controls changing, a request
starting, and report expiry all clear prior results. A request identity prevents
an obsolete response from restoring an old result; already-expired responses
are discarded. There are no booking/apply controls.

`backup/refresh.jac` copies its input, fetches deterministic synthetic candidate
observations, and reruns the whole-itinerary validator. It does not extend the
expiry of retained trip/risk evidence or invent missing requirements, operating
hours or routes. Passing results expire at the earliest contributing evidence
deadline. Failed/unresolved reports have no `valid_until`; their display can be
retained for up to 15 minutes to explain the failure.

The demo runner supplies a fresh synthetic trip/risk fixture on every run while
preserving the sample date. This is deliberately separate from real saved-trip
facts. The core refresh function accepts existing trip/risk snapshots and keeps
expired retained evidence unresolved. It does not implement upstream integration.
Each report has a unique refresh ID and each result has an evidence fingerprint;
these are transient observations, not persisted or authoritative trip versions.

Run the sequence and tests from `travel-planner/`:

```sh
jac run backup/refresh_demo.jac
jac test backup/test_refresh.jac server/test_refresh.jac
```

The same panel also has an independent web entry, so other feature UIs are not
needed for the demo:

```sh
jac build backup_refresh --as client
jac run --host 127.0.0.1 --port 8320 backup_refresh
```

Open `http://127.0.0.1:8320/` and expand the validation lab. This demo uses the
existing shared styles and the exact component included in Roam.

### Local verification — 2026-10-28

On Jac **0.37.21**, all four app entrypoint checks and the standalone
`backup_refresh` client build pass. After incorporating main `fc118b0` (including
the guided demo and renamed navigation), the combined suite has **64 passed, 1 failed**,
including 15 new core refresh cases and one new HTTP/database isolation case.
The remaining failure is the previously recorded replanning MockLLM test. The
full `travel` client build still fails at the previously recorded computed
property in generated `replan/frontend.js`. Pinned Jac 0.37.23 and clean-install
CI are not verified. Persistence, live providers and shared-agent handoff are
outside this implementation.

Before that rebase, browser checks on the standalone entry verified all seven inventory selections,
recovery to original prices, clearing results on inventory/budget changes,
both alternatives rejected at USD 400, and a readable error for an invalid
budget. Provider failures showed unknown costs instead of old passing quotes.
The sample date remained unchanged through those refreshes. The 15-minute
client timer and late-response guard were reviewed in source; expiry boundaries
were tested with a deterministic server clock, not a real-time browser wait.
