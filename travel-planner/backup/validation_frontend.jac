"""Independent synthetic full-trip demo using Roam's existing controls and styles."""
import from server.main { refresh_backup_validation }

def:pub ValidationLab -> JsxElement {
    has scenario: str = "rain", profile: str = "family", budget: str = "600",
        pending: bool = False, failure: str = "", result: dict[str, any] | None = None,
        expired: bool = False, timer: Ref[int] = Ref(0), requestRef: Ref[int] = Ref(0),
        inventory: str = "unchanged", sampleDate: str = "";

    can with [result] entry {
        if timer.current { window.clearTimeout(timer.current); timer.current = 0; }
        if result {
            timer.current = window.setTimeout(lambda { result = None; expired = True; },
                max(0.0, Date.parse(result["expires_at"]) - Date.now()));
        }
    }
    can with exit { requestRef.current += 1; if timer.current { window.clearTimeout(timer.current); } }
    def clear -> None {
        requestRef.current += 1;
        if timer.current { window.clearTimeout(timer.current); timer.current = 0; }
        result = None; failure = ""; expired = False;
    }
    async def run -> None {
        if pending { return; }
        clear(); pending = True;
        request = requestRef.current;
        try {
            nextResult = await refresh_backup_validation(scenario=scenario, profile_name=profile,
                budget=budget, inventory_change=inventory, sample_date=sampleDate);
            if request != requestRef.current { return; }
            sampleDate = nextResult["trip_date"];
            if Date.parse(nextResult["expires_at"]) <= Date.now() { expired = True; }
            else { result = nextResult; }
        }
        except Exception {
            if request == requestRef.current {
                failure = "Refresh failed. Check the budget (nonnegative USD, up to two decimal places and 100,000,000) and try again. Previous results have been cleared.";
            }
        }
        finally { if request == requestRef.current { pending = False; } }
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
        <summary><span>Explore validation with a sample trip</span></summary>
        <div className="validation-content">
            <p>Explore whole-trip checks using a Boston sample itinerary. This sample is separate from your saved trips.
                All venues, availability, prices and policies are synthetic. Passing these checks is not a booking or a shared-validator approval. Each refresh checks a new synthetic inventory observation for the same sample date.</p>
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
            <div className="validation-refresh-control"><label htmlFor="validation-inventory">Inventory on next refresh</label>
                <select id="validation-inventory" value={inventory} disabled={pending} onChange={lambda (e: ChangeEvent) { inventory = e.target.value; clear(); }}>
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
            <button type="button" className="primary" disabled={pending} onClick={run}>{"Refreshing evidence and checking the itinerary…" if pending else "Refresh and recheck Plan B / C"}</button>
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
        </div>
    </details>;
}
