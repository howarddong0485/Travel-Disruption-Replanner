# Standalone backup validation

This module validates synthetic Plan B / C proposals against an entire sample
itinerary. It is independent of teammates' schemas and services. The fixture
panel lives inside Roam, and never reads or writes saved trips. Week-one
`preview_backups` behavior is unchanged.

## Run

From `travel-planner/`:

```sh
python3 -m backup.validation_demo --scenario rain
python3 -m backup.validation_demo --scenario arrival_delay --budget 400
python3 -m backup.validation_demo --scenario missing_evidence
python3 -m unittest backup.test_validation -v
jac test server/test_validation.jac
jac run --host 127.0.0.1 --port 8310 travel
```

Open `http://127.0.0.1:8310/`, expand **Plan B / C · Validation lab**, and choose
**Run sample checks**. No saved trip is required. A USD 400 family budget rejects
both rain options; USD 600 allows them. Empty budget means unknown, not zero.
Changing a control clears prior results. Results clear after 15 minutes and can
be refreshed by running the sample again.

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

- `validation_models.py`: module-owned input records.
- `validation.py`: pure validator, with no database or provider dependencies.
- `validation_fixtures.py`: synthetic facts and isolated scenario runner.
- `validation_demo.py`: reproducible CLI.
- `validation_frontend.jac`: Roam fixture panel.
- `server.main.preview_backup_validation`: thin local demo entry point.

The validator is not the authoritative shared project validator. Shared risk,
profile, budget and itinerary mapping, real inventory, persistence, acceptance,
and applying changes are not integrated. All passing statuses explicitly retain
the fixture scope.
