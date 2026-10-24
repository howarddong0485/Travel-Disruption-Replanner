# Disruption and dependency-aware replanning

This is a working mock-data prototype inside Roam. Select a scheduled item, mark it delayed or interrupted, inspect several combinations of backups, optionally build a custom combination, then explicitly accept a revised plan. Nothing makes or cancels a real reservation.

## Try it

From `travel-planner/`:

```sh
jac install
jac run --dev travel
```

Click **Try a mock replanning trip** in the sidebar. This creates a separate synthetic trip. In **Replan**, delay **Flight arrival** by **180 minutes**, then click **Find revised plans**. Rental-car pickup and dinner miss their windows, hotel check-in moves, and the fixed next-day museum remains unchanged. Compare alternatives or use **Build your own combination** to mix individual backups. Rejecting leaves the itinerary unchanged; accepting applies the stored proposal.

For your own trip, enter dates and times, set durations/latest-start windows in **Schedule rules**, and connect dependent items. The transfer buffer is added after the prerequisite's duration. A blank latest-start window treats an arrangement as flexible. Existing itineraries have no implicit dependencies; the engine does not guess them from titles or chronological order. `done` means confirmed for transport/stays in Roam; completed food/activity items and explicitly fixed items are protected.

## Optional Jac LLM selection

The implementation follows Jac's [byLLM documentation](https://docs.jaseci.org/reference/plugins/byllm/). `agent.jac` declares a typed `ReplanSelection` and delegates selection with `by replan_model(...)`. Its `sem` annotations describe allowed selections and explanations. The model receives up to twelve prevalidated combinations of mock backup IDs, dates/times, and deterministic cost metrics. Booking references, traveler notes, and payment credentials are excluded.

`jac install` resolves the LLM capability declared by `[byllm.model]` in `jac.toml`. The default is `gpt-4o-mini`; to enable it, set a provider key in the **server** environment before launching and check **Use LLM to choose backup combinations**:

```sh
export OPENAI_API_KEY="your-key"
jac run --dev travel
```

To choose another configured provider/model, set `BYLLM_DEFAULT_MODEL` and its matching provider credentials. For an already-running local Ollama model, for example:

```sh
export BYLLM_DEFAULT_MODEL="ollama/llama3.2"
jac run --dev travel
```

No key is required for the deterministic mock workflow or MockLLM tests. LLM selection is opt-in, has a 25-second provider timeout and bounded structured-output retry, and cannot write the database. Unsupported/duplicate combination IDs, provider failures, or missing credentials produce a visible fallback to validated mock combinations. The model chooses combinations and explains them; deterministic code computes schedules and costs. No live provider call was needed to verify the typed Jac path.

## Modules and service interfaces

| File | Responsibility |
| --- | --- |
| `../events/simulator.jac` | Normalize delayed/interrupted simulated events with stable IDs and UTC observation timestamps |
| `backups.jac` | Three synthetic backups per transport, stay, food, and activity category |
| `engine.jac` | Dependency traversal, bounded combination search, scheduling, validation, proposal persistence and atomic application |
| `agent.jac` | Typed Jac LLM selection over supplied combinations |
| `frontend.jac` | Simulation, schedule/dependency editing, inventory, custom combinations and proposal review |
| `../server/main.jac` | Public Jac endpoints sharing the existing SQLite connection |

Public endpoints are `replan_demo`, `replan_state`, `replan_save_rules`, `replan_save_dependency`, `propose_replan`, `combine_replan`, and `review_replan`. `propose_replan` accepts `trip_id`, `item_id`, `kind`, `delay_minutes`, optional `event_id`, and `use_llm`. It returns `event_id`, `affected`, `backups`, `proposals`, `warnings`, and `mode`. A proposal contains its stored ID, base version, before/after changes, selected backup IDs, reasons and computed cost metrics. `combine_replan` accepts the pending event ID and an item-ID-to-backup-ID mapping. `review_replan` accepts a stored proposal ID and an explicit accept/reject decision.

## State and validation

The existing database is extended additively with trip versions, schedule rules, dependency edges, events and proposals. SQLite triggers advance the version for trip/item writes from both web and CLI, and schedule/dependency edits. Proposal generation never changes active items. Acceptance uses `BEGIN IMMEDIATE`, reloads the current version, revalidates, applies all changes, and records the event as applied in one transaction. Duplicate events can be regenerated while pending; this supersedes their earlier proposals. Applied events cannot be applied again. Other pending proposals become stale when the trip changes.

The full proposed itinerary is checked for dependency cycles, transfer buffers, overlaps among known scheduled items, latest-start windows, protected-item conflicts, changed-item trip bounds, and the existing trip budget. Unscheduled affected items require clarification. Repairs preserve stable item IDs and dependency edges. Candidate generation is capped at 256 combinations and eight affected items, with truncation disclosed.

Paid originals replaced by a backup remain as paid expense records because refund eligibility is unknown. Replacement items are unpaid/unconfirmed. Projected total includes retained prior payments, existing unaffected costs, and replacements. New replacement purchases are shown separately. Refund losses/entitlements are not invented. A paid delayed item that is merely rescheduled retains its payment state.

This prototype uses Roam's destination-local timestamps and two-decimal money convention. It does not yet implement cross-zone travel, provider availability/opening-hour evidence, policy-based refunds, location routing, profiles or dietary/pet/child/accessibility validation. Mock alternatives are flexible synthetic inventory, not eligible/reservable real products. Shared ConstraintValidator, BudgetLedger, evidenced policy adapters, and refreshed BackupAgent inventory remain integration points for the other feature owners. Risk/backups are not automatically regenerated after acceptance yet.

## Verification

```sh
jac check --nowarn
jac test server/main.test.jac
jac build travel --as client
```

The service tests cover the original planner plus delay cascades, fixed-node preservation, custom combinations, rejection, stale proposals, event deduplication, cycles, missing timing, retained payments, budgets, independent timing boundaries, rollback, and the actual typed `by` path using MockLLM. All tests use temporary trip databases.

If Jac cannot initialize its embedded Postgres store for HTTP tests, `jac db fetch` provisions its separate framework runtime. This does not move Roam's SQLite trip data.
