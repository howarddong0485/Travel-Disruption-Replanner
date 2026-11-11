"""Read impact from saved dependencies and review connected plans in the itinerary."""
import from server.main { replan_state, planning_state, report_itinerary_change, generate_backup_plans, review_backup_plan }
import from itinerary.presentation { affectedItemIds, planTitle, shiftLabel, differenceLabel }
import from itinerary.evidence { EvidencePopover, planSources }

def:pub itinerarySchedule(date: str, time: str) -> str {
    return date + (" · " + time if time else " · Flexible time") if date else "Date to be decided";
}

def:pub ItineraryReview(trip_id: str, currency: str, items: any, request: any,
    onPreview: any, onClose: any, onApplied: any, onFacts: any, onMapUpdate: any) -> JsxElement {
    browser: any = window;
    recordedRisks = request.get("risks", []);
    recordedMode = len(recordedRisks) > 0;
    has target: str = request["item"], reason: str = request["reason"], delay: str = request.get("delay", ""),
        snapshot: any = None, result: any = None, choice: str = "", earliest: str = "",
        failure: str = "", notice: str = "", loading: bool = True, busy: bool = False, checking: bool = False,
        showReport: bool = False,
        sheetSize: str = "half", dragHeight: float = 0.0, drag: Ref[any] = Ref(None),
        alive: Ref[bool] = Ref(True), operation: Ref[int] = Ref(0),
        expiry: Ref[int] = Ref(0), listener: Ref[any] = Ref(None), focusHandler: Ref[any] = Ref(None),
        keyListener: Ref[any] = Ref(None), closeHandler: Ref[any] = Ref(None);

    def money(value: any) -> str {
        return "Needs confirmation" if value is None else currency + " " + (value / 100).toFixed(2);
    }
    def focusWithinReview(id: str, reveal: bool = False) -> None {
        control: any = document.getElementById(id);
        if control {
            control.focus({"preventScroll": True});
            pane: any = control.closest(".review-scroll");
            if reveal and pane {
                pane.scrollTop += control.getBoundingClientRect().top - pane.getBoundingClientRect().top - 12;
            }
        }
    }
    def sheetHeight(size: str) -> float {
        ratio = 0.30 if size == "peek" else 0.60 if size == "half" else 0.92;
        return min(browser.innerHeight * 0.92, max(240.0, browser.innerHeight * ratio));
    }
    def resizeSheet(size: str) -> None { sheetSize = size; dragHeight = 0.0; }
    def startDrag(e: any) -> None {
        if e.button != 0 { return; }
        drag.current = {"y": e.clientY, "height": sheetHeight(sheetSize), "moved": False, "active": True};
        e.currentTarget.setPointerCapture(e.pointerId);
    }
    def moveDrag(e: any) -> None {
        if drag.current is None or not drag.current["active"] { return; }
        distance = drag.current["y"] - e.clientY;
        if abs(distance) > 8 { drag.current["moved"] = True; }
        if drag.current["moved"] {
            dragHeight = max(sheetHeight("peek"), min(sheetHeight("full"), drag.current["height"] + distance));
        }
    }
    def endDrag(e: any) -> None {
        if drag.current is None { return; }
        if drag.current["moved"] {
            height = dragHeight;
            nearest = "peek";
            for size in ["half", "full"] {
                if abs(sheetHeight(size) - height) < abs(sheetHeight(nearest) - height) { nearest = size; }
            }
            resizeSheet(nearest);
        }
        drag.current["active"] = False;
        e.currentTarget.releasePointerCapture(e.pointerId);
    }
    def clear -> None {
        result = None; choice = ""; earliest = ""; showReport = False;
        if expiry.current { window.clearTimeout(expiry.current); expiry.current = 0; }
    }
    def reset -> None {
        operation.current += 1; clear(); failure = ""; notice = ""; checking = False;
    }
    async def load -> None {
        reset(); loading = True;
        try {
            fresh = await replan_state(trip_id=trip_id);
            if not alive.current { return; }
            snapshot = fresh;
            prior = request.get("options", []);
            if len(prior) > 0 {
                state = await planning_state(trip_id=trip_id);
                if not alive.current { return; }
                current = [p for p in prior if p["base_version"] == state["trip_version"] and
                    state["review_statuses"].get(p["id"]) == "proposed" and Date.parse(p["expires_at"]) > Date.now()];
                if len(current) > 0 {
                    requested = request.get("option", "");
                    result = {"plans": current, "base_version": state["trip_version"], "warnings": [], "rejections": [],
                        "message": "Review your saved alternatives.", "input_snapshot": {"facts": state["facts"]}};
                    choice = requested if any(p["id"] == requested for p in current) else current[0]["id"];
                } else { notice = "These options changed or expired. Find fresh alternatives."; }
            }
        } except Exception {
            if alive.current { snapshot = None; failure = "Could not load the trip. Try reloading the review."; }
        } finally { if alive.current { loading = False; } }
    }
    async def verify -> None {
        if not alive.current or busy or loading or checking or result is None { return; }
        token = operation.current;
        checking = True;
        try {
            fresh = await planning_state(trip_id=trip_id);
            if alive.current and token == operation.current and (
                fresh["trip_version"] != result["base_version"] or any(
                    fresh["review_statuses"].get(p["id"]) != "proposed" or Date.parse(p["expires_at"]) <= Date.now() for p in result["plans"]
                )
            ) { clear(); notice = "These options are stale or expired. Reload the impact and find fresh options."; }
        } except Exception {
            if alive.current and token == operation.current { clear(); failure = "Could not verify these options. Reload and find fresh options."; }
        } finally { if alive.current and token == operation.current { checking = False; } }
    }
    focusHandler.current = verify;
    closeHandler.current = lambda { if not (busy and result) { onClose(); } };
    can with entry {
        alive.current = True;
        focusWithinReview("itinerary-review-title");
        load();
        listener.current = lambda { focusHandler.current(); };
        keyListener.current = lambda (e: any) { if e.key == "Escape" { closeHandler.current(); } };
        window.addEventListener("focus", listener.current);
        window.addEventListener("storage", listener.current);
        window.addEventListener("keydown", keyListener.current);
    }
    can with exit {
        alive.current = False;
        if expiry.current { window.clearTimeout(expiry.current); }
        window.removeEventListener("focus", listener.current);
        window.removeEventListener("storage", listener.current);
        window.removeEventListener("keydown", keyListener.current);
    }
    can with [items] entry { verify(); }
    can with [result] entry {
        if expiry.current { window.clearTimeout(expiry.current); expiry.current = 0; }
        if result and len(result["plans"]) > 0 {
            if sheetSize == "peek" { resizeSheet("half"); }
            focusWithinReview("itinerary-review-options", True);
            expiry.current = window.setTimeout(lambda {
                clear(); notice = "These options expired. Reload the impact and find fresh options.";
            }, max(0.0, min(Date.parse(p["expires_at"]) for p in result["plans"]) - Date.now()));
        }
    }
    available: any = sorted([item for item in snapshot["items"] if item["category"] in ["transport", "stay", "food", "activity"]],
        key=lambda (item: any) -> str { return (item["date"] or "9999") + "T" + item["time"]; }) if snapshot else [];
    originals = {item["id"]: item for item in available};
    selected_item = originals.get(target);
    affected = affectedItemIds(snapshot, target);
    affected_items = [item for item in available if item["id"] in affected];
    options: any = result["plans"] if result else [];
    matches = [plan for plan in options if plan["id"] == choice];
    plan = matches[0] if matches else None;
    changes: any = {change["replaces_id"]: change["item"] for change in plan["replacements"]} if plan else {};
    comparison: any = plan["comparison"] if plan else {};
    readyOptions = [option for option in options if option["selectable"]];
    priced = [option for option in readyOptions if option["comparison"]["projected_total_minor"] is not None];
    lowest = min(option["comparison"]["projected_total_minor"] for option in priced) if len(priced) > 0 and len(priced) == len(readyOptions) else None;
    facts = result.get("input_snapshot", {}).get("facts", {}) if result else {};
    can with [snapshot, target, choice, result] entry {
        onPreview({"affected": {item["id"]: index for (index, item) in enumerate(affected_items)},
            "protected": [item["id"] for item in available if item["protected"]], "changes": changes, "choice": choice,
            "time_changes": {time["item_id"]: time["start_shift_minutes"] for time in comparison.get("time_changes", [])}});
    }

    delay_valid = browser.RegExp("^[0-9]+$").test(delay) and int(delay) >= 1 and int(delay) <= 1440;
    async def generate(e: FormEvent) -> None {
        e.preventDefault();
        if busy or checking or loading or not selected_item { return; }
        if not recordedMode and (not reason or (reason == "timing" and not delay_valid)) { return; }
        reset(); busy = True;
        try {
            version = snapshot["version"]; risks = recordedRisks;
            if not recordedMode {
                recorded = await report_itinerary_change(trip_id=trip_id, item_id=target, reason=reason,
                    expected_version=version, delay_minutes=int(delay) if reason == "timing" else 0);
                if not alive.current { return; }
                version = recorded["trip_version"]; risks = [recorded["risk_id"]];
                snapshot = browser.Object.assign({}, snapshot, {"version": version});
                moment = recorded.get("not_before");
                if moment { earliest = moment["local"].replace("T", " ") + " · " + moment["zone"]; }
            }
            generated = await generate_backup_plans(trip_id=trip_id, expected_version=version,
                risk_ids=risks, max_plans=4);
            if not alive.current { return; }
            result = generated;
            choice = generated["plans"][0]["id"] if len(generated["plans"]) > 0 else "";
        } except Exception as exc {
            if alive.current { failure = str(exc); }
        } finally { if alive.current { busy = False; onMapUpdate(); } }
    }
    async def apply -> None {
        if busy or checking or plan is None or not plan["selectable"] { return; }
        if Date.parse(plan["expires_at"]) <= Date.now() {
            clear(); notice = "This option expired. Reload and find fresh options."; return;
        }
        busy = True; failure = "";
        try {
            response = await review_backup_plan(trip_id=trip_id, proposal_id=plan["id"], accept=True);
            if alive.current {
                if response["status"] == "accepted" { await onApplied(response["message"]); }
                else { clear(); failure = "This option was not saved. Reload and review fresh options."; }
            }
        } except Exception {
            if alive.current { clear(); failure = "This option could not be saved. The trip or supporting facts may have changed. Reload and review fresh options."; }
        } finally { if alive.current { busy = False; } }
    }
    missing: list[str] = []; conflicts: list[str] = [];
    if plan and not plan["selectable"] {
        for check in plan["validation"]["checks"] {
            if check["status"] == "unknown" and check["message"] not in missing { missing.append(check["message"]); }
        }
    }
    if result and len(options) == 0 {
        for rejection in result["rejections"] {
            for check in rejection["checks"] {
                if check["message"] not in conflicts and len(conflicts) < 4 { conflicts.append(check["message"]); }
            }
        }
    }
    return <aside className="card itinerary-review" aria-labelledby="itinerary-review-title" data-sheet-size={sheetSize}
        data-dragging={dragHeight > 0} style={{"--review-drag-height": str(dragHeight) + "px"}}>
        <div className="review-sheet-controls">
            <button type="button" className="review-sheet-handle" aria-label="Resize review sheet"
                onPointerDown={startDrag} onPointerMove={moveDrag} onPointerUp={endDrag}
                onPointerCancel={lambda { drag.current = None; dragHeight = 0.0; }}
                onClick={lambda {
                    moved = drag.current is not None and drag.current["moved"]; drag.current = None;
                    if not moved { resizeSheet("half" if sheetSize == "peek" else "full" if sheetSize == "half" else "peek"); }
                }}
                onKeyDown={lambda (e: any) {
                    if e.key in ["ArrowUp", "ArrowDown", "Home", "End"] {
                        e.preventDefault();
                        if e.key == "Home" { resizeSheet("peek"); }
                        elif e.key == "End" { resizeSheet("full"); }
                        elif e.key == "ArrowUp" { resizeSheet("half" if sheetSize == "peek" else "full"); }
                        else { resizeSheet("half" if sheetSize == "full" else "peek"); }
                    }
                }}><span aria-hidden="true"/></button>
            <div role="group" aria-label="Review sheet size">
                {[<button type="button" key={size} aria-pressed={sheetSize == size} onClick={lambda { resizeSheet(size); }}>
                    {"Summary" if size == "peek" else "Compare" if size == "half" else "Details"}
                </button> for size in ["peek", "half", "full"]]}
            </div>
            <span className="sr-only" role="status">{"Review sheet " + sheetSize}</span>
        </div>
        <div className="itinerary-panel-heading">
            <div><p className="eyebrow">{"2 · COMPARE OPTIONS" if len(options) > 0 else "1 · REVIEW A CHANGE"}</p>
                <h2 id="itinerary-review-title" tabIndex={-1}>Impact and alternatives</h2></div>
            <button type="button" className="itinerary-chip" aria-label="Close review" disabled={busy and bool(result)} onClick={onClose}>×</button>
        </div>
        <p className="review-peek-summary">{planTitle(plan) if plan else "Choose a stop and review its impact. Expand to enter the details."}</p>
        <div className="review-scroll">
        <p className="section-caption">Compare against your saved itinerary. Options use synthetic inventory and current trip facts.</p>
        {(<p className="alert error" role="alert">{failure}</p>) if failure else None}
        {(<p className="alert success" role="status">{notice}</p>) if notice else None}
        {(<button type="button" className="text-button" disabled={busy or loading} onClick={load}>Reload trip impact</button>) if failure or notice else None}
        {(<p role="status">Loading saved schedule…</p>) if loading else None}
        {(<div className="review-report-summary">
            <span><small>AFFECTED STOP</small><strong>{selected_item["title"]}</strong></span>
            <button type="button" className="itinerary-chip" aria-expanded={showReport} aria-controls="itinerary-review-report"
                disabled={busy} onClick={lambda {
                    opening = not showReport; showReport = opening;
                    if opening { window.requestAnimationFrame(lambda { focusWithinReview("itinerary-disruption-item", True); }); }
                }}>{"Hide controls" if showReport and recordedMode else "Find fresh alternatives" if recordedMode else "Hide report" if showReport else "Edit report"}</button>
        </div>) if len(options) > 0 and selected_item else None}
        {(<form id="itinerary-review-report" onSubmit={generate} className="itinerary-review-form" hidden={len(options) > 0 and not showReport}>
            <p className="section-caption">Find options for the recorded alert using your saved trip facts.</p>
            {(<section className="review-impact"><h3>Arrangements to check</h3>
                <ol>{[<li key={item["id"]}>{item["title"]}</li> for item in affected_items]}</ol></section>) if len(affected_items) > 0 else None}
            <button type="submit" className="primary" disabled={busy or checking or not selected_item}>
                {"Finding alternatives…" if busy else "Find alternatives"}</button>
        </form>) if snapshot and not loading and recordedMode else None}
        {(<form id="itinerary-review-report" onSubmit={generate} className="itinerary-review-form" hidden={len(options) > 0 and not showReport}>
            <label htmlFor="itinerary-disruption-item">Affected itinerary item</label>
            <select id="itinerary-disruption-item" value={target if selected_item else ""} disabled={busy} required={True}
                onChange={lambda (e: ChangeEvent) { target = e.target.value; reset(); }}>
                <option value="">Choose an item</option>
                {[<option key={item["id"]} value={item["id"]}>{item["title"] + " · " + itinerarySchedule(item["date"], item["time"])}</option> for item in available]}
            </select>
            <label htmlFor="itinerary-disruption-kind">What changed?</label>
            <select id="itinerary-disruption-kind" value={reason} disabled={busy} required={True}
                onChange={lambda (e: ChangeEvent) { reason = e.target.value; reset(); }}>
                <option value="">Choose a disruption</option>
                <option value="timing">Delay</option><option value="weather">Weather disruption</option>
                <option value="closure">Venue closure</option><option value="cancellation">Cancellation</option>
                <option value="traveler_change">I'd like a different arrangement</option>
            </select>
            {(<div><label htmlFor="itinerary-delay">Delay in minutes</label>
                <input id="itinerary-delay" value={delay} type="number" min="1" max="1440" step="1" required={True} disabled={busy}
                    onChange={lambda (e: ChangeEvent) { delay = e.target.value; reset(); }}/></div>) if reason == "timing" else None}
            {(<p className="section-caption">Add a date and time for this item before reporting a delay.</p>) if reason == "timing" and selected_item and (not selected_item["date"] or not selected_item["time"]) else None}
            {(<section className="review-impact"><h3>Arrangements to check</h3>
                <ol>{[<li key={item["id"]}>{item["title"] + (" · Fixed or completed" if item["protected"] else "")}</li> for item in affected_items]}</ol>
                {(<p className="section-caption">No downstream dependencies are saved for this item. Schedule rules are available in Replan.</p>) if len(affected_items) == 1 else None}
            </section>) if selected_item else None}
            <button className="primary" type="submit"
                disabled={busy or checking or not selected_item or not reason or (reason == "timing" and
                    (not delay_valid or not selected_item["date"] or not selected_item["time"]))}>
                {"Finding alternatives…" if busy and not result else "Report change and find alternatives"}
            </button>
        </form>) if snapshot and not loading and not recordedMode else None}
        {(<p className="section-caption">{"Reported earliest start: " + earliest}</p>) if earliest else None}
        {(<section className="review-results" aria-label="Plan options">
            <div aria-live="polite"><p>{result["message"]}</p></div>
            {[<p className="section-caption" key={warning}>{warning}</p> for warning in result["warnings"]]}
            {(<ul className="review-conflicts">{[<li key={message}>{message}</li> for message in conflicts]}</ul>) if conflicts else None}
            {(<div><h3 id="itinerary-review-options" tabIndex={-1}>Choose an option to preview</h3>
                <fieldset className="review-options" aria-labelledby="itinerary-review-options">
                {[<article className="review-option-card" key={option["id"]} data-selected={choice == option["id"]}>
                    <label className="review-option">
                    <input type="radio" name="itinerary-option" value={option["id"]} checked={choice == option["id"]} disabled={busy}
                        onChange={lambda { choice = option["id"]; }}/>
                    <span><strong>{planTitle(option)}</strong>
                        <span className="option-total">{money(option["comparison"]["projected_total_minor"])}</span>
                        <small>{differenceLabel(option["comparison"]["planned_difference_minor"], currency) +
                            " · " + str(len(option["replacements"])) +
                            (" stop changed" if len(option["replacements"]) == 1 else " stops changed")}</small>
                        <small>{", ".join([shiftLabel(time["start_shift_minutes"]) for time in option["comparison"]["time_changes"]])}</small>
                        {(<span className="option-badge">Lowest total among ready options</span>) if option["selectable"] and
                            lowest is not None and option["comparison"]["projected_total_minor"] == lowest else None}
                        {(<small>Ready for review</small>) if option["selectable"] else None}
                    </span>
                    </label>
                    {(<EvidencePopover id={"evidence-" + option["id"]}
                        checks={[check for check in option["validation"]["checks"] if check["status"] == "unknown"]}
                        sources={planSources(option, facts)} onFacts={onFacts}/>) if not option["selectable"] else None}
                </article> for (index, option) in enumerate(options)]}
            </fieldset></div>) if len(options) > 0 else None}
            {(<div className="review-preview" aria-live="polite">
                <div className="review-diff" key={choice}>
                    <h3>Saved → proposed</h3>
                    <ul>{[<li key={item["id"]}><strong>{item["title"]}</strong>
                        <span>{itinerarySchedule(item["date"], item["time"])}</span>
                        <span className="proposed-time">{(changes[item["id"]]["title"] + " · " if changes[item["id"]]["title"] != item["title"] else "") +
                            changes[item["id"]]["start"]["local"].replace("T", " ")}</span></li>
                        for item in available if item["id"] in changes]}</ul>
                </div>
                <dl className="review-costs">
                    <div><dt>Saved planned total</dt><dd>{money(comparison["original_planned_minor"])}</dd></div>
                    <div><dt>Projected trip total</dt><dd>{money(comparison["projected_total_minor"])}</dd></div>
                    <div><dt>Change in total</dt><dd>{money(comparison["planned_difference_minor"])}</dd></div>
                    <div><dt>New purchase quotes</dt><dd>{money(comparison["new_purchase_quotes_minor"])}</dd></div>
                    <div><dt>Cash due now</dt><dd>{money(comparison["cash_needed_now_minor"]) if comparison["cash_needed_now_minor"] is not None else
                        (<EvidencePopover id="cash-evidence" checks={[{"code": "payment timing", "message": "Payment timing, received refunds and usable credits have not been supplied. Purchase quotes alone do not establish an amount due now."}]}
                            sources={[]} onFacts={lambda { onFacts("budget"); }} actionLabel="View trip budget"/>)}</dd></div>
                </dl>
                <p className="section-caption">Totals include any saved reserve. Quotes are estimates.</p>
                {(<div className="review-unresolved"><strong>Needs confirmation</strong>
                    <ul>{[<li key={message}>{message}</li> for message in missing]}</ul>
                    <p>Complete the missing facts in Backup plans, then refresh these options.</p>
                    <button type="button" className="itinerary-chip" disabled={busy} onClick={lambda { onFacts(); }}>Open saved trip facts</button></div>) if not plan["selectable"] else None}
            </div>) if plan else None}
        </section>) if result else None}
        </div>
        {(<div className="review-footer">
            <div><small>Projected trip total</small><strong>{money(comparison["projected_total_minor"])}</strong></div>
            <button className="primary" type="button" disabled={busy or checking or not plan["selectable"]} onClick={apply}>
                {"Saving revision…" if busy else "Checking freshness…" if checking else "Confirm and save revision"}
            </button>
        </div>) if plan else None}
    </aside>;
}
