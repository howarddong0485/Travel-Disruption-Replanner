"""Shared sample/saved-trip backup workflow using Roam's controls and styles."""
import from server.main { load_backup_history, save_backup_refresh, load_trip_backup_history, save_trip_backup_refresh }

def:pub BackupChanges(changes: dict[str, any], historical: bool = False, diagnostics: bool = False) -> JsxElement {
    def money(value: any) -> str {
        if value is None { return "Unknown"; }
        return "USD " + (value / 100).toFixed(2);
    }
    def difference(value: any) -> str {
        if value is None { return "Unknown"; }
        if value == 0 { return "No change"; }
        return money(abs(value)) + (" more" if value > 0 else " less");
    }
    def shift(value: any, duration: bool = False) -> str {
        if value is None { return "Unknown"; }
        if value == 0 { return "No change"; }
        direction = ("longer" if value > 0 else "shorter") if duration else ("later" if value > 0 else "earlier");
        return str(abs(value)) + " min " + direction;
    }
    def moment(value: any) -> str {
        return value["local"] + " · " + value["zone"] + (" · fold " + str(value["fold"]) if value["fold"] is not None else "");
    }
    costs = changes["cost"]; schedule = changes["schedule"];
    return <section className="backup-changes" aria-label={"Recorded changes" if historical else "Changes from original plan"}>
        <h4>{"Changes when recorded" if historical else "What changes?"}</h4>
        <p>{changes["original_title"] + " → " + changes["proposed_title"]}<br/>
            <small>{str(changes["unchanged_item_count"]) + (" other itinerary item unchanged" if changes["unchanged_item_count"] == 1 else " other itinerary items unchanged")}</small></p>
        <dl className="validation-costs">
            <div><dt>Original planned total</dt><dd>{money(costs["original_total_minor"])}</dd></div>
            <div><dt>Proposed whole-trip total</dt><dd>{money(costs["proposed_total_minor"])}</dd></div>
            <div><dt>Change in planned total</dt><dd>{difference(costs["delta_minor"])}</dd></div>
            <div><dt>Budget remaining</dt><dd>{money(costs["budget_remaining_minor"])}</dd></div>
            <div><dt>Start time change</dt><dd>{shift(schedule["start_shift_minutes"])}</dd></div>
            <div><dt>End time change</dt><dd>{shift(schedule["end_shift_minutes"])}</dd></div>
            <div><dt>Duration change</dt><dd>{shift(schedule["duration_delta_minutes"], True)}</dd></div>
        </dl>
        <p className="muted">These are changes to the planned total. No refund is assumed.</p>
        {(<ul>{[<li key={str(i)}>{reason}</li> for (i, reason) in enumerate(changes["unknown_reasons"])]}</ul>) if diagnostics and len(changes["unknown_reasons"]) > 0 else None}
        {(<p className="muted">Some costs or times still need confirmation.</p>) if not diagnostics and len(changes["unknown_reasons"]) > 0 else None}
        {(<details><summary>{"Recorded calculation details" if historical else "Calculation details"}</summary>
            <p>{changes["notice"]}</p>
            <p>{"Original item quote: " + money(costs["original_quote_minor"]) + "; replacement quote: " + money(costs["replacement_quote_minor"])}</p>
            <p>{"Original: " + moment(schedule["original_start"]) + " → " + moment(schedule["original_end"])}</p>
            <p>{"Proposed: " + moment(schedule["proposed_start"]) + " → " + moment(schedule["proposed_end"])}</p>
            <p>Time differences use elapsed time across timezones and daylight saving changes.</p>
        </details>) if diagnostics else None}
    </section>;
}

def:pub ValidationLab(trip_id: str = "", initial_target: str = "", initial_trigger: str = "rain", onGenerated: any = None, diagnostics: bool = False) -> JsxElement {
    has scenario: str = initial_trigger, profile: str = "family", budget: str = "600", target: str = initial_target,
        pending: bool = False, failure: str = "", result: dict[str, any] | None = None,
        expired: bool = False, timer: Ref[int] = Ref(0), requestRef: Ref[int] = Ref(0),
        inventory: str = "unchanged", sampleDate: str = "", booting: bool = True,
        history: dict[str, any] | None = None, revision: int = 0, notice: str = "",
        sessionId: Ref[str] = Ref(""), retryId: Ref[str] = Ref(""),
        historyClock: float = 0, historyTimer: Ref[int] = Ref(0), syncListener: Ref[any] = Ref(None),
        syncQueued: Ref[bool] = Ref(False);
    prefix = "saved-backup" if trip_id else "validation";
    storageKey = "roam.backup.trip-session.v1:" + trip_id if trip_id else "roam.backup.sample-session.v1";

    async def fetchHistory -> dict[str, any] {
        if trip_id { return await load_trip_backup_history(session_id=str(sessionId.current or ""), trip_id=trip_id); }
        return await load_backup_history(session_id=str(sessionId.current or ""));
    }

    can with entry {
        initialize();
        browser: any = window;
        syncListener.current = lambda (event: any) {
            if event.type == "focus" or event.key == "roam.backup.refresh-notice.v1" { reconcile(); }
        };
        browser.addEventListener("storage", syncListener.current);
        browser.addEventListener("focus", syncListener.current);
    }
    can with [history, historyClock] entry {
        if historyTimer.current { window.clearTimeout(historyTimer.current); historyTimer.current = 0; }
        if history {
            future = [Date.parse(record["expires_at"]) for record in history["entries"] if Date.parse(record["expires_at"]) > Date.now()];
            if len(future) > 0 {
                historyTimer.current = window.setTimeout(lambda { historyClock = Date.now(); }, max(1.0, min(future) - Date.now() + 1.0));
            }
        }
    }
    async def initialize -> None {
        browser: any = window;
        booting = True; failure = "";
        requestRef.current += 1; request = requestRef.current;
        try {
            try {
                saved = browser.localStorage.getItem(storageKey);
                valid = saved and browser.RegExp("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").test(saved);
                sessionId.current = saved if valid else browser.crypto.randomUUID();
                browser.localStorage.setItem(storageKey, sessionId.current);
            } except Exception {
                sessionId.current = browser.crypto.randomUUID();
                notice = "Browser storage is unavailable. This session cannot be restored after closing the page.";
            }
            restored = await fetchHistory();
            if request != requestRef.current { return; }
            history = restored; revision = restored["revision"];
            context = restored["context"];
            scenario = context["scenario"]; profile = context["profile_name"];
            budget = context["budget"]; inventory = context["inventory_change"] if diagnostics else "unchanged"; sampleDate = context["sample_date"];
            if not diagnostics and scenario not in ("rain", "arrival_delay") { scenario = "rain"; }
            if trip_id {
                target = initial_target or context.get("item_id", "");
                if initial_target { scenario = initial_trigger; }
            }
            if revision > 0 { notice = "Saved history restored. Refresh to obtain a current result; historical checks are not current approval." if diagnostics else "Your preferences are restored. Find alternatives to see current options."; }
        } except Exception {
            if request == requestRef.current { failure = "Could not load backup history. Retry loading before refreshing."; }
        } finally {
            if request == requestRef.current {
                booting = False;
                if syncQueued.current { reconcile(); }
            }
        }
    }

    can with [result] entry {
        if timer.current { window.clearTimeout(timer.current); timer.current = 0; }
        if result {
            timer.current = window.setTimeout(lambda { result = None; expired = True; },
                max(0.0, Date.parse(result["expires_at"]) - Date.now()));
        }
    }
    can with exit {
        browser: any = window;
        requestRef.current += 1;
        if timer.current { window.clearTimeout(timer.current); }
        if historyTimer.current { window.clearTimeout(historyTimer.current); }
        browser.removeEventListener("storage", syncListener.current);
        browser.removeEventListener("focus", syncListener.current);
    }
    def clear -> None {
        requestRef.current += 1;
        if timer.current { window.clearTimeout(timer.current); timer.current = 0; }
        result = None; failure = ""; expired = False;
    }
    def inputChanged -> None { clear(); retryId.current = ""; notice = "Find alternatives again to use these preferences."; }
    async def reconcile -> None {
        if booting or pending { syncQueued.current = True; return; }
        if history is None { return; }
        syncQueued.current = False;
        request = requestRef.current;
        try {
            latest = await fetchHistory();
            if request != requestRef.current { return; }
            reasons = latest["entries"][0]["reasons"] if len(latest["entries"]) > 0 else [];
            invalidated = "version_changed" in reasons or "clock_invalid" in reasons or "evidence_expired" in reasons or "trip_changed" in reasons or
                (trip_id and latest.get("base_snapshot") != history.get("base_snapshot"));
            if latest["revision"] != revision or invalidated {
                clear(); retryId.current = ""; revision = latest["revision"];
                notice = "Your trip or availability has changed. Find alternatives again.";
            }
            history = latest;
        } except Exception {
            if request == requestRef.current {
                clear(); failure = "Could not verify saved history. Refresh again before using a result.";
            }
        }
    }
    async def run -> None {
        browser: any = window;
        if pending or booting or history is None { return; }
        clear(); pending = True; notice = "";
        if not retryId.current { retryId.current = browser.crypto.randomUUID(); }
        request = requestRef.current;
        try {
            response: dict[str, any] = {};
            if trip_id {
                response = await save_trip_backup_refresh(session_id=str(sessionId.current or ""), request_id=str(retryId.current or ""),
                    expected_revision=revision, trip_id=trip_id, item_id=target, trigger=scenario,
                    inventory_change=inventory, expected_base_snapshot=history["base_snapshot"]);
            } else {
                response = await save_backup_refresh(session_id=str(sessionId.current or ""), request_id=str(retryId.current or ""),
                    expected_revision=revision, scenario=scenario, profile_name=profile,
                    budget=budget, inventory_change=inventory, sample_date=sampleDate);
            }
            if request != requestRef.current { return; }
            retryId.current = ""; history = response["history"]; revision = history["revision"];
            nextResult = response["report"];
            if response["outcome"] == "trip_changed" {
                notice = "The saved trip changed. Choose an item and find alternatives again.";
            } elif response["outcome"] == "conflict" {
                notice = "Your options were updated in another window. Find alternatives again.";
            } elif nextResult is None {
                notice = "These options are no longer current. Find alternatives again.";
            } elif Date.parse(nextResult["expires_at"]) <= Date.now() { expired = True; }
            else {
                result = nextResult; budget = history["context"]["budget"];
                sampleDate = history["context"]["sample_date"]; profile = history["context"]["profile_name"];
                notice = "Saved refresh #" + str(response["revision"]) + "." if diagnostics else "";
                if onGenerated and len(nextResult["results"]) > 0 { onGenerated(); }
            }
            try { browser.localStorage.setItem("roam.backup.refresh-notice.v1", str(sessionId.current) + ":" + str(revision)); }
            except Exception { notice = notice + " Other tabs will recheck history when focused."; }
        }
        except Exception {
            if request == requestRef.current {
                failure = "Could not load alternatives. Reload this trip if the selected item was removed or completed, then try again." if trip_id else
                    "Could not load alternatives. Enter a valid budget (up to two decimal places) and try again.";
            }
        }
        finally {
            if request == requestRef.current {
                pending = False;
                if syncQueued.current { reconcile(); }
            }
        }
    }
    def money(value: any) -> str {
        if value is None { return "Unknown"; }
        return "USD " + (value / 100).toFixed(2);
    }
    def label(status: str) -> str {
        if status == "passed_fixture_checks" { return "Fixture checks passed" if diagnostics else "Available in this demo"; }
        if status == "invalid" { return "Does not meet requirements"; }
        return "Needs more evidence" if diagnostics else "Needs confirmation";
    }
    def unavailableReason(option: dict[str, any]) -> str {
        messages = {"budget": "This option exceeds your trip budget.",
            "availability": "This option is currently sold out.",
            "protected_item": "This would replace a fixed or completed item.",
            "eligibility": "This option does not support all traveler requirements.",
            "child_age": "This option does not meet the children's admission requirements.",
            "overlap": "This option overlaps another activity.",
            "transfer": "Travel between activities does not fit the itinerary.",
            "arrival_delay": "This dinner starts before your revised arrival.",
            "opening_hours": "The visit does not fit the available opening hours.",
            "trip_bounds": "This option falls outside your trip dates."};
        reasons: list[str] = [];
        for check in option["checks"] {
            if check["status"] == "fail" {
                message = messages.get(check["code"], "This option cannot fit the current trip. Review the itinerary and traveler details.");
                if message not in reasons { reasons.append(message); }
            }
        }
        return " ".join(reasons[:2]);
    }
    def historicalState(record: dict[str, any]) -> str {
        context = record["context"];
        reasons: list[str] = [];
        if context["scenario"] != scenario or context["profile_name"] != profile or context["budget"] != budget or context["inventory_change"] != inventory or context["sample_date"] != sampleDate {
            reasons.append("Inputs changed");
        }
        if "version_changed" in record["reasons"] or "clock_invalid" in record["reasons"] { reasons.append("Requires new checks"); }
        if "trip_changed" in record["reasons"] { reasons.append("Saved trip changed"); }
        if trip_id and context.get("item_id") != target { reasons.append("Different target"); }
        if Date.parse(record["expires_at"]) <= Date.now() { reasons.append("Evidence expired"); }
        if record["revision"] != revision { reasons.append("Superseded"); }
        return (" · ".join(reasons) if len(reasons) > 0 else "Latest saved observation") + " · history only";
    }
    def inventoryLabel(value: str) -> str {
        labels = {"unchanged": "Original inventory", "price_increase": "First inventory option price increased",
            "sold_out": "First inventory option sold out", "all_sold_out": "All inventory sold out",
            "expired_evidence": "First inventory option evidence expired", "provider_failure": "All providers failed",
            "partial_failure": "First inventory provider failed"};
        return labels.get(value, "Inventory observation");
    }
    eligible = [item for item in (history.get("targets", []) if history else []) if item["category"] == ("activity" if scenario == "rain" else "food")];
    return <details className="card validation-lab" open={True}>
        <summary><span>{"Backup plans for this trip" if trip_id else "Sample trip backup plans"}</span></summary>
        <div className="validation-content">
            <p>{"Choose an activity or dinner to explore alternatives. Your saved itinerary stays unchanged." if trip_id else
                "Explore Plan B / C options for a Boston sample trip."}</p>
            <p className="muted">Demo inventory: venues, prices and availability are simulated. No booking is made.</p>
            {(<p className="muted">Search → Validate → Refresh and recheck → Save → Review.</p>) if diagnostics else None}
            {(<p role="status">Loading your preferences…</p>) if booting else None}
            {(<button type="button" className="secondary" onClick={lambda { clear(); retryId.current = ""; initialize(); }}>Reload options</button>) if not booting and (history is None or (trip_id and failure)) else None}
            {(<p role="status">{notice}</p>) if notice else None}
            {(<div className="validation-controls">
                <div><label htmlFor={prefix + "-trigger"}>Activation scenario</label>
                    <select id={prefix + "-trigger"} value={scenario} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { scenario = e.target.value; target = ""; inputChanged(); }}>
                        <option value="rain">Rain affects an outdoor activity</option><option value="arrival_delay">Delayed arrival affects dinner</option>
                    </select></div>
                <div><label htmlFor={prefix + "-target"}>Original itinerary item</label>
                    <select id={prefix + "-target"} value={target} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { target = e.target.value; inputChanged(); }}>
                        <option value="">Choose an item</option>{[<option key={item["id"]} value={item["id"]}>{item["title"] + " · " + item["date"]}</option> for item in eligible]}
                    </select></div>
                {(<p>Add a dated, unfinished activity or dining item to this trip to search for backups.</p>) if len(eligible) == 0 else None}
            </div>) if trip_id else (<div className="validation-controls">
                <div><label htmlFor={prefix + "-scenario"}>Sample scenario</label>
                    <select id={prefix + "-scenario"} value={scenario} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { scenario = e.target.value; inputChanged(); }}>
                        <option value="rain">Rain · indoor alternatives</option>
                        <option value="arrival_delay">Delayed arrival · later dinner</option>
                        {(<optgroup label="Diagnostic scenarios"><option value="missing_evidence">Missing price and policy evidence</option>
                        <option value="eligibility_conflict">Pet, child and accessibility conflict</option>
                        <option value="schedule_conflict">Overlapping event and short transfer</option>
                        <option value="fixed_item">Protected original item</option>
                        <option value="stale_evidence">Expired candidate evidence</option></optgroup>) if diagnostics else None}
                    </select></div>
                <div><label htmlFor={prefix + "-profile"}>Traveler requirements</label>
                    <select id={prefix + "-profile"} value={profile} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { profile = e.target.value; inputChanged(); }}>
                        <option value="family">Family · vegetarian, dog, wheelchair</option>
                        <option value="solo">Solo adult · no additional requirements</option>
                    </select></div>
                <div><label htmlFor={prefix + "-budget"}>Whole-trip budget (USD)</label>
                    <input id={prefix + "-budget"} inputMode="decimal" value={budget} placeholder="Empty means unknown" maxLength={24} disabled={pending or booting}
                        onChange={lambda (e: ChangeEvent) { budget = e.target.value; inputChanged(); }}/></div>
                <div><label htmlFor={prefix + "-date"}>Sample trip date</label>
                    <input id={prefix + "-date"} type="date" value={sampleDate} disabled={pending or booting}
                        onChange={lambda (e: ChangeEvent) { sampleDate = e.target.value; inputChanged(); }}/></div>
            </div>)}
            {(<div className="validation-refresh-control"><label htmlFor={prefix + "-inventory"}>Inventory on next refresh</label>
                <select id={prefix + "-inventory"} value={inventory} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { inventory = e.target.value; inputChanged(); }}>
                    <option value="unchanged">Fresh inventory · original sample prices</option>
                    <option value="price_increase">First inventory option price rises by USD 200 for the whole party</option>
                    <option value="sold_out">First inventory option sold out</option>
                    <option value="all_sold_out">All alternatives sold out</option>
                    <option value="expired_evidence">First inventory option returns expired evidence</option>
                    <option value="provider_failure">All providers fail</option>
                    <option value="partial_failure">First inventory provider fails · others respond</option>
                </select>
                <p className="muted">Each selection is a separate inventory snapshot; price changes do not accumulate. Refresh replaces all previous conclusions.</p>
            </div>) if diagnostics else None}
            <button type="button" className="primary" disabled={pending or booting or history is None or (bool(trip_id) and not any(item["id"] == target for item in eligible))} onClick={run}>{"Finding alternatives…" if pending else "Find backup plans"}</button>
            {(<p role="status">Availability has expired. Find alternatives again for current options.</p>) if expired else None}
            {(<p className="alert error" role="alert">{failure}</p>) if failure else None}
            {(<div className="validation-results" aria-live="polite">
                <p role="status">{result["selection"]["message"] if result.get("selection") else result["message"] if diagnostics else ("No alternatives are available for this destination and currency." if len(result["results"]) == 0 else "Review the alternatives below. Your itinerary has not changed.")}</p>
                {(<p><strong>{result["profile_summary"]}</strong><br/>{"Item date: " if trip_id else "Sample date: "}{result["trip_date"]} · {result.get("trip_zone", "America/New_York")}</p>) if diagnostics else None}
                {(<section className="backup-pipeline" aria-label="Backup workflow">
                    <p>{"Searched " + str(result["pipeline"]["searched_count"]) + " inventory records → Checked " + str(result["pipeline"].get("evaluated_count", result["pipeline"]["selected_count"])) + " candidates → Refreshed and rechecked → Selected " + str(result["pipeline"]["selected_count"]) + " → Saved #" + str(revision)}</p>
                    <p>{"Inventory IDs: " + (result["pipeline"]["provider_ids"].join(", ") or "None")}</p>
                    <details><summary>Search exclusions and initial checks</summary>
                        <ul>{[<li key={str(i)}>{r["provider_id"] + ": " + r["reason"]}</li> for (i, r) in enumerate(result["pipeline"]["exclusions"])]}</ul>
                        <ul>{[<li key={r["provider_id"]}>{r["provider_id"] + " · Before refresh: " + label(r["status"])}</li> for r in result["pipeline"]["initial_checks"]]}</ul>
                    </details>
                    {(<details><summary>Candidate selection decisions</summary>
                        <p>Passed alternatives come first, then options needing confirmation. Search order is preserved within each group; price is not a ranking score.</p>
                        <ul>{[<li key={d["provider_id"]}>{d["provider_id"] + " · " + d["reason"] + " · " + label(d["status"])}
                            <ul>{[<li key={str(i)}>{c["message"]}</li> for (i, c) in enumerate(d["checks"])]}</ul>
                        </li> for d in result["selection"]["decisions"]]}</ul>
                    </details>) if result.get("selection") else None}
                </section>) if diagnostics and result and result.get("pipeline") else None}
                {(<p>{str(result["summary"]["passed_fixture_checks"]) + " passed · " + str(result["summary"]["invalid"]) + " rejected · " + str(result["summary"]["needs_validation"]) + " awaiting evidence"}</p>) if diagnostics else None}
                <div className="backup-options">{[<article className="backup-option validation-option" key={option["candidate_id"]}>
                    <p className="eyebrow">{(option.get("display_label", option["candidate_id"]) + " · " + option.get("provider_id", option["candidate_id"])) if diagnostics else option.get("display_label", "Plan B" if option["candidate_id"] == "plan-b" else "Plan C")}</p><h3>{option["title"]}</h3>
                    {(<p className="validation-provider-error">Availability could not be refreshed. Please try again.</p>) if option["refresh_state"] == "provider_error" else None}
                    <p className="validation-status" data-status={option["status"]}>{label(option["status"])}</p>
                    {(<p>Traveler details, timing or pricing still need confirmation before using this option.</p>) if not diagnostics and option["status"] == "needs_validation" else None}
                    {(<p>{unavailableReason(option)}</p>) if not diagnostics and option["status"] == "invalid" else None}
                    <dl className="validation-costs">
                        <div><dt>Proposed whole-trip cost</dt><dd>{money(option["cost"]["projected_total_minor"])}</dd></div>
                        <div><dt>Original payment retained</dt><dd>{money(option["cost"]["retained_original_payment_minor"])}</dd></div>
                        <div><dt>Reserve included</dt><dd>{money(option["cost"]["reserve_minor"])}</dd></div>
                        <div><dt>Budget</dt><dd>{money(option["cost"]["budget_minor"])}</dd></div>
                    </dl>
                    <p className="muted">No refund assumed. Totals require whole-party quotes including taxes and fees.</p>
                    {(<BackupChanges changes={option["changes"]} diagnostics={diagnostics}/>) if option.get("changes") else None}
                    {(<ul className="validation-reasons">{[<li key={str(index)}><strong>{"Failed" if check["status"] == "fail" else "Unknown"}: </strong>{check["message"]}
                        <small>{(" · " + check["item_ids"].join(" → ")) if len(check["item_ids"]) > 0 else ""}</small></li> for (index, check) in enumerate(option["checks"]) if check["status"] != "pass"]}</ul>
                    ) if diagnostics else None}
                    <details><summary>Proposed itinerary</summary><ol className="validation-timeline">{[<li key={item["id"]}>
                        <strong>{item["title"]}</strong><span>{item["start"]["local"] + " → " + item["end"]["local"]}</span>
                        <small>{item["start"]["zone"] + (" · fixed" if item["fixed"] else "") + (" · completed" if item["completed"] else "")}</small>
                    </li> for item in option["proposed_items"]]}</ol></details>
                    {(<details><summary>{"All checks (" + str(len(option["checks"])) + ")"}</summary>
                        <ul>{[<li key={str(index)}>{check["status"] + " · " + check["message"]}</li> for (index, check) in enumerate(option["checks"])]}</ul></details>
                    ) if diagnostics else None}
                    {(<small className="validation-evidence">Checked: {option["checked_at"]}<br/>Evidence expires: {option["evidence_expires_at"] or "No current evidence"}<br/>
                        Checks valid until: {option["valid_until"] or "No passing validation"}<br/>
                        Source: {option["source"] or "Unavailable"}</small>) if diagnostics else None}
                </article> for option in result["results"]]}</div>
            </div>) if result else None}
            {(<section className="validation-history" aria-label="Backup refresh history">
                <h3>Refresh history</h3><p>Recorded outcomes describe what was checked at that time. They are not current approval.</p>
                {(<p>No saved refreshes yet.</p>) if history and len(history["entries"]) == 0 else None}
                {(<p className="muted">{"Showing " + str(len(history["entries"])) + " of " + str(history["total"]) + " saved observations (newest first)."}</p>) if history and history["total"] > 0 else None}
                {[<details className="validation-history-entry" key={str(record["revision"])}>
                    <summary>{"Refresh #" + str(record["revision"]) + " · " + inventoryLabel(record["context"]["inventory_change"]) + " · " + historicalState(record)}</summary>
                    <p>{"Recorded: " + record["checked_at"] + " · Evidence deadline: " + record["expires_at"]}</p>
                    <p>{"Item date: " + record["context"]["sample_date"] + " · Profile: " + record["context"]["profile_name"] + " · Budget " + record["context"].get("currency", "USD") + " " + (record["context"]["budget"] or "unknown")}</p>
                    {(<p>{"Searched inventory IDs: " + (record["pipeline"]["provider_ids"].join(", ") or "None")}</p>) if record.get("pipeline") else None}
                    {(<details><summary>Recorded selection decisions</summary>
                        <p>{record["selection"]["message"]}</p>
                        <ul>{[<li key={d["provider_id"]}>{d["provider_id"] + " · " + d["reason"] + " · " + label(d["status"])}</li> for d in record["selection"]["decisions"]]}</ul>
                    </details>) if record.get("selection") else None}
                    <ul>{[<li key={option["candidate_id"]}>
                        <strong>{option["title"]}</strong><p>{"Outcome when recorded: " + label(option["status"]) + " · Recorded total: " + money(option["cost_minor"])}</p>
                        <p>{"Source: " + (option["source"] or "Provider unavailable; previous evidence discarded")}</p>
                        {(<BackupChanges changes={option["changes"]} historical={True} diagnostics={True}/>) if option.get("changes") else (<p>Change metrics were not recorded in this older observation.</p>)}
                        <ul>{[<li key={str(i)}>{check["message"]}</li> for (i, check) in enumerate(option["checks"])]}</ul>
                    </li> for option in record["recorded_options"]]}</ul>
                </details> for record in (history["entries"] if history else [])]}
            </section>) if diagnostics else None}
        </div>
    </details>;
}
