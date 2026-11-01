# Reproduce the connected planning build

This is the verification path for the mock Boston/USD implementation delivered
to main by PR #36. It does not approve the proposed shared
contracts or merge any PR. Use Python **3.14** and the checksum-pinned Jac
**0.37.23** binary; no sibling project or copied virtual environment is needed.

## Setup and checks

From the repository root:

```sh
bash scripts/setup.sh
bash scripts/verify.sh
```

`ROAM_PYTHON` can select a Python 3.14 executable. The setup script installs Jac
under `.tools/`, checks the official release checksum, creates a new
`travel-planner/.jac/venv` if needed, and installs the declared development and
client dependencies. It supports macOS arm64 and Linux x86_64/aarch64.

Verification fails on any required command failure. It runs four application
checks, all service/feature tests, both client builds, the three planning CLI
scenarios and a complete sealed build. It then starts separate disposable
localhost servers for source and packaged code, each with independent SQLite
stores. The packaged server starts outside the source tree with
`JAC_PRECOMPILE_REQUIRED=1`, so a missing executable artifact cannot be hidden by
source compilation.
Ports are selected from available localhost ports; an explicitly requested
`ROAM_SMOKE_PORT` must be free. Readiness also checks that the started process
is still running.

The HTTP checks cover the root page and referenced JS/CSS, explicit simulated
runtime metadata, three weather/five arrival alternatives, rejection without
stored-item changes, acceptance matching the reviewed candidate and trip-version
advancement. CLI `new`, `add` and `show` must work against both servers.
`_jac_id` is a per-response wire-object identity; persistence comparisons exclude
only that field, retaining the actual saved `id` and all other fields.

Logs are written to `.ci/reports/`, synthetic stores to `.ci/runtime/`, and the
bundle to `.ci/artifacts/travel-planner.jab`. These paths are ignored by Git.
`JAC_BIN` may select an existing Jac 0.37.23 executable for verification.

## Jac 0.37.23 packaging compatibility

Use this build command from the repository root:

```sh
.tools/jac-0.37.23 run --no-takeover scripts/build_jab.jac
```

The stock sealer starts its precompiler in the original checkout's working
directory. Some staged imports then resolve class declarations at the original
path while others resolve the copied path. We reproduced the resulting
`Cannot assign TripView to TripView` / `BackupCandidate to BackupCandidate`
errors with a new compiler cache and compared their actual canonical paths.
Running the same unit with a neutral working directory succeeded.

The version-guarded compatibility script changes only the precompiler child's
working directory to its staging tree. It retains the normal type checks, JIR
compiler-identity checks, complete manifest and seal finalization; it changes no
installed Jac files. `main.jac` also exposes read-only `application_info` so the
sealed root has executable server bytecode in addition to its colocated service.
Review this compatibility code when upgrading Jac; do not silently carry it to
another release. Raw `jac build travel` still has the upstream working-directory
bug; the supported project command above is the verified path.

The CLI explicitly supplies empty creation IDs to Jac's service bridge.
Otherwise 0.37.23 loses those defaults and reports missing `trip_id` / `item_id`
before making the request. The server API's default values and JSON fields are
unchanged.

## Run the packaged app

From the repository root, choose explicit persistent data paths:

```sh
TRAVEL_DB_PATH="$PWD/travel-planner/.jac/data/travel.sqlite3" \
BACKUP_HISTORY_DB_PATH="$PWD/travel-planner/.jac/data/backup-history.sqlite3" \
.tools/jac-0.37.23 run --no-dev --host 127.0.0.1 --port 8360 \
  .ci/artifacts/travel-planner.jab
```

Both freshly installed source mode and the sealed package serve the root page
and complete the connected flow in non-development mode. The earlier 404 was
not reproduced in these clean environments. Backend edits in development mode
may still require a process restart because HMR can retain imported modules.

## Verification record — 2026-10-30

On macOS arm64 with Python 3.14.7 and Jac 0.37.23, a new source export with no
`.jac` directory or copied dependencies completed `setup.sh` and `verify.sh`:

- **387 tests passed**; **four application entries passed**.
- Travel and standalone backup client builds passed.
- CLI planning scenarios produced 3 / 5 / 5 valid plans.
- The compatibility build compiled 45 application modules and sealed a verified
  46-module manifest with six payload files.
- Source and source-compilation-forbidden artifact HTTP/CLI smoke checks passed,
  including exact candidate acceptance and rejection preserving stored items.
- The packaged app rendered in a browser without console errors; accepting the
  gallery alternative saved the expected USD 375 total and success notice.

The GitHub workflow in `.github/workflows/jac.yml` uses the same scripts on
Ubuntu 24.04, pins its actions by commit, and preserves logs on failure. It is
provided with the review branch. This October 30 local record is separate
from the successful November 1 hosted run recorded below.
Live providers/models, external bookings/payments/cancellations, public
multi-user deployment and team contract approval are outside these checks.

## Publication verification — 2026-11-01

The complete setup/verification sequence passed again in the current checkout:
387 tests, four application checks, both client builds, 3/5/5 planning scenarios,
the 46-module sealed package, and both source/package HTTP and CLI smoke checks.
This repeat run used the existing checkout; the independent clean-install
evidence is the October 30 source-only run above. Browser results above retain
their original date and were not rerun as part of this command-line verification.

## GitHub-hosted verification — 2026-11-01

[Run #2](https://github.com/howarddong0485/Travel-Disruption-Replanner/actions/runs/41315449524)
passed on Ubuntu 24.04/Linux x86_64 with Python 3.14 and Jac 0.37.23 at code
baseline `83fee9617bf152c86f153ddfbc387f18b09223b4`. It confirms 387 tests,
four app checks, two client builds, 46 sealed manifest modules and both source
and sealed HTTP/CLI smoke checks. Verification logs were uploaded as
`jac-verification` with seven-day retention. This supersedes the earlier pending
hosted-CI gate, while retaining the original dates/scopes of local/browser checks.

See [MVP_STATUS.md](MVP_STATUS.md) for remaining feature work and review gates.

## Pre-merge review corrections — 2026-11-01

Code commit `a92e3da` fixes all five reproduced backend review findings: retain
all activations per changed item; reconcile deleted/excluded supplemental item
references while rejecting new foreign writes; preserve booking metadata on
reschedule; use identical derived activation semantics for generation/acceptance;
and bound reviewed finances by cancellation deadlines and policy evidence.
Validator v2 rejects older stored proposals.

The history and connected panels dispatch mount listeners through the current
callback and drain queued checks after loading/refresh. The history correction
was also delivered in #31 as `fe4d4df`. Browser checks in two tabs per panel
verified that another tab's update clears the old results; neither panel logged
a console error.

The full pinned local verification passed: **419 reported tests**, four app
checks, both client builds, 3/5/5 planning scenarios, the 46-module sealed package
and both source/package HTTP/CLI checks. The seven new regression cases were
added in `planning/test_review.jac` and `planning/test_service.jac`. The reported
total includes imported companion checks. See the [final PR checks](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/36/checks)
for hosted verification of the final delivery revision.

## Final review corrections — 2026-11-01

`f8dcf35` filters dependency endpoints when items leave the scheduled-node set,
invalidates evidence when item facts are edited without confirmation, and
replaces the original venue's supplemental hours with the newly observed
provider hours. The category-change and provider-hours regressions detect the
old failures. A browser reproduction changed a retained item's admission age:
before the fix, saving without confirmation still yielded selectable plans;
after the fix all three were unresolved with disabled acceptance, and explicit
confirmation restored three selectable plans without console errors.

The complete pinned local sequence passed again with **420 reported tests**,
four app checks, two client builds, the 46-module sealed package and both
source/package HTTP/CLI checks. There are eight added regression cases across
`planning/test_review.jac` and `planning/test_service.jac`; imported companion
checks are included in the reported total. The earlier 419-test run records
`a92e3da` before this follow-up. See [final PR checks](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/36/checks)
for hosted verification of the final delivery revision.


### Saving edits after confirmation

The final review additionally reproduced an HTTP save failure when edited item
facts lost their evidence but retained opening-hours records citing that evidence.
Context loading and payload validation now remove only those derived records;
independent evidence remains, and unknown/foreign references still fail validation.
The added HTTP regression covers confirm/save, edit/save without confirmation,
disabled plans, explicit reconfirmation restoring valid plans, and invalid evidence
rejection. Browser verification saved a previously confirmed dinner edit, showed
three Needs confirmation alternatives with all acceptance buttons disabled, and
reported no console errors.

The final complete pinned sequence passed **421 reported tests**, four app checks,
both client builds, CLI alternatives **3 / 5 / 5**, the 46-module sealed package,
and isolated source/package HTTP/CLI checks. Nine added regression cases cover
the pre-merge review corrections. Earlier 419/420 counts above are historical.


### Dated hours and distinct follow-up plans

The next review reproduced two additional failures: same-venue reschedules could
ignore a supported closed-day record, and Find other plans repeated the displayed
candidates. Validator v3 now uses the dated supplemental hours, preserves unknowns
when their evidence is stale/incomplete, and caps the review by that evidence.
The acceptance regression rejects a formerly selectable closed-day reschedule
before any write. Request-another accumulates stable candidate exclusions, includes
them in idempotency checks and leaves prior proposals and active items unchanged.
The HTTP bridge's literal empty-list default is normalized for old callers.

The full pinned sequence passed **423 reported tests**, four app checks, both
clients, CLI alternatives **3 / 5 / 5**, complete 46-module sealing and isolated
source/package HTTP/CLI checks. Eleven added regression cases cover the review
corrections. Browser verification advanced through **3 → 2 → 0** distinct options,
showed the exhausted-pool message, retained the itinerary and had no console
errors. The earlier 421-test record remains historical.


During this verification, sealing first stopped because documentation changed
while preparation was running. The already-passing 423-test/four-check/client
results were retained. After files were held stable, the same verification
script's sealing and source/package HTTP/CLI phases were rerun successfully;
the 46-module package and both runtime checks passed. No backend source changed
between these phases. Hosted CI runs the final committed tree from the start.
