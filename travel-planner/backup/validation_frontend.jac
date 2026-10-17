"""Independent synthetic full-trip demo using Roam's existing controls and styles."""
import from server.main { preview_backup_validation }

def:pub ValidationLab -> JsxElement {
    has scenario: str = "rain", profile: str = "family", budget: str = "600",
        pending: bool = False, failure: str = "", result: dict[str, any] | None = None,
        expired: bool = False, timer: Ref[int] = Ref(0);

    can with [result] entry {
        if timer.current { window.clearTimeout(timer.current); timer.current = 0; }
        if result {
            timer.current = window.setTimeout(lambda { result = None; expired = True; },
                max(0.0, Date.parse(result["expires_at"]) - Date.now()));
        }
    }
    can with exit { if timer.current { window.clearTimeout(timer.current); } }
    def clear -> None { result = None; failure = ""; expired = False; }
    async def run -> None {
        if pending { return; }
        clear(); pending = True;
        try { result = await preview_backup_validation(scenario=scenario, profile_name=profile, budget=budget); }
        except Exception as exc { failure = str(exc); }
        finally { pending = False; }
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
    return <details className="card validation-lab">
        <summary><span>Plan B / C · Validation lab</span><small>Independent synthetic demo · Gehao Dong</small></summary>
        <div className="validation-content">
            <p>Explore whole-trip checks using a Boston sample itinerary. This sample is separate from your saved trips.
                All venues, availability, prices and policies are synthetic. Passing these checks is not a booking or a shared-validator approval.</p>
            <div className="validation-controls">
                <div><label htmlFor="validation-scenario">Sample scenario</label>
                    <select id="validation-scenario" value={scenario} disabled={pending} onChange={lambda (e: ChangeEvent) { scenario = e.target.value; clear(); }}>
                        <option value="rain">Rain · indoor alternatives</option>
                        <option value="arrival_delay">Delayed arrival · later dinner</option>
                        <option value="missing_evidence">Missing price and policy evidence</option>
                        <option value="eligibility_conflict">Pet, child and accessibility conflict</option>
                        <option value="schedule_conflict">Overlapping event and short transfer</option>
                        <option value="fixed_item">Protected original item</option>
                        <option value="stale_evidence">Expired candidate evidence</option>
                    </select></div>
                <div><label htmlFor="validation-profile">Traveler requirements</label>
                    <select id="validation-profile" value={profile} disabled={pending} onChange={lambda (e: ChangeEvent) { profile = e.target.value; clear(); }}>
                        <option value="family">Family · vegetarian, dog, wheelchair</option>
                        <option value="solo">Solo adult · no additional requirements</option>
                    </select></div>
                <div><label htmlFor="validation-budget">Whole-trip budget (USD)</label>
                    <input id="validation-budget" inputMode="decimal" value={budget} placeholder="Empty means unknown" maxLength={24} disabled={pending}
                        onChange={lambda (e: ChangeEvent) { budget = e.target.value; clear(); }}/></div>
            </div>
            <button type="button" className="primary" disabled={pending} onClick={run}>{"Checking the full itinerary…" if pending else "Run sample checks"}</button>
            {(<p role="status">Evidence has expired. Run the sample again to refresh its checks.</p>) if expired else None}
            {(<p className="alert error" role="alert">{failure}</p>) if failure else None}
            {(<div className="validation-results" aria-live="polite">
                <p><strong>{result["profile_summary"]}</strong><br/>Sample date: {result["trip_date"]} · America/New_York</p>
                <p>{str(result["summary"]["passed_fixture_checks"]) + " passed · " + str(result["summary"]["invalid"]) + " rejected · " + str(result["summary"]["needs_validation"]) + " awaiting evidence"}</p>
                <div className="backup-options">{[<article className="backup-option validation-option" key={option["candidate_id"]}>
                    <p className="eyebrow">{option["candidate_id"]}</p><h3>{option["title"]}</h3>
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
                    <small className="validation-evidence">Checked: {option["checked_at"]}<br/>Refresh by: {result["expires_at"]}</small>
                </article> for option in result["results"]]}</div>
            </div>) if result else None}
        </div>
    </details>;
}
