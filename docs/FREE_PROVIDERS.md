# LiteAPI and Geoapify

Roam shows LiteAPI hotel rates in **Backup plans → Supplier inventory** for a saved trip. The panel also shows whether Geoapify place discovery and the separate Expedia integration are configured.

## Get the free keys

1. **LiteAPI:** [Create a free account](https://dashboard.liteapi.travel/) and copy your **sandbox** API key from the developer/API keys area. According to the [signup guide](https://docs.liteapi.travel/docs/getting-a-sandbox-key), no credit card is required for sandbox access. Sandbox keys begin with `sand_` or `sandbox_`; they produce test offers. Production keys begin with `prod_` and require separate account setup.
2. **Geoapify:** [Create an account](https://myprojects.geoapify.com/), create a project, and copy its API key for place discovery. Hotel quotes work without this key.

## Configure and run

From the project folder:

```sh
cd travel-planner
export PATH="$HOME/.local/bin:$PATH"
cp -n .env.example .env
open -e .env
```

Add or update these lines, then save. If `.env` already existed with Expedia settings, add these two new lines to that file; copying with `-n` will preserve the existing file.

```dotenv
LITEAPI_API_KEY=your_sandbox_key
GEOAPIFY_API_KEY=your_geoapify_key
```

Keep actual keys local. `.env` is ignored by Git. The app does not automatically load it. Load the file into the server environment:

```sh
set -a
source .env
set +a
jac install
jac run --no-cache --dev travel
```

Open the printed App URL. Use `--no-cache` to regenerate Jac API argument metadata after standalone server tests; restart the dev server with that flag if a running instance reports missing arguments after testing.

## Verify on JacHammer

1. In the project's server secret store, set `LITEAPI_API_KEY` to the key for the intended environment. Use a sandbox key for test data or an authorized production key for a live test. Restart the preview with the updated server environment.
2. Create a trip with future dates. Open **Backup plans → Supplier inventory**, check the LiteAPI configuration label, and enter a city, destination country code, stay dates within the trip, guest count and guest nationality. Dates span 1–28 nights and prices use the trip currency. Guest notation is `2` for two adults in one room, or `2-9,4` to include two children aged 9 and 4.
3. Select **Check hotel rates**. Record the observed mode, property, stay dates, occupancy, total and currency, and retrieval time. The result label distinguishes live quotes and sandbox test data. Record an empty result or provider error as such. A live acceptance check requires a returned live quote.
4. Refresh the trip and check that the saved itinerary and costs match the state before the lookup. Searching does not create reservations or itinerary drafts.

## Behavior and limits

- LiteAPI calls `POST https://api.liteapi.travel/v3.0/hotels/rates` with city/country, dates, currency and structured occupancy. It searches at most twenty hotels and requests one rate per hotel, then ranks normalized quotes by whole-stay cost. It does not guarantee the cheapest hotel citywide. Sandbox mode is inferred from the key and checked against response provenance. An explicit sandbox response is never labeled live.
- `retailRate.total` includes included fees. Explicitly excluded `taxesAndFees` are added once when their amounts and currency are known. Unknown fee evidence, negative/non-finite/unsupported fractional totals, currency conflicts and conflicting guest counts exclude the offer. Per LiteAPI documentation, an explicit `taxesAndFees: null` means no additional disclosed property fees; an omitted field is treated as missing evidence. No currency conversion is invented.
- Hotel drafts reuse existing itinerary schedule, dependency, fixed-item and budget checks. New hotel-specific check-in rules, travel routes, accessibility and other traveler requirements are still unvalidated. Drafts remain `needs_validation`, do not write itinerary/proposal records and cannot be accepted by the mock review endpoint. Booking/prebook, cancellation and automatic background monitoring are not implemented. Refresh and revalidate rates before a future booking step.
- Geoapify calls its geocoding and Places APIs. It supplies location suggestions, not room inventory, restaurant reservations or verified opening hours. Place prices remain `null` and availability remains `unknown`. Geoapify place IDs are never passed to LiteAPI as hotel IDs. Nearby suggestions are not automatically applied as feasible replacements.
- Provider keys remain server-side. Transport errors do not echo URL query keys or headers. The server uses fixed API endpoints, 15-second request timeouts and a bounded JSON response size. No mock inventory silently replaces failed live calls. Offer tokens are hashed into internal IDs and are not returned to the browser.
- Configuration and fixture tests do not establish live provider access. Keys must be supplied locally to test your accounts. Provider pricing and account requirements can change; follow the linked official documentation.

## Developer interfaces and checks

`travel_provider_status()` reports provider access and mode without credentials. `quote_liteapi_hotels(...)` requires ownership of the trip and returns normalized quote fields for display. The separate `preview_liteapi_hotels(...)` endpoint computes hotel drafts, and `discover_travel_places(...)` queries Geoapify for an existing trip. Provider-specific parsing stays in `tools/alternatives/liteapi.jac` and `tools/geoapify.jac`.

```sh
jac check --nowarn
jac test tools/test_free_providers.jac server/test_free_providers.jac
jac test replan/test_expedia.jac server/main.test.jac server/test_expedia.jac
jac build travel --as client
```

All provider tests use synthetic responses and isolated temporary databases.

Official API references: [LiteAPI rates](https://docs.liteapi.travel/reference/post_hotels-rates), [rate response structure](https://docs.liteapi.travel/docs/hotel-rates-api-json-data-structure), [Geoapify geocoding](https://apidocs.geoapify.com/docs/geocoding/), [Geoapify Places](https://apidocs.geoapify.com/docs/places/).
