"""Risk selection, traveler facts, plan comparison and explicit P4 review in Roam."""
import from server.main { ItemView, planning_state, save_planning_context, generate_backup_plans, review_backup_plan }

def:pub PlanningPanel(trip_id: str, items: list[ItemView], onGenerated: any = None, onApplied: any = None) -> JsxElement {
    browser: any = window;
    has state: dict[str, any] | None = None, result: dict[str, any] | None = None,
        busy: bool = False, loading: bool = True, failure: str = "", notice: str = "",
        adults: str = "", children: str = "", pets: str = "", dietary: str = "", wheelchair: bool = False,
        zone: str = "", reserve: str = "0", details: dict[str, any] = {}, routes: dict[str, str] = {},
        confirmed: dict[str, bool] = {}, selectedRisks: list[str] = [], reason: str = "detected", target: str = "", notBefore: str = "",
        useAI: bool = False, limit: str = "4", sequence: Ref[int] = Ref(0), expiryTimer: Ref[int] = Ref(0), listener: Ref[any] = Ref(None), alive: Ref[bool] = Ref(True), checkQueued: Ref[bool] = Ref(False);
    def split(value: str) -> list[str] { parts: any = value.split(","); return [s.trim() for s in parts if s.trim()]; }
    def joined(values: any) -> str { return values.join(", "); }
    def money(value: any) -> str {
        if value is None { return "Needs confirmation"; }
        return (state["ledger"]["currency"] if state else "USD") + " " + (value / 100).toFixed(2);
    }
    def costChange(value: any) -> str {
        if value is None { return "Needs confirmation"; }
        if value == 0 { return "No change"; }
        return money(abs(value)) + (" more" if value > 0 else " less");
    }
    def originalTime(id: str) -> str {
        matches = [i for i in (state.get("items", items) if state else items) if i.id == id];
        return matches[0].date + " " + matches[0].time if matches else "Needs confirmation";
    }
    def missingReasons(plan: dict[str, any]) -> list[str] {
        messages = {"eligibility": "A venue's support for traveler requirements needs confirmation.", "child_age": "Child admission ages need confirmation.",
            "profile": "Traveler requirements are incomplete.", "price": "A current whole-party quote is missing.", "party_quote": "Whole-party pricing including fees needs confirmation.",
            "schedule": "Start/end times or timezones need confirmation.", "transfer": "Travel time between places needs confirmation.", "transfer_evidence": "Current route evidence is missing.",
            "opening_hours": "Opening hours need confirmation.", "budget": "The whole-trip budget cannot yet be checked.", "risk_evidence": "The reported condition needs current evidence.",
            "risk_status": "The activation condition is not established.", "item_evidence": "Some itinerary facts need to be refreshed."};
        reasons: list[str] = [];
        for check in plan["validation"]["checks"] {
            if check["status"] != "unknown" { continue; }
            message = messages.get(check["code"], "Some supporting trip facts need confirmation.");
            if message not in reasons { reasons.append(message); }
        }
        return reasons[:3];
    }
    def label(value: str) -> str {
        labels = {"weather": "Weather", "timing": "Tight timing or delayed arrival", "long_drive": "Long drive",
            "opening_hours": "Opening hours", "booking_terms": "Booking terms", "closure": "Venue closure",
            "cancellation": "Cancellation", "traveler_change": "Traveler requirements changed", "budget_change": "Budget changed", "inventory_change": "Inventory changed"};
        return labels.get(value, value);
    }
    def title(id: str) -> str { matches = [i for i in (state.get("items", items) if state else items) if i.id == id]; return matches[0].title if matches else "Itinerary item"; }
    def petSize(species: str, profile: any) -> str {
        matches = [p for p in (profile["pets"] if profile else []) if p["species"] == species];
        return matches[0]["size"] if matches else "unknown";
    }
    def clear -> None { result = None; if expiryTimer.current { window.clearTimeout(expiryTimer.current); expiryTimer.current = 0; } }
    def fill(data: dict[str, any]) -> None {
        state = data; zone = data["facts"].get("zone", ""); reserve = str(data["facts"].get("reserve_minor", 0) / 100);
        profile = data["facts"].get("profile");
        if profile {
            adults = str(profile["adults"]); children = joined([str(age) for age in profile["child_ages"]]);
            pets = joined([pet["species"] for pet in profile["pets"]]);
            dietary = joined([r["code"] for r in profile["requirements"] if r["category"] == "dietary" and r["strength"] == "hard"]);
            wheelchair = any(r["category"] == "accessibility" and r["code"] == "wheelchair" and r["strength"] == "hard" for r in profile["requirements"]);
        } else { adults = ""; children = ""; pets = ""; dietary = ""; wheelchair = False; }
        details = browser.JSON.parse(browser.JSON.stringify(data["facts"].get("items", {}))); confirmed = {}; routes = {};
        for route in data["facts"].get("transfers", []) {
            routes[route["from_id"] + "|" + route["to_id"]] = str(route["minutes"]) if route["minutes"] is not None else "";
        }
        selectedRisks = [risk["id"] for risk in data["risks"] if risk["status"] == "flagged"];
    }
    async def reload -> None {
        sequence.current += 1; request = sequence.current; loading = True; clear();
        try { data = await planning_state(trip_id=trip_id); if request == sequence.current { fill(data); } }
        except Exception { if request == sequence.current { failure = "Could not load trip facts. Reload and try again."; } }
        finally { if request == sequence.current { loading = False; } }
    }
    can with entry {
        alive.current = True;
        reload();
        listener.current = lambda { checkVersion(); };
        window.addEventListener("focus", listener.current);
        window.addEventListener("storage", listener.current);
    }
    can with exit { alive.current = False; sequence.current += 1; clear(); window.removeEventListener("focus", listener.current); window.removeEventListener("storage", listener.current); }
    can with [result] entry {
        if expiryTimer.current { window.clearTimeout(expiryTimer.current); }
        if result and len(result["plans"]) > 0 {
            expiryTimer.current = window.setTimeout(lambda { clear(); notice = "These options have expired. Find fresh plans before choosing."; },
                max(0.0, min(Date.parse(plan["expires_at"]) for plan in result["plans"]) - Date.now()));
        }
    }
    async def checkVersion -> None {
        if not alive.current { return; }
        if busy or loading { checkQueued.current = True; return; }
        if state is None { return; }
        checkQueued.current = False;
        request = sequence.current;
        try {
            fresh = await planning_state(trip_id=trip_id);
            if request == sequence.current and fresh["trip_version"] != state["trip_version"] {
                clear(); fill(fresh); notice = "Your trip changed. Find fresh plans before choosing.";
            } elif request == sequence.current and result and any(fresh.get("review_statuses", {}).get(plan["id"]) != "proposed" or
                Date.parse(plan["expires_at"]) <= Date.parse(fresh["checked_at"]) for plan in result["plans"]) {
                clear(); notice = "These options were reviewed or have expired. Find fresh plans before choosing.";
            }
        } except Exception { clear(); failure = "Could not verify the latest trip. Reload before choosing a plan."; }
    }
    def notifyTabs -> None {
        try { browser.localStorage.setItem("roam.planning.changed", trip_id + ":" + str(Date.now())); }
        except Exception {}
    }
    def setFact(id: str, field: str, value: any) -> None {
        updated = browser.Object.assign({}, details[id] or {}); updated[field] = value;
        changedDetails = browser.Object.assign({}, details); changedDetails[id] = updated; details = changedDetails;
        changedConfirmations = browser.Object.assign({}, confirmed); changedConfirmations[id] = False; confirmed = changedConfirmations; clear();
    }
    def setEligibility(id: str, key: str, value: str) -> None {
        rules = browser.Object.assign({}, details[id]["eligibility"] if details[id] and details[id].get("eligibility") else {});
        rules[key] = True if value == "yes" else False if value == "no" else None;
        setFact(id, "eligibility", rules);
    }
    def setWindow(id: str, side: str, value: str) -> None {
        windows: any = browser.JSON.parse(browser.JSON.stringify(details[id]["hours"])) if details[id] and details[id].get("hours") else
            [{"start": {"local": "", "zone": zone}, "end": {"local": "", "zone": zone}}];
        windows[0][side] = {"local": value, "zone": zone}; setFact(id, "hours", windows);
    }
    def windowValue(id: str, side: str) -> str {
        return details[id]["hours"][0][side]["local"] if details[id] and details[id].get("hours") and len(details[id]["hours"]) > 0 else "";
    }
    def eligibilityValue(id: str, key: str) -> str {
        rules = details[id].get("eligibility", {}) if details[id] else {};
        return "yes" if rules.get(key) is True else "no" if rules.get(key) is False else "unknown";
    }
    def requirements -> list[dict[str, any]] {
        old = state["facts"].get("profile") if state else None;
        oldPets = [p["species"] for p in old["pets"]] if old else [];
        kept = [r for r in (old["requirements"] if old else []) if (r["strength"] == "soft" and not (r["category"] == "dietary" and r["code"] in split(dietary))) or r["category"] == "child" or
            (r["category"] == "accessibility" and r["code"] != "wheelchair") or (r["category"] == "pet" and r["code"] not in oldPets)];
        for code in split(dietary) { kept.append({"id": "dietary-" + code, "category": "dietary", "code": code, "strength": "hard"}); }
        for code in split(pets) { if not any(r["category"] == "pet" and r["code"] == code for r in kept) { kept.append({"id": "pet-" + code, "category": "pet", "code": code, "strength": "hard"}); } }
        if wheelchair { kept.append({"id": "accessibility-wheelchair", "category": "accessibility", "code": "wheelchair", "strength": "hard"}); }
        return kept;
    }
    async def saveFacts(e: FormEvent) -> None {
        e.preventDefault(); if busy or state is None { return; } busy = True; failure = ""; clear();
        request = sequence.current;
        try {
            browser: any = window; payload = browser.JSON.parse(browser.JSON.stringify(state["facts"]));
            if not browser.RegExp("^[0-9]+$").test(adults) or any(not browser.RegExp("^[0-9]+$").test(age) for age in split(children)) or
                not browser.RegExp("^[0-9]+([.][0-9]{1,2})?$").test(reserve) { failure = "Use whole numbers for traveler counts and ages, and at most two decimals for the reserve."; return; }
            payload["contract_version"] = "roam.planning-context.v1"; payload["zone"] = zone;
            payload["reserve_minor"] = int(round(float(reserve) * 100));
            old = payload.get("profile");
            payload["profile"] = {"id": old["id"] if old else "traveler-" + trip_id, "contract_version": "person1.traveler-profile.v1",
                "adults": int(adults), "child_ages": [int(age) for age in split(children)],
                "pets": [{"species": species, "size": petSize(species, old)} for species in split(pets)],
                "requirements": requirements(), "interests": old["interests"] if old else [], "pace": old["pace"] if old else "unknown"};
            payload["items"] = details;
            proof = {"source": "user://trip/" + trip_id + "/confirmed-facts", "checked_at": new(Date).toISOString(), "expires_at": new(Date, Date.now() + 900000).toISOString()};
            for item in scheduled {
                if not confirmed[item.id] { continue; }
                detail = browser.Object.assign({}, details[item.id] or {});
                detail["evidence"] = proof; detail["zone"] = zone;
                detail["party_size"] = int(adults) + len(split(children)) if detail.get("fees_included") else None;
                if detail.get("end") { detail["end"]["zone"] = zone; }
                payload["items"][item.id] = detail;
                if detail.get("hours") {
                    payload["place_hours"] = [h for h in payload.get("place_hours", []) if h["node_id"] != item.id];
                    for hours in detail["hours"] {
                        payload["place_hours"].append({"node_id": item.id, "date": hours["start"]["local"][:10],
                            "evidence_id": "item-facts:" + item.id, "open_local": hours["start"]["local"][11:16], "close_local": hours["end"]["local"][11:16]});
                    }
                }
            }
            payload["transfers"] = payload.get("transfers", []);
            for (index, item) in enumerate(scheduled) {
                if index + 1 >= len(scheduled) { continue; }
                following = scheduled[index + 1]; key = item.id + "|" + following.id;
                if routes[key] and confirmed[item.id] and confirmed[following.id] {
                    payload["transfers"] = [route for route in payload["transfers"] if route["from_id"] != item.id or route["to_id"] != following.id];
                    payload["transfers"].append({"from_id": item.id, "to_id": following.id, "from_venue": item.location, "to_venue": following.location,
                        "minutes": int(routes[key]), "evidence": proof});
                }
            }
            updated = await save_planning_context(trip_id=trip_id, payload=payload, expected_version=state["trip_version"]);
            if request != sequence.current { return; }
            fill(updated); notifyTabs();
            notice = "Trip facts saved. Missing information will still need confirmation.";
        } except Exception { failure = "Could not save these facts. Check the traveler counts, ages, timezone and amounts, then reload if the trip changed."; }
        finally { if alive.current { busy = False; if checkQueued.current { checkVersion(); } } }
    }
    async def findPlans -> None {
        if busy or state is None { return; } busy = True; failure = ""; notice = ""; clear();
        request = sequence.current;
        try {
            current = state; ids = selectedRisks;
            if reason != "detected" {
                if not target { failure = "Choose the affected itinerary item."; return; }
                payload = browser.JSON.parse(browser.JSON.stringify(state["facts"]));
                riskId = "traveler-report:" + target + ":" + reason;
                manual = {"id": riskId, "category": reason, "node_ids": [target], "summary": label(reason) + " reported by traveler",
                    "evidence": {"source": "user://trip/" + trip_id + "/reported-change", "checked_at": new(Date).toISOString(), "expires_at": new(Date, Date.now() + 900000).toISOString()}};
                if reason == "timing" and notBefore { manual["not_before"] = {"local": notBefore, "zone": state["facts"].get("zone", "")}; }
                payload["contract_version"] = "roam.planning-context.v1";
                payload["manual_risks"] = [r for r in payload.get("manual_risks", []) if r["id"] != riskId] + [manual];
                current = await save_planning_context(trip_id=trip_id, payload=payload, expected_version=state["trip_version"]);
                if request != sequence.current { return; }
                state = current; ids = [riskId]; notifyTabs();
            }
            response = await generate_backup_plans(trip_id=trip_id, expected_version=current["trip_version"], risk_ids=ids, max_plans=int(limit), use_llm=useAI);
            if request != sequence.current { return; }
            result = response;
            if onGenerated and len(response["plans"]) > 0 { onGenerated(); }
        } except Exception { failure = "Could not prepare current plans. Reload the trip and try again."; }
        finally { if alive.current { busy = False; if checkQueued.current { checkVersion(); } } }
    }
    async def review(id: str, accept: bool) -> None {
        if busy { return; } busy = True; failure = "";
        request = sequence.current;
        try {
            response = await review_backup_plan(trip_id=trip_id, proposal_id=id, accept=accept);
            if request != sequence.current { return; }
            notice = response["message"]; notifyTabs();
            if accept { clear(); if onApplied { await onApplied(); } else { await reload(); } }
            else { result = browser.Object.assign({}, result, {"plans": [p for p in result["plans"] if p["id"] != id]}); }
        } except Exception { clear(); failure = "This plan could not be applied. Its trip, price, availability or supporting evidence may have changed. Find fresh plans and review them again."; }
        finally { if alive.current { busy = False; if checkQueued.current { checkVersion(); } } }
    }
    currentItems: any = state.get("items", items) if state else items;
    scheduled = sorted([item for item in currentItems if item.category in ("activity", "food", "stay", "transport")], key=lambda (item: ItemView) -> str { item.date + "T" + item.time; });
    return <section className="card integrated-planning" aria-label="Integrated backup plans">
        <h3>Alternatives for your trip</h3><p>Prepare different ways to adjust your itinerary, compare their changes, and choose a plan.</p>
        <p className="muted">Demo inventory and prices are simulated. Acceptance updates this itinerary only.</p>
        {(<p role="status">Loading trip facts…</p>) if loading else None}
        {(<p role="alert" className="alert error">{failure}</p>) if failure else None}
        {(<p role="status">{notice}</p>) if notice else None}
        <button className="text-button" type="button" disabled={busy} onClick={reload}>Reload trip facts</button>
        {(<div>
            <details className="planning-facts"><summary>Traveler requirements and trip facts</summary>
                <form onSubmit={saveFacts}><fieldset disabled={busy}>
                    <div className="validation-controls">
                        <label>Adults<input type="number" min="1" required={True} value={adults} onChange={lambda (e: ChangeEvent) { adults = e.target.value; clear(); }}/></label>
                        <label>Children's ages, separated by commas<input value={children} placeholder="8, 12" onChange={lambda (e: ChangeEvent) { children = e.target.value; clear(); }}/></label>
                        <label>Pets<input value={pets} placeholder="dog" onChange={lambda (e: ChangeEvent) { pets = e.target.value; clear(); }}/></label>
                        <label>Dietary requirements<input value={dietary} placeholder="vegetarian, nut_free" onChange={lambda (e: ChangeEvent) { dietary = e.target.value; clear(); }}/></label>
                        <label>Trip timezone<input required={True} value={zone} placeholder="America/New_York" onChange={lambda (e: ChangeEvent) { zone = e.target.value; clear(); }}/></label>
                        <label>Budget reserve<input inputMode="decimal" value={reserve} onChange={lambda (e: ChangeEvent) { reserve = e.target.value; clear(); }}/></label>
                    </div>
                    <label className="replan-check"><input type="checkbox" checked={wheelchair} onChange={lambda (e: ChangeEvent) { wheelchair = e.target.checked; clear(); }}/>Wheelchair access required</label>
                    <p>Only confirm facts you know. Unconfirmed prices, requirements, hours or travel times remain unknown.</p>
                    {[<details className="planning-item-facts" key={item.id}><summary>{item.title}</summary>
                        <div className="validation-controls">
                            <label>End time<input type="datetime-local" value={details[item.id]["end"]["local"] if details[item.id] and details[item.id].get("end") else ""}
                                onChange={lambda (e: ChangeEvent) { setFact(item.id, "end", {"local": e.target.value, "zone": zone}); }}/></label>
                            <label>Availability<select value={details[item.id].get("availability", "unknown") if details[item.id] else "unknown"} onChange={lambda (e: ChangeEvent) { setFact(item.id, "availability", e.target.value); }}>
                                <option value="unknown">Unknown</option><option value="available">Available</option><option value="unavailable">Unavailable</option></select></label>
                            <label>Opens<input type="datetime-local" value={windowValue(item.id, "start")} onChange={lambda (e: ChangeEvent) { setWindow(item.id, "start", e.target.value); }}/></label>
                            <label>Closes<input type="datetime-local" value={windowValue(item.id, "end")} onChange={lambda (e: ChangeEvent) { setWindow(item.id, "end", e.target.value); }}/></label>
                            <label>Minimum child admission age<input type="number" min="0" value={str(details[item.id]["child_min_age"]) if details[item.id] and details[item.id].get("child_min_age") is not None else ""}
                                onChange={lambda (e: ChangeEvent) { setFact(item.id, "child_min_age", int(e.target.value) if e.target.value else None); }}/></label>
                            <label>Maximum child admission age<input type="number" min="0" value={str(details[item.id]["child_max_age"]) if details[item.id] and details[item.id].get("child_max_age") is not None else ""}
                                onChange={lambda (e: ChangeEvent) { setFact(item.id, "child_max_age", int(e.target.value) if e.target.value else None); }}/></label>
                        </div>
                        <div className="validation-controls">{[<label key={need["id"]}>{need["code"] + " supported"}<select value={eligibilityValue(item.id, need["category"] + ":" + need["code"])}
                            onChange={lambda (e: ChangeEvent) { setEligibility(item.id, need["category"] + ":" + need["code"], e.target.value); }}>
                            <option value="unknown">Unknown</option><option value="yes">Yes</option><option value="no">No</option></select></label> for need in requirements() if need["strength"] == "hard" and (need["category"] != "dietary" or item.category == "food")]}</div>
                        <label className="replan-check"><input type="checkbox" checked={bool(details[item.id] and details[item.id].get("fees_included"))}
                            onChange={lambda (e: ChangeEvent) { setFact(item.id, "fees_included", e.target.checked); }}/>Saved price covers the whole party, taxes and fees</label>
                        <button type="button" className="secondary" onClick={lambda { changed = browser.Object.assign({}, confirmed); changed[item.id] = True; confirmed = changed; }}>Confirm these item facts</button>
                        {(<p>These facts will be recorded when you save.</p>) if confirmed[item.id] else None}
                    </details> for item in scheduled]}
                    <div className="validation-controls">{[<label key={item.id}>{"Travel minutes: " + item.title + " to " + scheduled[index + 1].title}
                        <input type="number" min="0" value={routes[item.id + "|" + scheduled[index + 1].id] or ""} onChange={lambda (e: ChangeEvent) {
                            changed = browser.Object.assign({}, routes); changed[item.id + "|" + scheduled[index + 1].id] = e.target.value; routes = changed; clear();
                        }}/></label> for (index, item) in enumerate(scheduled) if index + 1 < len(scheduled)]}</div>
                    <button type="submit" className="secondary" disabled={busy}>Save requirements and facts</button></fieldset>
                </form>
            </details>
            <div className="validation-controls">
                <label>What should the plans address?<select value={reason} disabled={busy} onChange={lambda (e: ChangeEvent) { reason = e.target.value; clear(); }}>
                    <option value="detected">Detected risks</option>{[<option key={value} value={value}>{label(value)}</option> for value in ["weather", "timing", "closure", "cancellation", "long_drive", "opening_hours", "booking_terms", "traveler_change", "budget_change", "inventory_change"]]}</select></label>
                {(<label>Affected item<select value={target} disabled={busy} onChange={lambda (e: ChangeEvent) { target = e.target.value; clear(); }}><option value="">Choose an item</option>
                    {[<option key={item.id} value={item.id}>{item.title}</option> for item in scheduled if not item.done]}</select></label>) if reason != "detected" else None}
                {(<label>Earliest allowed start<input type="datetime-local" value={notBefore} disabled={busy} onChange={lambda (e: ChangeEvent) { notBefore = e.target.value; clear(); }}/></label>) if reason == "timing" else None}
                <label>Maximum alternatives<select value={limit} disabled={busy} onChange={lambda (e: ChangeEvent) { limit = e.target.value; clear(); }}>{[<option key={str(n)} value={str(n)}>{str(n)}</option> for n in [3, 4, 5]]}</select></label>
            </div>
            {(<p className="muted">Uses your saved budget. Edit the trip first to change that budget.</p>) if reason == "budget_change" else None}
            {(<p className="muted">Save the updated traveler requirements above before finding plans.</p>) if reason == "traveler_change" else None}
            {(<div className="planning-risk-list">{[<label className="replan-check" key={risk["id"]}><input type="checkbox" checked={risk["id"] in selectedRisks} disabled={busy}
                onChange={lambda (e: ChangeEvent) { selectedRisks = selectedRisks + [risk["id"]] if e.target.checked else [key for key in selectedRisks if key != risk["id"]]; clear(); }}/>
                {risk["summary"] + (" · Needs evidence" if risk["status"] != "flagged" else "")}</label> for risk in state["risks"]]}
                {(<p>No risks are established yet. Add trip facts or report a change.</p>) if len(state["risks"]) == 0 else None}</div>) if reason == "detected" else None}
            <label className="replan-check"><input type="checkbox" checked={useAI} disabled={busy} onChange={lambda (e: ChangeEvent) { useAI = e.target.checked; clear(); }}/>Use AI to choose among validated plans</label>
            <button type="button" className="primary" disabled={busy or (reason == "detected" and len(selectedRisks) == 0)} onClick={findPlans}>{"Preparing plans…" if busy else "Find alternative plans"}</button>
            {(<section className="planning-results" aria-live="polite"><p>{result["message"]}</p>
                <div className="backup-grid">{[<article className="backup-option" key={plan["id"]}>
                    <h4>{"Alternative " + str(index + 1)}</h4><p>{"Ready for review" if plan["selectable"] else "Needs confirmation"}</p>
                    {[<div key={change["replaces_id"]}><strong>{("Move " + title(change["replaces_id"])) if change["action"] == "reschedule" else title(change["replaces_id"]) + " → " + change["item"]["title"]}</strong>
                        <p>{"Originally: " + originalTime(change["replaces_id"])}</p>
                        <p>{"Proposed: " + change["item"]["start"]["local"] + " to " + change["item"]["end"]["local"] + " · " + change["item"]["start"]["zone"]}</p></div> for change in plan["replacements"]]}
                    <dl className="validation-costs"><div><dt>Original planned total, with reserve</dt><dd>{money(plan["comparison"]["original_planned_minor"])}</dd></div>
                        <div><dt>Projected trip total, with reserve</dt><dd>{money(plan["comparison"]["projected_total_minor"])}</dd></div>
                        <div><dt>Change in planned total</dt><dd>{costChange(plan["comparison"]["planned_difference_minor"])}</dd></div>
                        <div><dt>New purchase quotes</dt><dd>{money(plan["comparison"]["new_purchase_quotes_minor"])}</dd></div>
                        <div><dt>Cash due now</dt><dd>{money(plan["comparison"]["cash_needed_now_minor"])}</dd></div>
                        <div><dt>Potential cash not refunded</dt><dd>{money(plan["comparison"]["refund_loss_minor"])}</dd></div>
                        <div><dt>Potential credit</dt><dd>{money(plan["comparison"]["eligible_credit_minor"])}</dd></div></dl>
                    <p className="muted">Refunds have not been received. Quotes are not an amount due now.</p>
                    {(<ul>{[<li key={message}>{message}</li> for message in missingReasons(plan)]}</ul>) if not plan["selectable"] else None}
                    <button type="button" className="primary" disabled={busy or not plan["selectable"]} onClick={lambda { review(plan["id"], True); }}>Accept this plan</button>
                    <button type="button" className="secondary" disabled={busy} onClick={lambda { review(plan["id"], False); }}>Keep current plan</button>
                </article> for (index, plan) in enumerate(result["plans"])]}</div>
                <button type="button" className="secondary" disabled={busy} onClick={findPlans}>Find other plans</button>
            </section>) if result else None}
        </div>) if state else None}
    </section>;
}
