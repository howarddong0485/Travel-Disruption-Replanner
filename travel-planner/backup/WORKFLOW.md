# Unified backup workflow

**Current UI:** the saved-trip Backup plans panel now uses the connected
[planning integration](../planning/README.md). This document records the preserved
legacy sample/history workflow and its stateless/diagnostic interfaces.

Both the saved-trip **Backup plans** panel and the sample lab now run:

**Search → validate → refresh the same inventory IDs → revalidate → select Plan B/C → save → display.**

This is P3's module-owned workflow. Inventory and provider observations remain
synthetic. Shared traveler/risk/validation contracts, live providers, acceptance
and applying alternatives are separate work.

## Try it

From `travel-planner/`:

```sh
jac run --host 127.0.0.1 --port 8350 backup_refresh
```

- Choose **Synthetic sample trip** and select **Find backup plans**. The sample has complete synthetic facts for demonstrating
  passing checks, budget rejection and changing inventory.
- Choose **Saved Roam itinerary**, select an existing Boston/USD trip and a dated,
  unfinished activity or food item. Select the matching activation scenario and
  run the same action. This renders the same component used in Roam's Backup plans
  tab. It reads saved records and saves only backup observations.
- Review the candidate cards, availability and **What changes?** explanations.

Unsupported destinations/currencies produce an explicit empty result. Changing
the selected trip, target, scenario or inventory clears current results. Reopening
or switching back restores history and selected controls, but requires a new run
for a current result.

## Demo presentation defaults — 2026-10-29

The ordinary website and group demo show alternatives, cost/time changes and
actionable availability or uncertainty. Do not add developer check logs to that
view. Search traces, provider/item IDs, raw check lists, timestamps, internal
source URIs, saved revision numbers and refresh history are not rendered there.
The default UI also omits fault-injection controls and the extra validation lab
inside Roam. Necessary rejection/unknown states and the simulated-inventory label
remain visible.

Developers can explicitly open the standalone app with `?diagnostics=1` (for
example `http://127.0.0.1:8350/?diagnostics=1`) to see search exclusions, all checks,
calculation details, failure scenarios and persisted refresh history. This mode
is not enabled by ordinary Roam or its guided demo and is not a persistent browser
preference. Returning to the plain URL resets hidden failure scenarios to normal
inventory. Backend validation and snapshot persistence run in both views.

## Implementation and evidence boundaries

- `workflow.jac` searches the expanded mock pool, screens availability, currency,
  sources and expiry, rejects duplicate IDs, and materializes all supported
  candidates before initial validation and refresh. The current catalog has four
  supported candidates per scenario. `evaluated_count` counts these candidates;
  `selected_count` counts the final display options, which may be zero, one or two.
- `tools/alternatives/details.jac` supplies detailed synthetic facts keyed by the
  search inventory ID. The legacy search price is an unqualified estimate; it is
  not reused as a whole-party quote. Detailed fixture quotes explicitly cover the
  known party. Unknown party size leaves the amount unknown.
- `refresh.jac` refreshes those same IDs and revalidates. A missing ID or provider
  failure discards prior evidence. Each observation keeps its original identity.
- `selection.jac` selects up to two refreshed, passing alternatives, then fills
  remaining slots with received but unresolved alternatives labeled **Needs
  confirmation**. Invalid options and failed providers cannot fill a slot.
  Other evaluated candidates can replace rejected options; the full decision
  record is persisted and exposed only in diagnostics. Plan B/C are display labels,
  separate from stable provider IDs. See [selection policy and examples](SELECTION.md).
- `saved_inputs.jac` maps the actual target date and saved records without adding
  a fictional traveler profile, timezone, end time, quote or route evidence.
  A manually selected trigger remains unconfirmed risk. Those missing facts keep
  saved-trip candidates unresolved; numeric comparisons remain unknown when their
  supporting facts are absent. Packing items are excluded from itinerary checks.
- `history.jac` stores immutable inputs, observations, final checks, initial check
  trace, all evaluated candidates, selection decisions, provider IDs and calculated explanations. Old records without the new
  optional fields still load. History is not recalculated using later prices.
- `validation_frontend.jac` renders both modes. `frontend.jac` adapts Roam's saved
  trip props; `refresh_app.jac` also exposes both inputs for isolated verification.

## Saved-trip request lifecycle

`load_trip_backup_history(session_id, trip_id)` returns the selected trip's eligible
targets, current content fingerprint and history. `save_trip_backup_refresh(...)`
takes that fingerprint, a target, an expected history revision and a UUID request
ID. The existing sample endpoints use the same workflow and store.

Saved histories are namespaced by browser session and trip. Their localStorage
keys are `roam.backup.trip-session.v1:<trip_id>`; the sample continues to use
`roam.backup.sample-session.v1`. These are prototype history scopes, not user
authentication or shared-agent version IDs.

The service reads trip/items together and checks the content fingerprint before
generating and before appending. An intervening trip edit returns `trip_changed`
without saving the generated report. A final reread suppresses a report if a trip
edit or concurrent refresh has made it obsolete; history labels old snapshots
**Saved trip changed**. Trip edits in the parent UI remount the panel; focus/storage
events reconcile history. The immutable snapshot can remain recorded even if a
later edit makes it obsolete. Travel and history databases do not share an atomic
transaction, so this is not an application/version-lock boundary.

History writes retain optimistic revision checks and request-id idempotency.
Conflicts reload history; retries cannot extend old evidence or duplicate a saved
request. Generation and refresh never modify the original trip/items.

The legacy `preview_backups` API and storage-free `backup/demo.jac` remain for
compatibility. They still return the older draft contract. The Roam backup panel
now uses the saved-trip workflow endpoints above.
The stateless validation/refresh endpoints and `run_fixture` default retain the
two-candidate fixture behavior. Persisted sample and saved-trip workflows use the
expanded pool; `run_fixture(..., expanded=True)` opts into it explicitly.

## Verification — 2026-10-28

For the later candidate-selection slice, see [current verification](SELECTION.md#verification--2026-10-29).

Local runtime: Jac 0.37.21. Manifest-pinned 0.37.23 and clean-install CI are not
verified in this environment.

```sh
jac test server/main.test.jac server/test_backup.jac server/test_validation.jac server/test_refresh.jac server/test_history.jac server/test_backup_workflow.jac backup/test_planner.jac backup/test_validation.jac backup/test_refresh.jac backup/test_history.jac backup/test_changes.jac backup/test_workflow.jac
jac check --nowarn
jac build backup_refresh --as client
```

The combined suite has **105 passes and one existing MockLLM selection failure**
in `server/main.test.jac`. All 12 new workflow tests pass. They cover candidate
identity, exclusions, initial versus refreshed validation, serialization, missing
provider IDs, incomplete saved records, immutable travel data, request retries,
revision conflicts, history isolation and trip edits. The concurrent-edit test
calls the production service function directly with an injected edit; other
service lifecycle cases exercise the Jac HTTP bridge.

Four app checks and the standalone client build pass. Browser checks against
temporary travel/history databases cover both sample scenarios, saved-trip
scenarios, price changes, provider failure, empty inventory, history restoration,
trip isolation and rejection of a request based on an edited trip. Keyboard
expansion of the search trace works; at a 390px viewport the document width is
390px, with no horizontal overflow. No browser console errors were observed.
Travel database dumps remain unchanged by backup operations. The Roam browser regression script
has been updated to the new endpoint and controls; it has not been executed in
this verification run.

The full `travel` client build still fails in generated `replan/frontend.js` at
the existing dynamic object-key expression. Full Roam end-to-end success is not
claimed; the shared backup component is verified through `backup_refresh`.

## Delivery verification — 2026-10-29

The combined suite again reports **105 passed / 1 existing MockLLM failure** on
Jac 0.37.21. Four app checks and the final standalone client build pass.

Browser verification confirms that both sample and saved-trip views render zero
developer trace/history/evidence/check-list sections by default. Sample budget
rejection uses plain-language explanations; saved-trip unknowns remain visible.
The explicit diagnostics URL restores persisted observations and provider-failure
controls. Returning to the plain URL removes the records and uses normal inventory
even after saving a diagnostic failure. Storage still contains those observations.
The 390px layout has no horizontal overflow and the browser reports no console
errors. This run uses only isolated temporary travel/history databases.

The full-Roam browser script was updated for the presentation labels and absence
of diagnostic records; full-Roam execution remains outside the verified boundary.
