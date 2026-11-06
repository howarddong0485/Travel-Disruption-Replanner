# LiteAPI and Geoapify

Roam's **Backup plans** and **Replan** tabs use LiteAPI for hotel rate previews and Geoapify for nearby place discovery. These integrations do not need Expedia credentials. Each provider works independently when its key is configured.

## Get the free keys

1. **LiteAPI:** [Create a free account](https://dashboard.liteapi.travel/) and copy your **sandbox** API key from the developer/API keys area. According to the [signup guide](https://docs.liteapi.travel/docs/getting-a-sandbox-key), no credit card is required for sandbox access. Sandbox keys begin with `sand_` or `sandbox_`; they produce test offers. Production keys begin with `prod_` and require separate account setup.
2. **Geoapify:** [Create an account](https://myprojects.geoapify.com/), create a project, and copy its API key. The [free plan](https://www.geoapify.com/pricing/) currently provides 3,000 credits/day without a credit card. Preserve Geoapify and OpenStreetMap attribution when displaying data; the new panel includes both links.

## Configure and run

From the project folder:

```sh
cd "/Users/zhanhaoliu/Desktop/EECS 449/Travel-Disruption-Replanner/travel-planner"
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

## Use the app

- **Hotel Plan B/C:** Create a trip with future dates and add a hotel stay with a date, local time and whole-stay original cost. In **Backup plans**, find **LiteAPI + Geoapify**, enter the destination city and country code, choose the stay, set check-out and guests, then select **Generate hotel plans**. The server automatically searches hotels by city and calculates up to two replacement drafts. No hotel IDs are needed.
- **Hotel disruption:** Open **Replan** and use the provider panel to report an unavailable hotel or delayed arrival. Arrival delays propagate through saved dependencies. The server searches rates for the resulting check-in date, retains prior paid costs where refunds are unknown, and computes proposed downstream schedule changes.
- **Nearby alternatives:** In either panel, choose hotels, restaurants or attractions and select **Find nearby places**. Geoapify resolves the entered destination within the selected country, displays that resolved location, and returns up to ten places within 5 km. Check the resolved destination before using the suggestions.

Country inputs have different meanings: **destination country** determines the city search, while **guest nationality** is used for LiteAPI rate eligibility. Guest notation is one room: `2` for two adults, or `2-9,4` for two adults and children aged 9 and 4.

## Behavior and limits

- LiteAPI calls `POST https://api.liteapi.travel/v3.0/hotels/rates` with city/country, dates, currency and structured occupancy. It searches at most twenty hotels and requests one rate per hotel, then ranks normalized quotes by whole-stay cost. It does not guarantee the cheapest hotel citywide. Sandbox mode is inferred from the key and checked against response provenance. An explicit sandbox response is never labeled live.
- `retailRate.total` includes included fees. Explicitly excluded `taxesAndFees` are added once when their amounts and currency are known. Unknown fee evidence, negative/non-finite/unsupported fractional totals, currency conflicts and conflicting guest counts exclude the offer. Per LiteAPI documentation, an explicit `taxesAndFees: null` means no additional disclosed property fees; an omitted field is treated as missing evidence. No currency conversion is invented.
- Hotel drafts reuse existing itinerary schedule, dependency, fixed-item and budget checks. New hotel-specific check-in rules, travel routes, accessibility and other traveler requirements are still unvalidated. Drafts remain `needs_validation`, do not write itinerary/proposal records and cannot be accepted by the mock review endpoint. Booking/prebook, cancellation and automatic background monitoring are not implemented. Refresh and revalidate rates before a future booking step.
- Geoapify calls its geocoding and Places APIs. It supplies location suggestions, not room inventory, restaurant reservations or verified opening hours. Place prices remain `null` and availability remains `unknown`. Geoapify place IDs are never passed to LiteAPI as hotel IDs. Nearby suggestions are not automatically applied as feasible replacements.
- Provider keys remain server-side. Transport errors do not echo URL query keys or headers. The server uses fixed API endpoints, 15-second request timeouts and a bounded JSON response size. No mock inventory silently replaces failed live calls. Offer tokens are hashed into internal IDs and are not returned to the browser.
- Configuration and fixture tests do not establish live provider access. Keys must be supplied locally to test your accounts. Provider pricing and account requirements can change; follow the linked official documentation.

## Developer interfaces and checks

`travel_provider_status()` reports key presence and LiteAPI mode. `preview_liteapi_hotels(...)` creates hotel drafts and rejects a trip version change during the provider call. `discover_travel_places(...)` queries Geoapify for an existing trip. Provider-specific parsing stays in `tools/alternatives/liteapi.jac` and `tools/geoapify.jac`; shared read-only hotel drafting reuses `replan/expedia.jac`. Legacy Expedia endpoints remain available but are not used by the new panels.

```sh
jac check --nowarn
jac test tools/test_free_providers.jac server/test_free_providers.jac
jac test replan/test_expedia.jac server/main.test.jac server/test_expedia.jac
jac build travel --as client
```

All provider tests use synthetic responses and isolated temporary databases.

Official API references: [LiteAPI rates](https://docs.liteapi.travel/reference/post_hotels-rates), [rate response structure](https://docs.liteapi.travel/docs/hotel-rates-api-json-data-structure), [Geoapify geocoding](https://apidocs.geoapify.com/docs/geocoding/), [Geoapify Places](https://apidocs.geoapify.com/docs/places/).
