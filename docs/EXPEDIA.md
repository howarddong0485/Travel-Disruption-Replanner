# Expedia hotel backup and replan previews

The current browser panels use [LiteAPI and Geoapify](FREE_PROVIDERS.md), which do not require Expedia access. The Expedia adapter and endpoints described here remain available as a legacy developer integration; the previous Expedia browser controls have been replaced by the new provider panels.

Implemented against Expedia's public Rapid v3 schema on October 28, 2026. This integration searches hotel inventory and automatically generates up to two replacement drafts using Roam's existing schedule, dependency, fixed-item and budget checks. It is a read-only preview, separate from the mock proposal acceptance flow. It does not book, cancel or update saved itinerary items.

## Configure partner access

Use an approved **Rapid Lodging** API key and shared secret. Travel Redirect and third-party RapidAPI marketplace credentials are different products and will not work here. Public documentation does not provide credentials for your partner account. Expedia documents credential retrieval and production approval in its [setup guide](https://developers.expediagroup.com/rapid/setup).

From `travel-planner/`, copy `.env.example` to `.env`, fill in the two values locally, then run:

```sh
set -a
source .env
set +a
jac run --no-cache --dev travel
```

Environment names are `EXPEDIA_API_KEY`, `EXPEDIA_SHARED_SECRET`, and `EXPEDIA_ENV`. The default `test` mode calls `https://test.ean.com/v3`; `live` calls `https://api.ean.com/v3`. The UI labels test results as provider test data. Switching to `live` requires production-approved access. The adapter signs each request with SHA-512 and never returns credentials, authorization headers or tokenized provider links to the browser. `.env` is ignored by Git; Jac does not load it automatically.

## Use the website

1. Create a trip with future dates, a currency and optionally a budget. Add a hotel stay with a date and local time. The stay's cost should represent the whole original stay.
2. Open **Backup plans** and find **Find hotel Plan B / C**, or open **Replan** and find **Replan a hotel disruption**.
3. Choose the stay, a check-out date within the trip, and a shortlist of Expedia property IDs for the destination. Numeric IDs come from the partner's Rapid property catalog/geography data; arbitrary hotel names or Expedia webpage URLs are not accepted. This first integration does not perform city-to-property discovery. The IDs shown as input placeholders are documentation examples, not a verified local shortlist.
4. Enter guests for **one room** (`2` = two adults; `2-9,4` includes two children aged 9 and 4) and the traveler's point-of-sale country code.
5. For replanning, report the hotel interruption or arrival delay. Click **Generate hotel options**. The server searches again for the resulting check-in date and computes drafts automatically. Review the proposed schedules and monetary totals.

Each search fetches current availability and property content for at most 20 supplied properties and a maximum 28-night stay. The adapter ranks its returned quotes by whole-stay price, chooses distinct properties, and passes up to ten candidates to the planner to find Plan B/C. It does not claim to find the global cheapest hotel or every valid rate.

## Terminal search

With the same environment loaded:

```sh
jac run --no-cache tools/expedia_demo.jac -- 2026-11-01 2026-11-03 19248,20321 --occupancy 2 --currency USD --country US
```

Use future dates and property IDs from your approved catalog. No app server or trip database is needed for this raw search.

## Integration details and limits

- `tools/alternatives/expedia.jac` calls `GET /v3/properties/availability` and `GET /v3/properties/content`. It uses `occupancy_pricing[occupancy].totals.property_inclusive.request_currency`, which includes Expedia- and property-collected taxes/fees for the entire stay. Missing, negative, non-finite, mismatched-currency and unsupported fractional prices are excluded rather than treated as zero. This follows Roam's existing two-decimal currency convention.
- Restricted member, package, corporate, distribution and mobile rates are excluded when flagged because eligibility is not established. Unknown traveler eligibility remains unvalidated.
- `replan/expedia.jac` passes explicit provider inventory into the deterministic combination builder. It never silently substitutes mock restaurants, transport or hotels. If a downstream item needs a replacement unavailable from this hotel-only provider flow, the draft is excluded with an explanation.
- `expedia_status()` reports configuration presence and test/live mode. `preview_expedia_hotels(...)` takes `trip_id`, `item_id`, `checkout`, `property_ids`, optional `occupancy`, `country`, `mode` (`backup`/`replan`), `kind` (`interrupted`/`delayed`) and `delay_minutes`. It closes the database before network calls and rejects results if the trip version changes during the search.
- Original paid costs remain in projected totals because the original booking's refund entitlement is unknown. New replacement costs are shown separately. Candidate cancellation rules are returned as provider evidence; they do not establish refunds on the original reservation.
- All results remain `needs_validation`. The planner reuses saved durations and transfer buffers; it does not yet validate new routes, hotel-specific check-in windows, accessibility, pet/child eligibility or other hard requirements. The stored stay time represents a check-in task, not an overnight block. Provider content contains the hotel's address and check-in/check-out rules for future validation work.
- There is no background monitoring, automatic acceptance, booking, cancellation, flight integration or Price Check execution. Refresh shopping and perform Expedia Price Check before any future booking flow. These drafts are not stored in the mock proposal table and cannot be accepted through `review_replan`.
- Calls have a 15-second timeout each, bounded response sizes and no retries. Missing credentials, denied access, provider errors and unavailable quotes are explicit. There is no mock fallback in live mode. Displayed timestamps mark retrieval, not guaranteed quote validity.

## Verification

```sh
jac check --nowarn
jac test tools/alternatives/test_expedia.jac replan/test_expedia.jac
jac test server/main.test.jac server/test_expedia.jac
jac build travel --as client
```

Use `--no-cache` on startup to regenerate API argument metadata after running standalone server tests. If an already-running dev instance reports missing API arguments after tests, restart it with that flag.

Tests use synthetic Rapid-shaped responses, never real account credentials or bookings. Successful fixture tests do not verify partner access or live availability.

Official references: [Rapid Lodging](https://developers.expediagroup.com/rapid/lodging), [shopping](https://developers.expediagroup.com/rapid/lodging/shopping/about-shopping-api), [signature authentication](https://developers.expediagroup.com/rapid/lodging/reference/signature-authentication), [OpenAPI specification](https://a.travel-assets.com/documentation-hubs/prod/rapid/latest/en-US/assets/rapid-3-specs.yaml).
