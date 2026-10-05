# Roam — Travel Planner

Roam is a personal travel planner built with **Jac 0.37.23**, following GoPlanner's web + CLI + shared SQLite service structure. Keep multiple trips, daily itineraries, reservations, packing lists, notes, and costs together in one workspace.

## Features

- **Trips:** Create and edit a trip name, destination, departure/return dates, currency, budget, and notes. Switch between saved trips; upcoming, current, and past status follows the local calendar.
- **Itinerary:** Add activities, dining, flights/transport, and stays. Dates and local 24-hour times are optional; dated items sort chronologically, with timed items before flexible plans and undated ideas last. Filter by day, edit details, and complete/reopen items.
- **Bookings:** Store locations, confirmation references, and notes for transport and stays. Confirm/reopen reservations. The same record appears in the itinerary, bookings, and budget; it is not duplicated.
- **Packing:** Add essentials and check them off. Packed/total counts appear in the trip summary.
- **Budget:** Record costs on itinerary/booking items and add other costs such as insurance or shopping. Track planned total, paid total, unpaid total, remaining budget, and overspending. Mark payment independently from confirmation or completion.
- **Persistence:** Web and CLI share `.jac/data/travel.sqlite3`, independent of GoPlanner. Stable IDs, transactional writes, date/time/amount validation, and deletion confirmations protect your records.
- **Responsive design:** A calm green and cream interface with a CSS landscape, trip sidebar, overview cards, and four planning tabs. The web interface adapts to phones and tablets.

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

This workspace already has a working `.jac/venv`. If Jac's bundled Python cannot recreate it, use GoPlanner's project Python from this sibling folder:

```sh
../planner/.jac/python314/bin/python -m venv .jac/venv
jac install
```

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

## Project structure

| Component | Files | Purpose |
| --- | --- | --- |
| Web | `main.jac`, `frontend.jac`, `frontend.impl.jac`, `styles.css` | Trip workspace and responsive browser UI |
| Service | `server/main.jac` | Shared trip/item API, validation, and SQLite storage |
| CLI | `cli/main.jac` | Terminal commands using the same service |
| Tests | `server/main.test.jac` | Endpoint lifecycle, persistence, validation, isolation, ordering, and cascade deletion |
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
jac build travel --as client
```

Tests use temporary SQLite databases. They do not read or modify your saved trips.
