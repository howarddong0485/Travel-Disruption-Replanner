# Jacplan — Travel Planner

Jacplan is a personal travel planner built with **Jac 0.37.23**, following GoPlanner's web + CLI + shared SQLite service structure. Keep multiple trips, daily itineraries, reservations, packing lists, notes, and costs together in one workspace.

Application code, backend helpers, demos, and tests are written in `.jac` files. Jac imports Python standard-library modules for SQLite, dataclasses, date/time handling, and CLI argument parsing; no project-owned Python source files are required.

The main workspace now uses **GPT-6 Luna** with reasoning disabled for faster conversation, web research, initial itinerary drafts, alternatives and disruption repairs. Full itineraries and web research still take time. The earlier mock modules and endpoints remain available for regression checks; their milestone status is recorded in [MVP_STATUS.md](../docs/MVP_STATUS.md).

## AI planning workspace

The **AI planner** combines initial planning, backup preparation and disruption
replanning. A persistent conversation sidebar stays beside your itinerary,
bookings, packing and budget. Chat history is stored separately for each trip.

1. Create or select a trip with dates, departure/return locations, destination, currency and budget. For a complete route, use **Route** to set ordered city stays, time zones and transport buffers, then choose **Plan this journey with AI**. See [journey planning](../docs/JOURNEY_PLANNING.md).
2. Choose **Plan my trip**, **Find alternatives**, or **Something changed**.
3. Edit the prompt in the conversation sidebar and send it. **Ask a question**
   answers without generating a draft. Web search can be switched off.
4. Review proposals in the main area: before/after changes, estimated totals,
   schedule checks and uncertainty. Refine a proposal in chat or keep your plan.
5. Acknowledge the estimates and choose **Save this plan** to write the reviewed
   changes. Chat and search never directly change itinerary items.

### Pet-friendly and trip pace

Before asking GPT to plan, use the controls in **AI planner**:

- **Pet-friendly**: toggle on to request pet-suitable stays, dining, activities,
  breaks and fee allowances. GPT must flag unverified policies and species/size
  restrictions; this setting does not verify that a venue accepts your pet.
- **Intense**: targets 4–6 main activities per full day, with fuller schedules.
- **Balanced** (default): targets 2–3 main activities with breaks and flexibility.
- **Relax**: targets 1–2 main activities and generous rest/free time.

These are pacing targets, adjusted for arrival/departure days and constraints.
The controls save automatically for each trip and are included in research,
structured plan generation, backups, replanning and automatic correction calls.
Changing them leaves saved itinerary items intact and makes older proposals
stale, so generate a new plan after changing preferences. Turning the pet toggle
off does not erase separately recorded pet requirements in your traveler facts.

You can also ask the assistant to edit the active trip's name, destination,
departure/return locations and dates, budget, currency or notes, either in ordinary chat or
**Edit trip details** mode. For example: “Move my trip to April 10–14, 2027 and
raise my budget to USD 2,000.” A proposal shows each trip field before and after.
Date changes must also move any affected flexible itinerary items into the new
trip window; accepting saves trip and item changes in one transaction. Locked
bookings stay protected, and currency changes cannot relabel existing costs.
New date/destination edits clear obsolete venue/route evidence while preserving
traveler preferences. No edit is applied until you review and save the proposal.

Users can open **OpenAI API key** in the Travel assistant, enter their own key,
and choose **Use key**. Their key overrides the server key for every AI stage,
including research, planning and automatic repairs. **Clear key** restores the
server fallback. Keys remain only in the assistant’s browser memory and the
current server request; refreshing or closing the assistant clears them. They are
not saved to browser storage, the database, conversation history or `.env`.
OpenAI checks the key on the first message; API charges apply to its account.

For an optional app-owner fallback and model settings, set these values in
`travel-planner/.env` (never commit actual credentials):

```dotenv
OPENAI_API_KEY=your_key_here
OPENAI_CHAT_MODEL=gpt-6-luna
OPENAI_PLANNING_MODEL=gpt-6-luna
```

The server reads these settings from its environment or the project `.env`.
No hotel, place or flight provider keys are needed for this workflow. Existing
provider adapters are retained but their panels are removed from the main UI.

OpenAI's Responses API performs optional web research with clickable sources.
Planning requests use a separate structured-output call to convert the research
and trip context into bounded drafts. Web research is limited to three built-in
tool calls and concise evidence notes, including representative pet policies.
Policies without evidence remain explicitly unverified. Turn off **Search the web**
for a faster draft with estimated costs: pet and pace preferences still apply.
Ordinary questions use one call; planning with search uses two. Planning without
search and explicit **Edit trip details** requests skip the research call and
build a draft directly. Local validation may add at most one correction call.
Planning history includes conversation text without resending old research and
review metadata. Model and search usage incur OpenAI API charges. Missing keys, quota
errors and timeouts appear in the conversation; no mock answer is substituted.
API keys and booking references are not sent as model context. Server keys are never returned to the browser; user keys are submitted only with their AI requests.

Local checks cover trip dates, schedule overlap, stored dependencies, latest-start
rules, fixed items and the whole-trip budget including an existing reserve.
Paid, confirmed, completed, fixed and booking-reference items stay unchanged.
Prices remain estimates: these checks do **not** establish live availability,
opening hours, transfer feasibility, dietary/accessibility/pet eligibility,
refunds or booking terms. New GPT drafts require numeric planning estimates for every item. If a draft fails local budget or schedule checks, one automatic correction is attempted before review. Older drafts with missing prices can be completed through GPT or by entering traveler estimates and rerunning the budget check. Unknown prices are never silently counted as free. The existing
synthetic full-trip validator is separate from this AI draft workflow.

Drafts expire after 30 minutes. Acceptance checks the current trip and facts
again under a write transaction, rejecting stale drafts; request IDs and review
states prevent duplicate requests and repeated application. Saving one option
invalidates sibling drafts. User-entered trip data and recent conversation are
sent to OpenAI to answer requests; Responses requests use `store: false` while
conversation records remain in the local SQLite database.

Core trip editing, chronological itineraries, reservations, packing, notes,
planned/paid/unpaid budget totals, CLI access and local SQLite persistence remain
available. No real bookings, payments or cancellations are performed.

Offline AI regressions: `jac test assistant/test_workflow.jac`.

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

- **AI planner:** Initial itinerary drafts, alternatives and repairs in one flow.
- **Itinerary:** Review saved plans and manually add or edit arrangements.
- **Bookings, Packing list, Budget:** Manage reservations, essentials and costs.
- **Travel assistant:** Trip-specific conversation, questions, sources and planning prompts.

The historical guided/mock examples below document retained backend/demo modules;
the primary navigation uses the unified AI workspace.

## Start the app

For a new checkout, use the repository-root
[setup and complete verification scripts](../docs/LOCAL_VERIFICATION.md).
They pin Jac 0.37.23, create an independent Python 3.14 environment, build a
sealed package, and verify non-development HTTP/CLI behavior. The guide also
records the version-specific build compatibility command and packaged-run setup.

From the repository root on the connected review branch:

```sh
bash scripts/setup.sh
cd travel-planner
../.tools/jac-0.37.23 run --dev travel
```

For the CLI and focused examples below, `jac` means this checksum-verified
0.37.23 executable; invoke `../.tools/jac-0.37.23` if your shell resolves another version.

Open the **App** URL printed by Jac. Create a trip, then add details using the itinerary, bookings, packing, and budget tabs. Use **Edit trip** for notes or a budget. Refresh to see changes made through the CLI or another browser.

A fresh clone needs an independent Python 3.14 environment; `setup.sh` creates it and installs the declared dependencies. See the [current verification guide](../docs/LOCAL_VERIFICATION.md).

## LiteAPI hotel backups and Geoapify places

The **Backup plans** and **Replan** tabs include **LiteAPI + Geoapify** panels. Configure `LITEAPI_API_KEY` with your free sandbox key for city-based hotel rates and automatic Plan B/C drafts; configure `GEOAPIFY_API_KEY` for nearby hotel, restaurant and attraction suggestions. Neither requires Expedia access. The hotel drafts check stored itinerary constraints and show costs and downstream schedule changes; Geoapify suggestions have unknown prices and availability. These are read-only previews requiring further validation. See [free-provider setup and usage](../docs/FREE_PROVIDERS.md). Legacy Expedia endpoints remain available; see [their setup guide](../docs/EXPEDIA.md).

## Wikipedia destination and attraction discovery

Fetch live English Wikipedia information without an API key, app server, or database:

```sh
jac run --no-cache tools/wikipedia_demo.jac -- Boston --interest museum --limit 5
jac run --no-cache tools/wikipedia_demo.jac -- "Kyoto" --interest temple --limit 5
```

The JSON includes a destination introduction and ranked article candidates matching the destination and containing the interest in their titles. Use a short interest such as `museum`, `park`, or `temple`; title filtering can miss relevant places with other names. Each article includes its title, plain-text summary, source URL, coordinates when present, retrieval time and attribution. Destination lookup uses an article title and follows redirects; use a precise title such as `Paris` or `Cambridge, Massachusetts`. Missing pages return `not_found`; disambiguation pages return `ambiguous` and require a more specific title.

Reuse the helper in server-side Jac code:

```jac
import from tools.wikipedia { destination_summary, search_attractions }
```

Call `destination_summary("Boston")` and `search_attractions("Boston", "museum", 5)`. These are standalone helpers, not yet wired into the browser UI. Search results are discovery candidates, not verified local attractions: review the source and location before using them. They do not supply verified opening hours, prices, availability or traveler eligibility. Requests have a ten-second timeout and report provider errors; there are no automatic retries. Text comes from Wikipedia contributors under its source license; retain the returned attribution and article link when displaying or reusing it. No images are fetched.

The default identifying User-Agent links to this repository. Override it with `WIKIPEDIA_USER_AGENT` if deploying under another project/contact. See the official [Search API](https://www.mediawiki.org/wiki/API:Search), [TextExtracts API](https://www.mediawiki.org/wiki/Extension:TextExtracts), and [User-Agent policy](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy).

Offline checks: `jac test tools/test_wikipedia.jac`.

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

Departure and return locations are optional cities or airports and may differ. Set them in Create/Edit trip or with CLI `new --depart-from "Detroit, MI" --return-to "Chicago, IL"`. They appear in the trip overview and assistant context. Existing databases migrate automatically with blank locations; older API clients that omit these fields preserve saved locations when editing.

The trip overview animates the route from departure through destination to return, with a pause/play control. Reduced-motion settings show a static route. This is a route illustration, not a geographic map or live flight tracker.
