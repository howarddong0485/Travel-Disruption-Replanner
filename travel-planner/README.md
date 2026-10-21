# Roam — Travel Planner

Roam is a personal travel planner built with **Jac 0.37.23**, following GoPlanner's web + CLI + shared SQLite service structure. Keep multiple trips, daily itineraries, reservations, packing lists, notes, and costs together in one workspace.

## Features

- **Trips:** Create and edit a trip name, destination, departure/return dates, currency, budget, and notes. Switch between saved trips; upcoming, current, and past status follows the local calendar.
- **Itinerary:** Add activities, dining, flights/transport, and stays. Dates and local 24-hour times are optional; dated items sort chronologically, with timed items before flexible plans and undated ideas last. Filter by day, edit details, and complete/reopen items.
- **Bookings:** Store locations, confirmation references, and notes for transport and stays. Confirm/reopen reservations. The same record appears in the itinerary, bookings, and budget; it is not duplicated.
- **Packing:** Add essentials and check them off. Packed/total counts appear in the trip summary.
- **Budget:** Record costs on itinerary/booking items and add other costs such as insurance or shopping. Track planned total, paid total, unpaid total, remaining budget, and overspending. Mark payment independently from confirmation or completion.
- **Backup previews (Gehao Dong, week one):** Prepare mock Plan B/C ideas for rain-affected activities or delayed dinners from the Itinerary page. Boston/USD fixtures include source, timestamps and expiry. Suggestions stay `needs_validation`; they never modify the itinerary or budget. [Demo and limitations](#backup-preview-demo).
- **Standalone backup validation (PR #23):** Check synthetic replacements against an entire sample itinerary, including traveler requirements, costs, scheduling, opening hours and transfers. The read-only validation lab uses its own fixtures and is not connected to saved trips or the shared validator. [Commands and scope](backup/VALIDATION.md).
- **Replanning:** Simulate delayed/interrupted items, combine synthetic backup inventory, edit dependencies and schedule rules, optionally use a Jac LLM to select combinations, and accept/reject version-safe revisions. Try the separate demo trip from the sidebar; see [the replanning guide](replan/README.md).
- **Persistence:** Web and CLI share `.jac/data/travel.sqlite3`, independent of GoPlanner. Stable IDs, transactional writes, date/time/amount validation, and deletion confirmations protect your records.
- **Responsive design:** A business-style navy, slate, and white interface with a flat trip overview, trip sidebar, overview cards, and five planning tabs. The web interface adapts to phones and tablets.

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

From `travel-planner/`, run the deterministic, storage-free demo:

```sh
jac run backup/demo.jac
```

In the web app, create a Boston/USD trip and add a dated, unfinished activity and dining item. In **Itinerary**, choose **Rain affects an outdoor activity** or **Delayed arrival affects dinner**, select the original item, and prepare Plan B/C. The panel shows up to two drafts with activation conditions, synthetic prices, mock sources, checked/expiry times and validation notes. Switching trips, scenarios or items clears the previous result. When the earliest evidence expires, the panel removes the drafts and prompts a refresh.

Unsupported locations/currencies show an empty result or exclusion reasons. Unavailable/unknown inventory, missing sources, expired timestamps and invalid evidence are excluded. Preview success and failure preserve saved trip/items and costs. Drafts remain `needs_validation`; full-trip constraints, automatic risks, live inventory, comparison, acceptance, booking and trip changes are separate work.

The draft contract is in `backup/models.jac`, the search/refresh adapter in `tools/alternatives/mock.jac`, and the public endpoint is `preview_backups(trip_id, item_id, trigger)`. These are local mock contracts, not the final shared AlternativePlan schema.

### Standalone full-itinerary validation demo

The implementation in [PR #23](https://github.com/howarddong0485/Travel-Disruption-Replanner/pull/23) adds a separate synthetic validation lab. From this folder:

```sh
python3 -m backup.validation_demo --scenario rain --budget 450
python3 -m unittest backup.test_validation -v
```

The rain example returns a USD 440 whole-trip Plan B that passes the implemented fixture checks and rejects a USD 470 Plan C against the USD 450 budget. In Roam, expand **Plan B / C · Validation lab** and choose **Run sample checks**. A passing fixture result is not shared-validator approval or permission to book/apply a replacement. See [the validation guide](backup/VALIDATION.md) and [the dated progress record](../docs/PROGRESS.md#progress-snapshot--2026-10-21).

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
| Standalone backup validation | `backup/validation.py`, `backup/validation_models.py`, `backup/validation_fixtures.py`, `backup/validation_demo.py`, `backup/validation_frontend.jac` | Synthetic full-itinerary checks, CLI and read-only lab from PR #23 |
| Tests | `server/main.test.jac`, `backup/test_planner.jac`, `server/test_backup.jac`, `tests/backup_preview.browser.cjs` | Service regressions, draft screening, read-only storage checks, and browser states/expiry |
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
python3 -m unittest backup.test_validation -v
jac test server/test_validation.jac
jac build travel --as client
```

Tests use temporary SQLite databases. They do not read or modify your saved trips.
