"""Disruption simulation and review of combined mock backup plans."""
import from workspace { workspaceKey }
import from server.main { replan_state, replan_save_rules, replan_save_dependency,
    propose_replan, review_replan, combine_replan }

def:pub ReplanPanel(trip_id: str, currency: str, onApplied: any) -> JsxElement {
    has state: dict[str, any] = {"items": [], "dependencies": []},
        result: dict[str, any] = {"proposals": [], "warnings": [], "affected": [], "backups": []},
        choices: dict[str, str] = {},
        item_id: str = "", kind: str = "delayed", delay: str = "180", use_ai: bool = False,
        busy: bool = False, error: str = "", message: str = "",
        rule_id: str = "", duration: str = "60", latest: str = "", fixed: bool = False,
        prerequisite: str = "", dependent: str = "", buffer: str = "30";
    def amount(cents: int) -> str {
        return currency + " " + str(cents // 100) + "." + ("0" if cents % 100 < 10 else "") + str(cents % 100);
    }
    def titleFor(id: str) -> str {
        matches = [i for i in state["items"] if i["id"] == id];
        return matches[0]["title"] if len(matches) > 0 else "Removed item";
    }
    def chooseBackup(id: str, value: str) -> None {
        browser: any = window;
        updated = browser.Object.assign({}, choices); updated[id] = value; choices = updated;
    }
    def loadRule(id: str) -> None {
        rule_id = id;
        matches = [i for i in state["items"] if i["id"] == id];
        if len(matches) > 0 {
            duration = str(matches[0]["duration_minutes"]);
            latest = matches[0]["latest_start"]; fixed = bool(matches[0]["fixed"]);
        }
    }
    async def reload -> None {
        state = await replan_state(workspace_key=await workspaceKey(), trip_id=trip_id);
        available = [i for i in state["items"] if i["category"] in ["transport", "stay", "food", "activity"]];
        if len(available) > 0 and not item_id { item_id = available[0]["id"]; }
        if len(available) > 0 and not rule_id { loadRule(available[0]["id"]); }
    }
    async def generate(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; error = ""; message = "";
        result = {"proposals": [], "warnings": [], "affected": [], "backups": []};
        try {
            result = await propose_replan(workspace_key=await workspaceKey(), trip_id=trip_id, item_id=item_id, kind=kind,
                delay_minutes=int(delay) if kind == "delayed" else 0, use_llm=use_ai);
            choices = {};
            if len(result["proposals"]) > 0 {
                for change in result["proposals"][0]["changes"] {
                    if change["backup_id"] { choices[change["item_id"]] = change["backup_id"]; }
                }
            }
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def combine(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; error = ""; message = "";
        try {
            result = await combine_replan(workspace_key=await workspaceKey(), trip_id=trip_id, event_id=result["event_id"], choices=choices);
            message = "Your backup combination is ready to review.";
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def review(id: str, accept: bool) -> None {
        if busy { return; } busy = True; error = "";
        try {
            response = await review_replan(workspace_key=await workspaceKey(), trip_id=trip_id, proposal_id=id, accept=accept);
            message = response["message"];
            if accept {
                result = {"proposals": [], "warnings": [], "affected": [], "backups": []};
                await reload(); await onApplied(); loadRule(rule_id);
            } else {
                result = {**result, "proposals": [p for p in result["proposals"] if p["id"] != id]};
            }
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def rules(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; error = "";
        try {
            state = await replan_save_rules(workspace_key=await workspaceKey(), trip_id=trip_id, item_id=rule_id,
                duration_minutes=int(duration), latest_start=latest, fixed=fixed);
            result = {"proposals": [], "warnings": [], "affected": [], "backups": []};
            message = "Schedule rules saved. Generate new options to use them.";
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def dependency(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; error = "";
        try {
            state = await replan_save_dependency(workspace_key=await workspaceKey(), trip_id=trip_id, prerequisite_id=prerequisite,
                dependent_id=dependent, buffer_minutes=int(buffer));
            result = {"proposals": [], "warnings": [], "affected": [], "backups": []};
            message = "Items linked. Generate new options to use the link.";
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def removeDependency(source: str, target: str) -> None {
        if busy { return; } busy = True; error = "";
        try {
            state = await replan_save_dependency(workspace_key=await workspaceKey(), trip_id=trip_id, prerequisite_id=source,
                dependent_id=target, remove=True);
            result = {"proposals": [], "warnings": [], "affected": [], "backups": []};
            message = "Link removed.";
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async can with entry {
        try { await reload(); } except Exception as exc { error = str(exc); }
    }
    available = [i for i in state["items"] if i["category"] in ["transport", "stay", "food", "activity"]];
    <section className="replan-workspace">
        <div className="card replan-intro"><h2>Replan your trip</h2>
            <p>Pick a delayed or canceled item to get revised plans. Review what changes, then accept one.</p>
            <p className="mock-badge">SIMULATION · No real bookings or cancellations</p>
            <p className="section-caption">Plans are checked for timing, linked items, fixed items and budget. They are not checked for traveler requirements or booking policies. Times are local to the destination.</p>
        </div>
        {(<div className="alert error" role="alert">{error}</div>) if error else None}
        {(<div className="alert success" role="status">{message}</div>) if message else None}
        {(<div className="card empty-state"><h3>No itinerary items yet</h3><p>Add a dated activity, meal, stay or transport item in Itinerary. Or try the flight-delay walkthrough in the sidebar.</p></div>) if len(available) == 0 else None}
        <div className="replan-disruption">
            <section className="card"><p className="eyebrow">STEP 1</p><h3>Report a disruption</h3>
                <form onSubmit={generate}>
                    <label htmlFor="disrupted-item">Affected item</label><select id="disrupted-item" value={item_id} onChange={lambda (e: ChangeEvent) { item_id = e.target.value; }}>
                        {[<option key={i["id"]} value={i["id"]}>{i["title"] + " · " + i["date"] + " " + i["time"]}</option> for i in available]}
                    </select>
                    <label htmlFor="disruption-type">What happened?</label><select id="disruption-type" value={kind} onChange={lambda (e: ChangeEvent) { kind = e.target.value; }}><option value="delayed">Delayed</option><option value="interrupted">Interrupted / canceled</option></select>
                    {(<div><label htmlFor="delay-minutes">Delay in minutes</label><input id="delay-minutes" type="number" min="1" max="1440" required={True} value={delay} onChange={lambda (e: ChangeEvent) { delay = e.target.value; }}/></div>) if kind == "delayed" else None}
                    <label className="replan-check"><input type="checkbox" checked={use_ai} onChange={lambda (e: ChangeEvent) { use_ai = e.target.checked; }}/>Let AI choose which backups to combine</label>
                    <button className="primary" type="submit" disabled={busy or not item_id}>{"Combining backups…" if busy else "Generate replan options ↗"}</button>
                </form>
            </section>
        </div>
        <details className="card replan-settings">
            <summary>Schedule rules and linked items</summary>
            <p className="section-caption">Set these before generating options. Saving a change clears the current options.</p>
            <div className="replan-setup">
            <section><h3>Schedule rules</h3><p className="section-caption">Set how long an item takes, its latest start time, and whether it must stay as is.</p>
                <form onSubmit={rules}>
                    <label htmlFor="rule-item">Item</label><select id="rule-item" value={rule_id} onChange={lambda (e: ChangeEvent) { loadRule(e.target.value); }}>{[<option key={i["id"]} value={i["id"]}>{i["title"]}</option> for i in available]}</select>
                    <label htmlFor="rule-duration">Duration in minutes</label><input id="rule-duration" type="number" min="1" max="1440" required={True} value={duration} onChange={lambda (e: ChangeEvent) { duration = e.target.value; }}/>
                    <label htmlFor="rule-latest">Latest start (optional)</label><input id="rule-latest" type="datetime-local" value={latest} onChange={lambda (e: ChangeEvent) { latest = e.target.value; }}/>
                    <label className="replan-check"><input type="checkbox" checked={fixed} onChange={lambda (e: ChangeEvent) { fixed = e.target.checked; }}/>Keep this arrangement fixed</label>
                    <button type="submit" className="secondary" disabled={busy or not rule_id}>Save schedule rules</button>
                </form>
            </section>
            <section><h3>Link items</h3><p className="section-caption">The second item can start only after the first ends plus the buffer.</p>
                <form onSubmit={dependency}>
                    <label htmlFor="dependency-source">First item</label><select id="dependency-source" value={prerequisite} required={True} onChange={lambda (e: ChangeEvent) { prerequisite = e.target.value; }}><option value="">Choose an item</option>{[<option key={i["id"]} value={i["id"]}>{i["title"]}</option> for i in available]}</select>
                    <label htmlFor="dependency-target">Second item</label><select id="dependency-target" value={dependent} required={True} onChange={lambda (e: ChangeEvent) { dependent = e.target.value; }}><option value="">Choose an item</option>{[<option key={i["id"]} value={i["id"]}>{i["title"]}</option> for i in available]}</select>
                    <label htmlFor="dependency-buffer">Buffer between them (minutes)</label><input id="dependency-buffer" type="number" min="0" max="1440" required={True} value={buffer} onChange={lambda (e: ChangeEvent) { buffer = e.target.value; }}/>
                    <button type="submit" className="secondary" disabled={busy}>Link items</button>
                </form>
            </section>
        </div>
        {(<section className="card"><h3>Linked items</h3><ul className="dependency-list">{[<li key={edge["prerequisite_id"] + edge["dependent_id"]}>{titleFor(edge["prerequisite_id"]) + " → " + titleFor(edge["dependent_id"]) + " · " + str(edge["buffer_minutes"]) + " min buffer"}<button type="button" className="text-button delete" disabled={busy} onClick={lambda { removeDependency(edge["prerequisite_id"], edge["dependent_id"]); }}>Remove</button></li> for edge in state["dependencies"]]}</ul></section>) if len(state["dependencies"]) > 0 else None}
        </details>
        {(<section className="card"><h3>Items checked</h3><p>{", ".join([i["title"] for i in result["affected"]])}</p></section>) if len(result["affected"]) > 0 else None}
        {[<div className="alert error" role="status" key={warning}>{warning}</div> for warning in result["warnings"]]}
        {(<div className="replan-results-heading"><p className="eyebrow">STEP 2</p><h2>Compare revised plans</h2><p>Your itinerary changes only when you accept a plan.</p></div>) if len(result["proposals"]) > 0 else None}
        <div className="replan-proposals">{[
            <article className="card proposal-card" key={p["id"]}><p className="eyebrow">{p["mode"] + " · MOCK BACKUP COMBINATION"}</p><h3>{p["title"]}</h3>
                <div className="proposal-metrics"><p><small>Projected trip cost</small><strong>{amount(p["projected_total_cents"])}</strong></p><p><small>New replacement purchases</small><strong>{amount(p["replacement_cash_cents"])}</strong></p><p><small>Prior paid costs retained</small><strong>{amount(p["retained_paid_cents"])}</strong></p></div>
                <p className="section-caption">{p["refund_note"]}</p>
                <ul className="proposal-changes">{[<li key={change["item_id"]}><strong>{change["before"]["title"] + " → " + change["after"]["title"]}</strong><span>{change["before"]["date"] + " " + change["before"]["time"] + " → " + change["after"]["date"] + " " + change["after"]["time"]}</span><small>{change["reason"]}</small></li> for change in p["changes"]]}</ul>
                {(<p>{p["explanation"]}</p>) if p["explanation"] else None}
                <p className="section-caption">{p["validation"]}</p><div className="proposal-actions"><button type="button" className="primary" disabled={busy} onClick={lambda { review(p["id"], True); }}>Accept revised plan</button><button type="button" className="text-button" disabled={busy} onClick={lambda { review(p["id"], False); }}>Reject</button></div>
            </article> for p in result["proposals"]
        ]}</div>
        {(<details className="card replan-inventory"><summary>View available mock backups</summary><p className="section-caption">Simulated options that can replace affected items. To choose your own, use Build your own combination.</p><div className="backup-grid">{[<div className="backup-chip" key={b["id"]}><strong>{b["title"]}</strong><small>{"For " + titleFor(b["item_id"])}</small><span>{amount(b["cost_cents"]) + " · " + str(b["duration_minutes"]) + " min"}</span></div> for b in result["backups"]]}</div></details>) if len(result["backups"]) > 0 else None}
        {(<section className="card"><p className="eyebrow">OPTIONAL</p><h3>Build your own combination</h3><p className="section-caption">Pick a backup for any affected item. Items that can no longer happen in time need one.</p>
            <form onSubmit={combine}><div className="backup-grid">{[<div key={i["id"]}><label htmlFor={"choice-" + i["id"]}>{i["title"]}</label><select id={"choice-" + i["id"]} value={choices.get(i["id"], "")} disabled={bool(i["protected"])} onChange={lambda (e: ChangeEvent) { chooseBackup(i["id"], e.target.value); }}><option value="">Keep original if feasible</option>{[<option key={b["id"]} value={b["id"]}>{b["title"] + " · " + amount(b["cost_cents"])}</option> for b in result["backups"] if b["item_id"] == i["id"]]}</select></div> for i in result["affected"]]}</div><button type="submit" className="secondary" disabled={busy}>Combine selected backups</button></form>
        </section>) if len(result["affected"]) > 0 and len(result["backups"]) > 0 else None}
        {(<p className="section-caption">No workable plan found. Check the conflicts above or adjust the schedule rules.</p>) if len(result["affected"]) > 0 and len(result["proposals"]) == 0 and len(result["warnings"]) > 0 else None}
    </section>
}
