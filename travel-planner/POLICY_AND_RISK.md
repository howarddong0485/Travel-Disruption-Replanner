# Policies and risk detection (Person 2)

The PolicyAgent, cancellation tracking and the rule-based RiskAnalyzer, plus the
proposed shared contracts they read and produce. Everything runs on mock fixtures
with a fixed clock; no LLM provider or API key is needed.

## Run it

From `travel-planner/`:

```sh
jac run risk/demo.jac                 # risk report for fixtures/demo-trip.json
jac run risk/demo.jac -- --json       # same report as JSON
jac test -d schema && jac test -d policy && jac test -d risk
```

Run `jac install` first; the `[byllm]` section in `jac.toml` installs the LLM
library. If it fails creating `.jac/venv` with
`symbol not found in flat namespace '_PyExc_MemoryError'`, create the venv with
another Python 3.14 (for example one under `~/Library/Caches/jac/rt/*/python/bin/`
that can `import subprocess`) and rerun: `<python3.14> -m venv .jac/venv && jac install`.

## Layout

| Path | Purpose |
| --- | --- |
| `schema/common.jac` | `Evidence`, local-time to UTC conversion, money formatting, JSON serialization |
| `schema/itinerary.jac` | `ItineraryNode`/`Edge`/`Graph` plus `PlaceHours`, `WeatherForecast`, `TravelEstimate` |
| `schema/policy.jac` | `RefundPolicy` as ordered `CancellationTier`s |
| `schema/risk.jac` | `RiskFlag`, severity and status enums |
| `schema/bundle.jac` | `TripBundle`, JSON loading, structural checks |
| `schema/roam.jac` | Adapter from Roam trip/item records to `ItineraryGraph` |
| `policy/agent.jac` | PolicyAgent: verifies a draft against the terms text and builds an evidenced `RefundPolicy` |
| `policy/draft.jac` | Unverified `PolicyDraft` the extractors produce |
| `policy/extract_llm.jac` | `by llm()` extraction with the project's default model |
| `policy/extract_rules.jac` | Rule-based fallback extractor for common phrasings |
| `policy/cancellation.jac` | What cancelling now refunds, and when terms next change |
| `risk/rules.jac`, `risk/analyzer.jac`, `risk/config.jac` | Risk rules, the analyzer entry point, tunable thresholds |
| `fixtures/demo-trip.json` | Synthetic Denver family trip that exercises every rule |

`schema/` is a **proposal** for the shared contracts in `docs/ARCHITECTURE.md`; it
needs agreement from the other owners before anyone depends on it.

## PolicyAgent

`extract_policy(PolicyRequest(...))` turns a booking's terms text into a
`RefundPolicy` plus `Evidence` records. An extractor only proposes a draft; code then
checks it against the source:

- Every excerpt must appear in the terms (ignoring case, spacing and quote style).
  Evidence stores the source's own wording.
- A partial refund percentage, a fee amount, and a deadline's day or hour count must
  appear in that tier's excerpt; a fee must be in the booking's currency. A field that
  fails becomes unknown.
- An unverifiable tier or deadline, a misordered tier, an ambiguity the extractor
  reports, or instruction-like text in the terms sends the whole policy to review:
  its terms become unknown and `needs_review` is set.

The LLM is used only when byLLM can resolve a model (`BYLLM_DEFAULT_MODEL`,
`[byllm.model] default_model`, or a provider API key). Otherwise, or if the call
fails, the rule-based extractor runs. The prompt contains the terms text and the
booking's title, kind, start, zone and currency, never traveler or payment details.
Tests use `MockLLM`.

## Rules

| Rule | Flags when |
| --- | --- |
| `tight_connection` | The gap on a `precedes`/`depends_on` edge is shorter than the stated minimum, travel estimate, or default buffer |
| `weather_exposure` | An outdoor activity overlaps a forecast at or above the precipitation threshold |
| `long_drive` | A drive exceeds the configured limit |
| `opening_hours` | A visit starts before opening, runs past closing, ends close to closing, or falls on a closed day |
| `booking_terms` | A booking is non-refundable, partially refundable, near its free-cancellation deadline, or has missing terms |

A rule that cannot evaluate an item for lack of evidence emits an **unresolved**
flag rather than treating it as safe.

## Conventions

- Money is integer minor units with an explicit currency; percentage refunds round down.
- Local times are `YYYY-MM-DDTHH:MM` with an IANA zone, converted to UTC before any
  comparison so durations across zones and DST changes are correct. An ambiguous
  local deadline resolves to its earlier occurrence.
- `None` means unknown and is never read as zero, refundable, or free.
- `jac.toml` pins `schema.*`, `policy.*` and `risk.*` to the server; without the pin,
  modules with no Python imports compile native and their tests abort.

## Open decisions for the team

- Agree on (or replace) the `schema/` contracts.
- Choose the LLM provider and model (`[byllm.model] default_model`).
- Default thresholds in `risk/config.jac` (transfer buffers, drive limit, rain threshold, deadline warning window).
- Roam records have no end times, zones, dependencies or policies; decide whether
  the foundation should store them or whether the adapter stays lossy.

## Next

- Optional bounded LLM classification for indoor/outdoor activities.
- Risk/policy panel in the web UI.
