# Connected backup planning

This integration proposal connects the existing Person 1 profile, mandatory-filter
and budget interfaces, Person 2 risk/policy analysis, Person 3 backup generation,
and Person 4's versioned proposal/review transaction. The Roam Backup plans page
provides comparison and explicit acceptance. Tracked in #34, on
`codex/connected-backup-planning` above the #33 candidate-selection slice.
Publishing this proposal does not merge the source PRs or approve their contracts.

## Try it

Use the manifest-pinned **Jac 0.37.23**. Run `jac install --dev` to install the
declared runtime capabilities, including the LLM dependencies needed by MockLLM.
An existing venv may require repair as described in the upstream runtime docs;
the working local Python venv was reused in this verification.

```sh
jac run planning/demo.jac
jac run --dev --host 127.0.0.1 --port 8360 --api-port 8361 travel
```

Choose **Try connected backup plans**, or open **Backup plans** and select a
weather or arrival-delay sample. Each sample creates a separate saved trip with
explicit synthetic traveler, quote, operating-hour, route and risk evidence.
Select risks, find up to five alternatives, compare the exact changes, keep the
current plan or explicitly accept a proposal. The weather sample has three
passing indoor choices. The arrival sample includes both moving dinner and
changing restaurants. The CLI's third scenario combines weather and a reported
restaurant closure into two-node alternatives.

Saved trips use the same flow. Expand **Traveler requirements and trip facts**
to record party composition, dietary/pet/accessibility requirements, timezone,
reserve, end times, hours, eligibility, whole-party pricing and route estimates.
Confirm item facts explicitly before saving new evidence. Editing a profile
does not renew old quote/route evidence or assume that an old quote covers a
different party. Missing information remains unresolved and disables acceptance.
User-confirmed facts are identified as user sources; inventory remains synthetic.

## Interfaces and ownership

| Interface | Owner/reuse |
| --- | --- |
| `profile_from_data` -> `TravelerProfile` | Boundary validation around Person 1's contract; travelling pets remain hard requirements |
| `evaluate_place(profile, place, now)` | Person 1 mandatory filter, applied throughout the proposed itinerary |
| `build_ledger(trip, items, contingency_cents)` | Person 1 deterministic totals; retained original payments count once |
| `analyze_trip(bundle, now)` / `evaluate_cancellation` | Person 2 risks and evidenced policy/refund results |
| `schema/alternative.jac` | Versioned `AlternativePlan`, `PlanValidation`, `ComparisonResult` and JSON loader |
| `generate_plans(context, now, risk_ids, max_plans, use_llm)` | P3 search, strategy generation, full-trip validation and optional bounded model choice |
| `review_backup_plan` -> `replan.engine.decide` | P4 proposal version check and transactional application |

The typed integration contract uses `trip_id + base_version`, a supplemental
content fingerprint, stable candidate identities, changed nodes, activation
conditions, evidence deadlines, validation and deterministic comparison metrics.
`valid` has explicit `integrated_mock` scope. An unresolved, reviewed, expired,
changed-price or outdated alternative cannot be accepted. `schema/` remains an
implemented integration proposal, not a claim of team-wide contract approval.

Public service functions:

- `planning_state(trip_id)` returns the P4 version, facts, P2 risks, P1 ledger,
  current item summaries, server clock and recent proposal review states.
- `save_planning_context(trip_id, payload, expected_version)` validates and saves
  supplemental facts. It increments the authoritative trip version.
- `generate_backup_plans(trip_id, expected_version, max_plans, risk_ids,
  use_llm=False, request_id="")` produces and stores proposals. `max_plans` and
  `risk_ids` are explicit HTTP inputs. A canonical UUID request ID permits retries
  without duplicating observations or extending evidence.
- `review_backup_plan(trip_id, proposal_id, accept)` requires a raw boolean.
  Rejection does not change the itinerary. Acceptance reconfirms inventory,
  checks all constraints and changes only simulated state in one transaction.
- `create_planning_demo(scenario)` creates an explicit synthetic saved sample.

Supplemental context has `contract_version="roam.planning-context.v1"`, a Person 1
profile, IANA `zone`, `reserve_minor`, item facts keyed by saved ID, transfers,
P2 policies/forecasts/hours/evidence, and evidence deadlines. `planning/fixtures.jac`
contains a complete executable example. Saved item identity, dates, prices, paid
state, fixed rules and dependencies come from Roam/P4; a payload cannot replace them.
The API preserves explicit DST folds; P2 time inputs that would require guessing
a fold, and ambiguous cancellation deadlines, remain unresolved.

## Strategies and limits

P2 supplies weather, timing, long-drive, opening-hours and booking-terms risks.
Traveler reports additionally support closure, cancellation, traveler changes,
budget changes and inventory changes. Each request selects risks and affected
nodes. Strategies search different venues/providers, move existing items and
combine connected changes. Flexible downstream arrangements may stay or move;
fixed/completed boundaries remain protected. Every complete proposed itinerary
is validated, not just each replacement independently.

Search covers the explicit Boston/USD synthetic catalog: activities, dining,
transport and stays. It is bounded to eight affected nodes and 256 combinations;
truncation is reported. Up to five distinct passing or unresolved plans are shown.
Previously rejected candidate identities are excluded from fresh searches at
the same trip version. This is bounded feasibility search, not global optimization.
Known synthetic route evidence is restricted to the named demo venues. Arbitrary
saved locations need their own matching evidence.

AI selection is opt-in. It receives supplied validated plan IDs, interests and
computed metrics, with bounded retries. Unknown/hallucinated IDs or model failure
fall back to deterministic plans. The implementation does not let a model invent
inventory, money, evidence, refunds or validation.

## Money, freshness and persistence

Original and proposed totals include reserve. Paid original replacements are
retained as expenses; already-paid amounts on unchanged items are not added twice.
Unpaid confirmed-booking cancellation liability remains unresolved and blocks
acceptance until authoritative liability information exists. Cash refund
entitlements, credit and confirmed refunds are separate. No potential refund is
deducted from projected cost or available cash. A new purchase quote is not an
amount due now; payment timing remains unknown when not supplied.

`planning_contexts` supplements a saved trip; its writes increment P4's version.
`planning_runs` preserves immutable input snapshots, observations and rejected
decisions. Proposals reuse `replan_proposals`/`disruption_events`. Search checks
the trip version again before publication; retries preserve original deadlines
and cannot re-enable reviewed/obsolete results. Acceptance refreshes candidates,
rejects changed prices/availability, revalidates and atomically writes the chosen
nodes and retained payments. Client expiry, focus/storage reconciliation and
request/unmount guards prevent obsolete results from overwriting current views.

The original `preview_backups`, stateless fixture endpoints and standalone
sample/history lab remain compatible. The older guided replanning demo explicitly
uses its legacy catalog. The connected flow is entered through **Try connected
backup plans**; it passes P3's actual candidates to P4's application boundary.

## Source provenance

Feature files were imported unchanged from these existing PR heads; their source
branches and PR state are preserved:

| Source | Commit |
| --- | --- |
| P1 profile, PR #22 | `503c78301f574ae79aa9178acbbb9720c85c3fce` |
| P1 mandatory filter, PR #24 | `1b5d3dc7c30fa585202b95c7503268e498b7a3d0` |
| P1 budget, PR #27 | `b6656ddffc90f6e27083b3a7483f8a87111ab92a` |
| P2 schema/policy/risk, PR #16 | `50ee4b9cce85f1afa4a91f6c9ad5f97fd20044c5` |

The profile comes from #22's newer boolean-validation fix, rather than the older
profile copy in #24. Existing module tests are retained. Integration adapters and
`schema/alternative.jac` are new; the imported owners' feature implementations
are preserved.

## Verification

```sh
jac test server/ backup/ planning/ profile/ filter/ budget/ schema/ policy/ risk/
jac check --nowarn
jac build travel --as client
jac build backup_refresh --as client
jac run planning/demo.jac
```

See `docs/PROGRESS.md` for final current verification. Tests use temporary
databases. Browser verification uses isolated temporary travel/history files.
No clean-checkout CI, live provider/model call, real booking, payment or cancellation
is established by those checks.

The current local regression has **387 passing tests** under Jac 0.37.23. All four
application checks and both client builds pass. Sealed `jac build travel` still
fails during precompilation on the `TripView`/`ItemView` JSX type boundary;
`jac run --no-dev` returns 404 at the UI root in this setup. Development mode is
the verified local browser path. Restart the server after changing backend
modules so that imported code is loaded afresh.
