# Saved backup refresh history

Implementation for issues #28 and #29, based on the refresh slice at `06009b1`.
It extends the standalone synthetic
lab; it does not integrate shared traveler/risk/ledger contracts or apply a plan.

## Try it

From `travel-planner/`:

```sh
jac run --host 127.0.0.1 --port 8330 backup_refresh
```

Expand **Explore validation with a sample trip**, choose the scenario, traveler
requirements, budget, sample date and inventory change, then refresh. Each
successful save creates an immutable observation. Provider failures also save
their unresolved outcomes. Open **Refresh history** to inspect recorded outcomes,
costs, sources and failure reasons.

Reopening the page restores sample controls and history, but **never restores a
current validation result**. Explicitly refresh before using a current conclusion.
Historical passes are labeled as recorded outcomes, not current approval.
Changed inputs, expired evidence and superseded observations have explicit labels.
The page shows the newest 50 observations and the total; older rows remain stored.

The same component appears in Roam's **Backup plans** tab. Its history is separate
from the selected saved trip. Neither entry point exposes accept/apply controls.

## Storage and request semantics

- Default file: `.jac/data/backup-history.sqlite3`. Override it with
  `BACKUP_HISTORY_DB_PATH`. The store refuses the configured travel database path.
- `backup_runs` contains a session ID, increasing revision, unique request ID,
  normalized request fingerprint, schema/validator versions and a JSON snapshot.
  Snapshots include original trip/risk/candidate inputs, observed candidate facts
  and transfers, full validation results, sources and original validity deadlines.
- Only the session ID is stored in browser localStorage, under
  `roam.backup.sample-session.v1`. Results are loaded from SQLite. Blocking browser
  storage prevents automatic session recovery; the UI reports that limitation.
- Sessions separate sample histories, not users or authorization. This retains
  the existing local prototype's public endpoint model.
- Writes use a SQLite transaction and an expected revision. Concurrent new
  requests cannot overwrite one another; a stale writer gets a conflict and
  current history. Repeating a request ID with identical normalized inputs
  returns the original observation without extending its expiry. Reusing that ID
  with changed inputs fails. The HTTP boundary rejects booleans, strings, floats
  and negative values as revisions.
- Old retries never restore a superseded, expired or incompatible result.
  Historical reads recalculate reasons using the server clock and return only
  recorded summaries, not a current validation result.
- Different tabs invalidate visible results through storage notifications;
  focusing a tab also rechecks the latest history. Notifications arriving during
  a request are checked after it finishes. Request identities and cleanup guards
  prevent late responses from overwriting newer UI state.
- Observation revisions and fingerprints are **not authoritative trip versions**.
  No travel database tables or Person 4 version/acceptance logic are changed.

## Files and endpoints

- `backup/history.jac`: isolated storage, atomic append, retry rules and history.
- `backup/refresh.jac`: serializable original inputs and observed evidence.
- `server.main.load_backup_history(session_id)`: newest-first history, defaults
  and latest revision; no current report is returned.
- `server.main.save_backup_refresh(...)`: server-generated refresh and atomic save;
  takes canonical UUID session/request IDs, a nonnegative integer expected revision
  and the selected sample context. A sample date is required for stable retries.
- `backup/validation_frontend.jac`: controls, current checks and historical views.

Existing `preview_backup_validation` and `refresh_backup_validation` remain
stateless for compatibility. Live inventory, shared handoff, financial comparison
and accepting/applying alternatives remain outside this slice.

## Verification

```sh
jac test backup/test_history.jac server/test_history.jac
jac check --nowarn
jac build backup_refresh --as client
```

On local Jac 0.37.21, the 15 storage tests and HTTP lifecycle test pass. They cover
new connections/service instances, exact persisted snapshots, expiry, changed
inputs, incompatible versions, clock rollback, failure/recovery, idempotency,
concurrent writers, rollback, isolation, bounded reads and invalid inputs.
The HTTP test compares the complete saved-trip SQLite dump before and after.
The combined suite is **80 passed, 1 existing MockLLM selection failure**.
Pinned Jac 0.37.23 and clean-install CI have not been verified.

Four application checks and the standalone client build pass. Browser verification
used a separate temporary history database on port 8330 and covered empty state,
saved versions, page reload, actual server-process restart, provider failure/recovery,
budget rejection, invalid input without an extra saved row, profile/date restoration,
cross-tab invalidation, expired-history labels and keyboard expansion/date editing.
At a 390px viewport, document width was 390px with no horizontal overflow.
The browser date field was exercised with native keyboard events; the browser
automation fill operation alone did not commit its value. Late network responses
and exact client expiry deadlines were code-reviewed; deterministic server-clock
tests cover expiration. The complete travel build retains its pre-existing
generated replanning JavaScript blocker.
