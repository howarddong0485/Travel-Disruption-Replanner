# Departure and multi-city journeys

The Route tab models the whole trip: departure city → ordered destination cities/regions → optional return city. A one-way trip omits the return. Route editing is also available in AI planner. Existing trips without a structured route keep their previous behavior.

## Use the planner

1. Create a trip with the departure date and final arrival date. Set a departure city and, if needed, a return city.
2. Open **Route → Set up route**. Enter each city's IANA time zone (for example `America/Detroit` or `Asia/Tokyo`), ordered destination cities, and each city's arrival/departure dates. Add, remove or reorder cities as needed. Return travel is optional.
3. Choose the transport mode and time allowances before departure and after arrival for every adjacent pair of cities. Optional city coordinates support places outside the map's built-in city list.
4. Save the route. Missing transport items are listed until a complete schedule has been supplied. **Plan this journey with AI** prepares a chat request; review the text and send it to generate a proposal. The assistant can also propose the route directly from a natural-language request.
5. Review the complete proposal and estimated total, then save it. Route changes and itinerary items are applied together. Planning a configured route requires all outbound/intercity/return legs to be covered. Existing paid, referenced, completed and fixed items remain protected.
6. To edit manually, assign each scheduled item to a city or transport leg. For intercity travel, enter the departure and arrival in their respective local time zones and the actual elapsed duration. The map and itinerary display the saved route; the transport popup shows both local times.

For example, a January 1–7 trip from Detroit to Tokyo, Kyoto and Osaka includes Detroit → Tokyo, Tokyo → Kyoto, Kyoto → Osaka and Osaka → Detroit. An overnight outbound flight and a return arriving earlier on the same calendar day are represented using different endpoint time zones.

Changing a city's name, time zone, dates or transport mode may invalidate existing items. Such edits are rejected until the affected items can be updated together in an AI proposal. A route editor opened before another trip change must be refreshed. Route changes also invalidate older AI and backup proposals.

## Data and checks

- `journey/model.jac` stores one versioned route per trip and city/leg bindings per item. City IDs remain stable when their order changes. SQLite writes share the trip's existing transaction and version system.
- Each route has 1–12 destination stops and exactly one leg between each adjacent pair. Supported modes are flight, train, drive, bus and ferry. The model represents one scheduled transport item per leg; connecting services can be described in that item, not as separate flight segments.
- Dates/times remain local for display. Scheduling comparisons use UTC instants derived from IANA zones. Missing or ambiguous daylight-saving times are rejected. A single item/leg can last up to 24 hours, matching the existing scheduler limit.
- Complete AI plans require every leg to have one transport item, consistent departure/arrival dates and elapsed duration, city activities within their stay, no schedule overlaps, and the configured transfer allowances. Existing budget, fixed-item and dependency checks also apply.
- Manual entry can build an incomplete route incrementally, with missing assignments/transport shown as issues. Every assigned item must still satisfy local-time, overlap and transfer constraints. Failed edits roll back all their writes.
- Backup reschedules preserve the route and endpoint zones. Sample-catalog replacements are blocked for routed trips because that catalog does not establish their destination city; use the journey planner for a replacement proposal.

## Real-world data boundary

The existing OpenAI Responses API research and structured-output flow is retained. This feature does not add a flight inventory API, verify fares/hotel availability, or schedule background disruption checks. City coordinates and drawn map paths are approximate. Transport schedules, durations, hotel costs and transfer buffers remain planning inputs/estimates until supported by a current source. No reservations or purchases are made.

## Verification

`journey/test_service.jac` checks complete cross-zone plans, acceptance/rejection, missing and duplicate transport, arrival buffers, wrong cities, manual-edit rollback, stale proposals/editors, one-way trips, DST edges and backup reschedules. Model calls are mocked; fixtures contain synthetic schedules and prices.

`tests/journey.browser.cjs` exercises the actual route form, persistence, map and arrival display, manual transport editing and the mobile layout against an isolated app. Run it like the other browser regressions, supplying `TRAVEL_APP_URL`, `TRAVEL_API_URL`, `PLAYWRIGHT_MODULE` and optionally `TRAVEL_BROWSER_CHANNEL`/`TRAVEL_MAP_SCREENSHOTS`. It makes no model or travel-provider requests.
