# Reproduce the connected planning build

This is the local verification path for the mock Boston/USD implementation on
`codex/connected-backup-planning`. It does not approve the proposed shared
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
