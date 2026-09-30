# Data Sources and Integration Plan

All integrations are planned. Start with fixture-backed adapters that share the same contracts as future provider adapters. Provider access, fields, pricing, licensing, and partner approval must be confirmed before implementation. Documentation links below were reviewed on September 30, 2026.

## Candidate providers

| Provider | Proposed use | Documented capability and integration boundary |
| --- | --- | --- |
| Expedia Group | Lodging and flight discovery | The [Travel Redirect API explorer](https://developers.expediagroup.com/xap-apis/api/resources/api-explorer) documents lodging and flight listings. Evaluate the selected Expedia product and approved access separately for booking execution, detailed terms, and other needs. Do not assume a listings integration supplies disruption monitoring or claims handling. |
| Google Places API | Restaurants, landmarks, attractions, hotels, and other places | [Places API overview](https://developers.google.com/maps/documentation/places/web-service/overview) describes search, place details, hours, reviews, and photos. Request only needed fields. Place discovery alone does not establish room inventory, reservation availability, or all traveler-specific eligibility. |
| Yelp API | Restaurant and local-business discovery | [Getting started](https://docs.developer.yelp.com/docs/getting-started) and [Business Search](https://docs.developer.yelp.com/reference/v3_business_search) provide the entry points for evaluating business discovery. Confirm needed fields and access for the selected plan and endpoint. |
| OpenWeather | Weather-aware risk analysis | [Current weather](https://openweathermap.org/api/current) supplies current conditions. Planning requires a forecast endpoint, such as the [5-day / 3-hour forecast](https://openweathermap.org/api/forecast5), within its supported horizon. Do not present current conditions as a forecast for a future trip. |

## Additional data still needed

The listed providers do not, by themselves, establish every capability in the product vision. The team still needs to select or supply:

- Flight operational status and disruption events, distinct from flight-search listings.
- Routing and travel-time estimates for walking, driving, and other transport.
- Booking-specific fare rules, hotel cancellation/no-show terms, and confirmation details.
- Rental-car availability, pickup rules, and reservation changes.
- Restaurant reservation availability and verified dietary accommodations where required.
- Attraction closures and date-specific opening information.
- Insurance policy documents and, later, supported claim-submission channels.

Use explicit fixtures or user-provided evidence for these gaps in the MVP. Pet and child suitability must carry evidence and may be unknown; ratings or categories alone are insufficient to establish mandatory eligibility.

## Proposed adapter contract

Expose operations such as `search_places`, `get_place_details`, `search_lodging`, `search_flights`, `get_weather_forecast`, `get_booking_policy`, and `estimate_travel_time`. These names are proposed application interfaces, not claims about provider endpoint names.

Every normalized response should include:

- Stable internal and provider IDs, source, retrieval time, and applicable date range.
- Location, time zone, price currency, known taxes/fees, and quote expiry when supplied.
- Evidence for eligibility and policy fields, with unknown values represented explicitly.
- A `mock` or `live` origin indicator and structured errors for unavailable data.

Keep provider-specific response parsing inside `tools/`. Agents consume normalized records, not raw provider payloads. Keep the fixture clock fixed in tests so deadlines and weather windows behave predictably.

## Collection and refresh strategy

1. Collect the minimum traveler input necessary for a plan, with consent for saved memory.
2. Search within bounded dates, locations, and constraints; avoid sending unnecessary personal details to providers.
3. Retrieve details only for shortlisted options and attach supporting evidence.
4. Cache only as permitted by provider terms; preserve required attribution and define expiry per data type.
5. Refresh volatile prices, availability, operating status, and policy evidence before a consequential decision.
6. On timeout, quota exhaustion, or stale results, return a clear partial/unavailable state. Never silently substitute mock inventory into a live result.

Before enabling each integration, review its current access requirements, attribution, storage and retention terms, regional availability, rate limits, and cost. No provider credentials or paid services are required for the planned fixture-based MVP.
