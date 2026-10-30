# Roam — Travel Planner

Roam is a personal travel planner built with **Jac 0.37.23**, following GoPlanner's web + CLI + shared SQLite service structure. Keep multiple trips, daily itineraries, reservations, packing lists, notes, and costs together in one workspace.

Application code, backend helpers, demos, and tests are written in `.jac` files. Jac imports Python standard-library modules for SQLite, dataclasses, date/time handling, and CLI argument parsing; no project-owned Python source files are required.

## Features

- **Trips:** Create and edit a trip name, destination, departure/return dates, currency, budget, and notes. Switch between saved trips; upcoming, current, and past status follows the local calendar.
- **Itinerary:** Add activities, dining, flights/transport, and stays. Dates and local 24-hour times are optional; dated items sort chronologically, with timed items before flexible plans and undated ideas last. Filter by day, edit details, and complete/reopen items.
- **Bookings:** Store locations, confirmation references, and notes for transport and stays. Confirm/reopen reservations. The same record appears in the itinerary, bookings, and budget; it is not duplicated.
- **Packing:** Add essentials and check them off. Packed/total counts appear in the trip summary.
- **Budget:** Record costs on itinerary/booking items and add other costs such as insurance or shopping. Track planned total, paid total, unpaid total, remaining budget, and overspending. Mark payment independently from confirmation or completion.
- **Connected backup plans:** Address detected risks or traveler-reported changes with up to five different venue, timing or connected-item plans. P1 profile/filter/ledger, P2 risk/policy and P4 version-safe application now connect through a typed alternative contract. Compare and explicitly accept simulated changes from **Backup plans**. [Connected flow and limits](planning/README.md).
- **Backup validation:** Check complete proposed itineraries for traveler requirements, costs, scheduling, opening hours, routes, dependencies and fixed items. Missing facts remain unresolved and cannot be accepted. Passing has explicit synthetic scope. [Integration](planning/README.md) and [legacy validator](backup/VALIDATION.md).
- **Backup refresh:** Reconfirm inventory before acceptance; changed prices, sold-out or expired evidence and provider failures block old conclusions. The standalone sample lab retains its explicit fault-injection scenarios. Search and refresh do not change active itinerary items. [Refresh demo](backup/VALIDATION.md#refreshing-synthetic-inventory).
- **Saved refresh history:** Store versioned sample and saved-trip observations separately from trips, inspect historical outcomes in diagnostics and restore controls after reopening. Current checks always require an explicit refresh. [Storage and UI guide](backup/HISTORY.md).
- **Candidate backfill:** Refresh and validate the full synthetic pool before selecting up to two alternatives. Rejected or unavailable options can be replaced by other eligible candidates; a single option or no solution is explained explicitly. Normal demo pages hide diagnostic records. [Selection policy and examples](backup/SELECTION.md).
- **Replanning:** Simulate delayed/interrupted items, combine synthetic backup inventory, edit dependencies and schedule rules, optionally use a Jac LLM to select combinations, and accept/reject version-safe revisions. Try the separate demo trip from the sidebar; see [the replanning guide](replan/README.md).
- **Persistence:** Web and CLI share `.jac/data/travel.sqlite3`, independent of GoPlanner. Stable IDs, transactional writes, date/time/amount validation, and deletion confirmations protect your records.
- **Responsive design:** A business-style navy, slate, and white interface with a flat trip overview, trip sidebar, overview cards, and five planning tabs. The web interface adapts to phones and tablets.

## Guided backup and replan demo

For the connected P1/P2/P3/P4 flow, choose **Try connected backup plans** in the
sidebar, or the weather/arrival-delay sample buttons in **Backup plans**. Those
plans are directly reviewed and passed to P4. The older guided demo below is
retained as a separate legacy example.

Click **Start backup & replan demo** in the sidebar. Each start saves a separate Boston/USD trip with six scheduled items, a USD 1,500 budget, dependencies and a protected museum visit.

1. **Generate backups:** Dinner is preselected. Click **Find backup plans** to fetch up to two synthetic dining alternatives. For rain backups, select the rain scenario and **Outdoor harbor walk**.
2. **Simulate & replan:** Continue, keep **Flight arrival** delayed by **180 minutes**, and click **Generate replan options**. Compare three alternatives, optionally build a custom combination, then accept or reject a proposal.
3. **Updated itinerary:** Acceptance persists the revision and opens an original-versus-saved schedule with revised costs. Click **Open updated itinerary** to inspect the regular workspace.

Backup previews and proposal generation leave itinerary items unchanged. Acceptance updates only this demo trip. The backup preview catalog and replanning catalog are separate synthetic modules; preview cards are not directly applied. No provider credentials are required.

## Workspace navigation

Use the three workflow shortcuts to **build your itinerary → generate backup plans → replan a disruption**.

- **Itinerary:** Add and edit the active trip's activities, meals, stays and transport.
- **Backup plans:** Record traveler/trip facts, select detected risks or report a change, compare up to five complete alternatives, reject or explicitly accept a validated simulated plan.
- **Replan:** Report a delay or interruption, generate replan options, compare changes and explicitly accept or reject a revised plan. Expand **Schedule rules and dependencies** to configure timing and connections; customize backup combinations below the proposals.
- **Bookings, Packing list, Budget:** Manage reservations, essentials and trip spending.

The connected Backup plans flow applies only after explicit acceptance. The
legacy stateless previews and separate sample lab remain read-only.

## Start the app

From this folder:

```sh
jac --version
jac install
jac run --dev travel
```

Open the **App** URL printed by Jac. Create a trip, then add details using the itinerary, bookings, packing, and budget tabs. Use **Edit trip** for notes or a budget. Refresh to see changes made through the CLI or another browser.

If Jac is missing from your shell:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

A fresh clone does not include `.jac/venv`. Use a working Jac installation to provision dependencies; do not rely on another developer's sibling project. The manifest pins Jac 0.37.23; see the [verification boundary](../docs/PROGRESS.md#latest-verification-boundary) for dated validation results.

## CLI

Keep the web/server running. Set the bridge URL using the printed **API** URL, with `/api/server` appended. Replace the example port with your actual port:

```sh
export JAC_APP_SERVER_URL="http://127.0.0.1:8002/api/server"

jac run cli -- new "Kyoto week" "Kyoto, Japan" --start 2026-11-01 --end 2026-11-07 --currency USD --budget 2500 --notes "Remember the train tickets"
jac run cli -- trips

# Replace TRIP_ID with an ID from trips, or a unique prefix.
jac run cli -- add TRIP_ID "Hotel check-in" --category stay --date 2026-11-01 --time 15:00 --reference ABC123 --cost 900
jac run cli -- add TRIP_ID "Temple walk" --date 2026-11-02 --time 09:00 --location "Higashiyama" --cost 12.50
jac run cli -- add TRIP_ID "Passport" --category packing
jac run cli -- add TRIP_ID "Travel insurance" --category expense --cost 65
jac run cli -- show TRIP_ID

# Replace ITEM_ID with an ID from show, or a unique prefix.
jac run cli -- done TRIP_ID ITEM_ID
jac run cli -- reopen TRIP_ID ITEM_ID
jac run cli -- paid TRIP_ID ITEM_ID
jac run cli -- unpaid TRIP_ID ITEM_ID
jac run cli -- delete-item TRIP_ID ITEM_ID
jac run cli -- delete-trip TRIP_ID --yes
```

Editing trip and item details is available in the web app. CLI `done` means completed, confirmed, or packed depending on category; `paid` changes only payment status.

## Backup preview demo

The current saved-trip UI uses the [connected planning flow](planning/README.md).
This section describes the preserved legacy preview APIs and sample/history lab.

From `travel-planner/`, run the deterministic, storage-free demo:

```sh
jac run backup/demo.jac
```

In the standalone `backup_refresh` app's sample view, choose rain or delayed
arrival and **Find backup plans**. The legacy saved-trip panel can be inspected
through its explicit diagnostics entry. These fixture endpoints retain their
search, refresh, history and evidence-expiry behavior.

Unsupported locations/currencies show an empty result or exclusion reasons.
The legacy endpoints preserve saved trip/items and costs; missing facts remain
unresolved. Their current and historical results retain change explanations.
See the [legacy workflow guide](backup/WORKFLOW.md).

The original `backup/models.jac`, `preview_backups`, `load_trip_backup_history`
and `save_trip_backup_refresh` remain compatible. New connected proposals use
`schema/alternative.jac` and the service interfaces in [planning/README.md](planning/README.md).

### Standalone full-itinerary validation demo

The implementation in [PR #23](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/23) adds a separate synthetic validation lab. From this folder:

```sh
jac run backup/validation_demo.jac -- --scenario rain --budget 450
jac test backup/test_validation.jac
```

This legacy CLI example returns a USD 440 whole-trip Plan B that passes the implemented fixture checks and rejects a USD 470 Plan C against the USD 450 budget. The current `backup_refresh` page uses the expanded pool and fills that second slot with the eligible USD 425 covered market. It offers **Synthetic sample trip** and **Find backup plans**; Roam's **Backup plans** tab uses the selected saved itinerary. Both default to a presentation view without developer check records. Add `?diagnostics=1` to the standalone URL to inspect search traces, checks and history. A passing fixture result is not shared-validator approval or permission to book/apply a replacement. See [the validation guide](backup/VALIDATION.md) and [the current workflow guide](backup/WORKFLOW.md).

To run the changing-inventory sequence and its isolated web demo:

```sh
jac run backup/refresh_demo.jac
jac test backup/test_refresh.jac server/test_refresh.jac
jac run --host 127.0.0.1 --port 8320 backup_refresh
```

Fresh results include **What changes?** explanations for original/proposed totals,
cost differences, budget remaining and elapsed-time changes. History preserves
the recorded values. See [backup change explanations](backup/CHANGES.md) for
examples, calculation semantics and verification.

### Browser regression check

Start a separate test instance with an isolated database, using the App/API ports printed by Jac:

```sh
TRAVEL_DB_PATH=/tmp/roam-backup-browser.sqlite3 jac run --dev travel
```

In another terminal, install Playwright into a temporary test environment and run the browser checks with installed Chrome:

```sh
npm install --prefix /tmp/roam-browser-check playwright
NODE_PATH=/tmp/roam-browser-check/node_modules \
TRAVEL_BROWSER_CHANNEL=chrome \
TRAVEL_APP_URL=http://localhost:8000 \
TRAVEL_API_URL=http://localhost:8001/api/server \
node tests/backup_preview.browser.cjs
```

The script creates and deletes its own synthetic trips. It checks both scenarios, mobile overflow, clearing results, request errors, delayed responses, empty states, automatic expiry/refresh and preservation of saved data. Override the URLs if Jac prints different ports. Without `TRAVEL_BROWSER_CHANNEL`, Playwright uses its installed Chromium instead.

## Project structure

| Component | Files | Purpose |
| --- | --- | --- |
| Web | `main.jac`, `frontend.jac`, `frontend.impl.jac`, `styles.css` | Trip workspace and responsive browser UI |
| Service | `server/main.jac` | Shared trip/item API, validation, and SQLite storage |
| CLI | `cli/main.jac` | Terminal commands using the same service |
| Standalone backup validation | `backup/validation.jac`, `backup/validation_models.jac`, `backup/validation_fixtures.jac`, `backup/validation_demo.jac`, `backup/validation_frontend.jac` | Synthetic full-itinerary checks, CLI and read-only lab from PR #23 |
| Tests | `server/main.test.jac`, `backup/test_planner.jac`, `backup/test_validation.jac`, `server/test_backup.jac`, `server/test_validation.jac`, `tests/backup_preview.browser.cjs` | Service regressions, draft screening, full-itinerary validation, read-only storage checks, and browser states/expiry |
| Configuration | `jac.toml` | Jac version, dependencies, and app declarations |

## Data and planning rules

Set `TRAVEL_DB_PATH` before starting the service to use another SQLite file. `.jac/` contains dependencies and saved data and is ignored by Git. Keep it to preserve your local trips.

All costs in a trip use its selected currency, represented with two decimal places; there is no exchange-rate conversion. Currency changes are blocked while a trip has costs. A blank or zero budget means no budget is set. Add each cost once: if a booking already has a cost, mark that record paid instead of creating another expense for the payment.

Dated items must fall within the trip dates. Changing a trip's dates is blocked if existing dated items would fall outside them. Move those items first. Packing records have no dates or costs. Deleting a trip removes all its records. Times are destination-local; no automatic timezone conversion is performed.

Roam records your plans and booking details; it does not make reservations. This is a local personal app with public service endpoints, following GoPlanner's access model.

## Validation

```sh
jac check --nowarn
jac test server/main.test.jac
jac test backup/test_planner.jac
jac test server/test_backup.jac
jac test backup/test_validation.jac
jac test server/test_validation.jac
jac test backup/test_refresh.jac server/test_refresh.jac
jac build travel --as client
jac test backup/test_history.jac server/test_history.jac
jac test backup/test_changes.jac
```

Tests use temporary SQLite databases. They do not read or modify your saved trips.
