"""Independent synthetic full-trip demo using Roam's existing controls and styles."""
import from server.main { load_backup_history, save_backup_refresh }

def:pub ValidationLab -> JsxElement {
    has scenario: str = "rain", profile: str = "family", budget: str = "600",
        pending: bool = False, failure: str = "", result: dict[str, any] | None = None,
        expired: bool = False, timer: Ref[int] = Ref(0), requestRef: Ref[int] = Ref(0),
        inventory: str = "unchanged", sampleDate: str = "", booting: bool = True,
        history: dict[str, any] | None = None, revision: int = 0, notice: str = "",
        sessionId: Ref[str] = Ref(""), retryId: Ref[str] = Ref(""),
        historyClock: float = 0, historyTimer: Ref[int] = Ref(0), syncListener: Ref[any] = Ref(None),
        syncQueued: Ref[bool] = Ref(False);

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
                saved = browser.localStorage.getItem("roam.backup.sample-session.v1");
                valid = saved and browser.RegExp("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$").test(saved);
                sessionId.current = saved if valid else browser.crypto.randomUUID();
                browser.localStorage.setItem("roam.backup.sample-session.v1", sessionId.current);
            } except Exception {
                sessionId.current = browser.crypto.randomUUID();
                notice = "Browser storage is unavailable. This session cannot be restored after closing the page.";
            }
            restored = await load_backup_history(session_id=str(sessionId.current or ""));
            if request != requestRef.current { return; }
            history = restored; revision = restored["revision"];
            context = restored["context"];
            scenario = context["scenario"]; profile = context["profile_name"];
            budget = context["budget"]; inventory = context["inventory_change"]; sampleDate = context["sample_date"];
            if revision > 0 { notice = "Saved history restored. Refresh to obtain a current result; historical checks are not current approval."; }
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
    def inputChanged -> None { clear(); retryId.current = ""; notice = "Inputs changed. Refresh before using any previous conclusion."; }
    async def reconcile -> None {
        if booting or pending { syncQueued.current = True; return; }
        if history is None { return; }
        syncQueued.current = False;
        request = requestRef.current;
        try {
            latest = await load_backup_history(session_id=str(sessionId.current or ""));
            if request != requestRef.current { return; }
            reasons = latest["entries"][0]["reasons"] if len(latest["entries"]) > 0 else [];
            invalidated = "version_changed" in reasons or "clock_invalid" in reasons or "evidence_expired" in reasons;
            if latest["revision"] != revision or invalidated {
                clear(); retryId.current = ""; revision = latest["revision"];
                notice = "Saved evidence changed or expired. Previous results cleared; refresh with your selected inputs." if invalidated else
                    "Another refresh was saved in this session. Previous results cleared; refresh with your selected inputs.";
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
            response = await save_backup_refresh(session_id=str(sessionId.current or ""), request_id=str(retryId.current or ""),
                expected_revision=revision, scenario=scenario, profile_name=profile,
                budget=budget, inventory_change=inventory, sample_date=sampleDate);
            if request != requestRef.current { return; }
            retryId.current = ""; history = response["history"]; revision = history["revision"];
            nextResult = response["report"];
            if response["outcome"] == "conflict" {
                notice = "Another refresh was saved in this session. History reloaded; refresh again with your selected inputs.";
            } elif nextResult is None {
                notice = "The saved response is no longer current. Its history is preserved; refresh again.";
            } elif Date.parse(nextResult["expires_at"]) <= Date.now() { expired = True; }
            else {
                result = nextResult; budget = history["context"]["budget"];
                notice = "Saved refresh #" + str(response["revision"]) + ".";
            }
            try { browser.localStorage.setItem("roam.backup.refresh-notice.v1", str(sessionId.current) + ":" + str(revision)); }
            except Exception { notice = notice + " Other tabs will recheck history when focused."; }
        }
        except Exception {
            if request == requestRef.current {
                failure = "Could not refresh and save. Check the budget (nonnegative USD, up to two decimal places and 100,000,000) and retry. Previous results have been cleared; a retry will not duplicate a saved request.";
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
        if status == "passed_fixture_checks" { return "Fixture checks passed"; }
        if status == "invalid" { return "Does not meet requirements"; }
        return "Needs more evidence";
    }
    def historicalState(record: dict[str, any]) -> str {
        context = record["context"];
        reasons: list[str] = [];
        if context["scenario"] != scenario or context["profile_name"] != profile or context["budget"] != budget or context["inventory_change"] != inventory or context["sample_date"] != sampleDate {
            reasons.append("Inputs changed");
        }
        if "version_changed" in record["reasons"] or "clock_invalid" in record["reasons"] { reasons.append("Requires new checks"); }
        if Date.parse(record["expires_at"]) <= Date.now() { reasons.append("Evidence expired"); }
        if record["revision"] != revision { reasons.append("Superseded"); }
        return (" · ".join(reasons) if len(reasons) > 0 else "Latest saved observation") + " · history only";
    }
    def inventoryLabel(value: str) -> str {
        labels = {"unchanged": "Original inventory", "price_increase": "Plan B price increased",
            "sold_out": "Plan B sold out", "all_sold_out": "Both sold out",
            "expired_evidence": "Plan B evidence expired", "provider_failure": "Both providers failed",
            "partial_failure": "Plan B provider failed"};
        return labels.get(value, "Inventory observation");
    }
    return <details className="card validation-lab">
        <summary><span>Explore validation with a sample trip</span></summary>
        <div className="validation-content">
            <p>Explore whole-trip checks using a Boston sample itinerary. This sample is separate from your saved trips.
                All venues, availability, prices and policies are synthetic. Passing these checks is not a booking or a shared-validator approval. Each refresh checks a new synthetic inventory observation for the same sample date.</p>
            <p className="muted">Refreshes are saved in a separate sample history. Reopening restores the controls and recorded observations; click refresh for a current result. No saved trip is changed.</p>
            {(<p role="status">Loading saved backup history…</p>) if booting else None}
            {(<button type="button" className="secondary" onClick={initialize}>Retry loading history</button>) if not booting and history is None else None}
            {(<p role="status">{notice}</p>) if notice else None}
            <div className="validation-controls">
                <div><label htmlFor="validation-scenario">Sample scenario</label>
                    <select id="validation-scenario" value={scenario} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { scenario = e.target.value; inputChanged(); }}>
                        <option value="rain">Rain · indoor alternatives</option>
                        <option value="arrival_delay">Delayed arrival · later dinner</option>
                        <option value="missing_evidence">Missing price and policy evidence</option>
                        <option value="eligibility_conflict">Pet, child and accessibility conflict</option>
                        <option value="schedule_conflict">Overlapping event and short transfer</option>
                        <option value="fixed_item">Protected original item</option>
                        <option value="stale_evidence">Expired candidate evidence</option>
                    </select></div>
                <div><label htmlFor="validation-profile">Traveler requirements</label>
                    <select id="validation-profile" value={profile} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { profile = e.target.value; inputChanged(); }}>
                        <option value="family">Family · vegetarian, dog, wheelchair</option>
                        <option value="solo">Solo adult · no additional requirements</option>
                    </select></div>
                <div><label htmlFor="validation-budget">Whole-trip budget (USD)</label>
                    <input id="validation-budget" inputMode="decimal" value={budget} placeholder="Empty means unknown" maxLength={24} disabled={pending or booting}
                        onChange={lambda (e: ChangeEvent) { budget = e.target.value; inputChanged(); }}/></div>
                <div><label htmlFor="validation-date">Sample trip date</label>
                    <input id="validation-date" type="date" value={sampleDate} disabled={pending or booting}
                        onChange={lambda (e: ChangeEvent) { sampleDate = e.target.value; inputChanged(); }}/></div>
            </div>
            <div className="validation-refresh-control"><label htmlFor="validation-inventory">Inventory on next refresh</label>
                <select id="validation-inventory" value={inventory} disabled={pending or booting} onChange={lambda (e: ChangeEvent) { inventory = e.target.value; inputChanged(); }}>
                    <option value="unchanged">Fresh inventory · original sample prices</option>
                    <option value="price_increase">Plan B price rises by USD 200 for the whole party</option>
                    <option value="sold_out">Plan B sold out</option>
                    <option value="all_sold_out">Both alternatives sold out</option>
                    <option value="expired_evidence">Plan B provider returns expired evidence</option>
                    <option value="provider_failure">Both providers fail</option>
                    <option value="partial_failure">Plan B provider fails · Plan C responds</option>
                </select>
                <p className="muted">Each selection is a separate inventory snapshot; price changes do not accumulate. Refresh replaces all previous conclusions.</p>
            </div>
            <button type="button" className="primary" disabled={pending or booting or history is None} onClick={run}>{"Refreshing and saving checks…" if pending else "Refresh and recheck Plan B / C"}</button>
            {(<p role="status">These checks have expired. Refresh to obtain new evidence; previous results are no longer shown.</p>) if expired else None}
            {(<p className="alert error" role="alert">{failure}</p>) if failure else None}
            {(<div className="validation-results" aria-live="polite">
                <p role="status">{result["message"]}</p>
                <p><strong>{result["profile_summary"]}</strong><br/>Sample date: {result["trip_date"]} · America/New_York</p>
                <p>{str(result["summary"]["passed_fixture_checks"]) + " passed · " + str(result["summary"]["invalid"]) + " rejected · " + str(result["summary"]["needs_validation"]) + " awaiting evidence"}</p>
                <div className="backup-options">{[<article className="backup-option validation-option" key={option["candidate_id"]}>
                    <p className="eyebrow">{option["candidate_id"]}</p><h3>{option["title"]}</h3>
                    {(<p className="validation-provider-error">Provider unavailable. Prior evidence discarded.</p>) if option["refresh_state"] == "provider_error" else None}
                    <p className="validation-status" data-status={option["status"]}>{label(option["status"])}</p>
                    <dl className="validation-costs">
                        <div><dt>Proposed whole-trip cost</dt><dd>{money(option["cost"]["projected_total_minor"])}</dd></div>
                        <div><dt>Original payment retained</dt><dd>{money(option["cost"]["retained_original_payment_minor"])}</dd></div>
                        <div><dt>Reserve included</dt><dd>{money(option["cost"]["reserve_minor"])}</dd></div>
                        <div><dt>Budget</dt><dd>{money(option["cost"]["budget_minor"])}</dd></div>
                    </dl>
                    <p className="muted">No refund assumed. Quotes cover the whole party and include fees.</p>
                    <ul className="validation-reasons">{[<li key={str(index)}><strong>{"Failed" if check["status"] == "fail" else "Unknown"}: </strong>{check["message"]}
                        <small>{(" · " + check["item_ids"].join(" → ")) if len(check["item_ids"]) > 0 else ""}</small></li> for (index, check) in enumerate(option["checks"]) if check["status"] != "pass"]}</ul>
                    <details><summary>Full proposed itinerary</summary><ol className="validation-timeline">{[<li key={item["id"]}>
                        <strong>{item["title"]}</strong><span>{item["start"]["local"] + " → " + item["end"]["local"]}</span>
                        <small>{item["start"]["zone"] + (" · fixed" if item["fixed"] else "") + (" · completed" if item["completed"] else "")}</small>
                    </li> for item in option["proposed_items"]]}</ol></details>
                    <details><summary>{"All checks (" + str(len(option["checks"])) + ")"}</summary>
                        <ul>{[<li key={str(index)}>{check["status"] + " · " + check["message"]}</li> for (index, check) in enumerate(option["checks"])]}</ul></details>
                    <small className="validation-evidence">Checked: {option["checked_at"]}<br/>Evidence expires: {option["evidence_expires_at"] or "No current evidence"}<br/>
                        Checks valid until: {option["valid_until"] or "No passing validation"}<br/>
                        Source: {option["source"] or "Unavailable"}</small>
                </article> for option in result["results"]]}</div>
            </div>) if result else None}
            <section className="validation-history" aria-label="Backup refresh history">
                <h3>Refresh history</h3><p>Recorded outcomes describe what was checked at that time. They are not current approval.</p>
                {(<p>No saved refreshes yet.</p>) if history and len(history["entries"]) == 0 else None}
                {(<p className="muted">{"Showing " + str(len(history["entries"])) + " of " + str(history["total"]) + " saved observations (newest first)."}</p>) if history and history["total"] > 0 else None}
                {[<details className="validation-history-entry" key={str(record["revision"])}>
                    <summary>{"Refresh #" + str(record["revision"]) + " · " + inventoryLabel(record["context"]["inventory_change"]) + " · " + historicalState(record)}</summary>
                    <p>{"Recorded: " + record["checked_at"] + " · Evidence deadline: " + record["expires_at"]}</p>
                    <p>{"Sample date: " + record["context"]["sample_date"] + " · Profile: " + record["context"]["profile_name"] + " · Budget USD " + (record["context"]["budget"] or "unknown")}</p>
                    <ul>{[<li key={option["candidate_id"]}>
                        <strong>{option["title"]}</strong><p>{"Outcome when recorded: " + label(option["status"]) + " · Recorded total: " + money(option["cost_minor"])}</p>
                        <p>{"Source: " + (option["source"] or "Provider unavailable; previous evidence discarded")}</p>
                        <ul>{[<li key={str(i)}>{check["message"]}</li> for (i, check) in enumerate(option["checks"])]}</ul>
                    </li> for option in record["recorded_options"]]}</ul>
                </details> for record in (history["entries"] if history else [])]}
            </section>
        </div>
    </details>;
}
