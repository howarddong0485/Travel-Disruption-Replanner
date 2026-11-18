# Launch-guide implementation

This follows the supplied Group 13 Roam launch guide, based on PR #56 plus the
Replan fixes in PR #58. It does not merge those PRs or establish a public deployment.

| Guide requirement | Implementation / acceptance evidence |
| --- | --- |
| Applicable policy excerpt, fee, deadline and questions beside alternatives | `policy/review.jac` builds evidence-bound review data; connected candidate cards, itinerary review and AI drafts render `itinerary/policy_review.jac`. Missing/expired evidence or required inputs stays unresolved; free, fee-qualified and explicitly excluded refunds remain distinct. |
| Bring policy/risk output into the traveler panel | Backup plans shows cancellation review, source/freshness and risk mitigation. The terms form runs the existing deterministic extractor and saves exact source evidence with version checks. It neither books nor cancels. |
| Whole-trip validation in Jac | Existing connected-plan and journey validators plus `replan/connections.jac` enforce saved connections; evidence is rechecked on acceptance. Currency adapters use true JPY/KRW minor units at policy boundaries while keeping the existing Roam ledger storage. |
| Unknown fare disables apply | AI `cost_cents=None` leaves total unknown and `can_apply=false`; connected plans retain unknown quotes and reject acceptance. Explicit zero remains distinct from unknown. |
| Explicit review/apply and protected items | The assistant keeps paid/fixed/completed/referenced arrangements unchanged. Request identity, fingerprint, version, expiry and a second validation guard acceptance. The UI refreshes expired/stale cards and shows readable errors. |
| Storm, fees, tight transfer, unknown fare, edits during review | `planning/test_launch_review.jac` covers storm candidates with fee evidence, policy states/freshness, source saving and stale rejection with unchanged items. `planning/test_connections.jac`, `assistant/test_replan_regressions.jac`, and `assistant/test_workflow.jac` cover transfer timing, unknown fares, protected items, reject/accept and expiry. |

Potential refunds are not received cash and are not deducted from trip totals.
Unknown policy consequences remain visible even when timing and budget checks
pass. A local itinerary revision is never presented as supplier confirmation.
The UI shows the saved original booking's policy; it does not invent a policy
for an unbooked replacement or claim that a reschedule is supplier-authorized.

## Reproduce

Use the repository's pinned Jac 0.37.23 / Python 3.14 runtime:

```sh
bash scripts/setup.sh
bash scripts/verify.sh
```

The guide's Jac 0.39.2 footer is a documentation reference, not a tested runtime
migration requirement. Runtime upgrades need their own compatibility work.

Local verification on November 17, 2026: four application checks, 1,010 test
executions in the full suite, both client builds, and the 3/5/5 demo checks
passed. After the final policy-expiry display change, the component check,
72 focused test executions, sealed bundle build, and HTTP/CLI smoke checks
against both source and the bundle outside the checkout passed. Test counts
include imported suites, not just newly added tests.

Browser verification used a disposable local trip and synthetic inventory:
saving revised source terms changed the displayed fee from USD 10 to USD 15
and the potential refund from USD 35 to USD 30; alternatives displayed the
same exact excerpt and source. At evidence expiry, the page automatically
removed expired alternatives and replaced the fee/refund conclusions with
"Unknown until rechecked". This does not establish live supplier pricing
or a fresh model-driven end-to-end run.

## Hosted handoff (JacHammer target pending)

The user will supply the JacHammer project or deployment URL. No target or
credentials have been assumed and no public deployment has been performed.
Build the bundle on the target operating system/architecture and Python version;
do not deploy a macOS precompiled bundle onto Linux.

Configure secret values in the host's server secret store, never Git or client
assets: `OPENAI_API_KEY`, and optional `GEOAPIFY_API_KEY`, `LITEAPI_API_KEY`, or
Expedia credentials only for enabled providers. Model names can be configured
with `OPENAI_CHAT_MODEL` and `OPENAI_PLANNING_MODEL`.

Mount persistent storage and set distinct absolute `TRAVEL_DB_PATH` and
`BACKUP_HISTORY_DB_PATH`. Set `PORT` to the host-assigned port. The verified start
entry point is `bash scripts/start_hosted.sh`; set `ROAM_BIND_HOST=0.0.0.0` only
inside the host's protected network when its reverse proxy requires it. Health
check: `/healthz/ready`. An alternate bundle path uses `ROAM_APP_BUNDLE`.

Each browser profile owns a private workspace. The server checks ownership on
trip reads and mutations. Existing rows from the shared prototype remain
unassigned. Use HTTPS and persistent storage for visitor workspaces.

Once the target is supplied, verify on that actual host:

- Client assets, real routing/weather inputs and provider failure states; source
  timestamps and missing inputs must remain visible. Existing synthetic backup
  inventory must stay labelled synthetic.
- Save a dedicated test trip, restart the app, and confirm persistence.
- Produce an AI draft with the server key; verify amounts and policy evidence.
- Edit the trip while a draft waits, reject the stale save, then test expiry.
- Reject a proposal and confirm the original trip is unchanged; accept a valid
  proposal and compare stored items with the reviewed changes.

Do not run `runtime_smoke.jac` against a populated public database: its contract
requires a new disposable store. Use the hosting platform's staging instance.
