"""A route brief with ordered city stays and explicit transfer allowances."""
import from server.main { save_journey }

def:pub journeyLabel(route: any) -> str {
    if not route { return ""; }
    names = [route["origin"]["city"]] + [stop["city"] for stop in route["stops"]];
    if route["return_to"] { names.append(route["return_to"]["city"]); }
    return " → ".join(names);
}

def:pub legLabel(route: any, leg: any) -> str {
    names = {stop["id"]: stop["city"] for stop in route["stops"]};
    names["origin"] = route["origin"]["city"];
    if route["return_to"] { names["return"] = route["return_to"]["city"]; }
    return names[leg["from_id"]] + " → " + names[leg["to_id"]];
}

def point(city: str) -> any {
    return {"city": city, "zone": "", "lat": None, "lon": None};
}

def:pub RouteEditor(trip: any, data: any, onSaved: any, onPlan: any, disabled: bool) -> JsxElement {
    has draft: any = None, editing: bool = False, saving: bool = False, error: str = "", version: int = 0;
    browser: any = window;
    def copy(value: any) -> any { return browser.JSON.parse(browser.JSON.stringify(value)); }
    def rebuild(value: any) -> any {
        pairs: any = [["origin", value["stops"][0]["id"]]];
        for index in range(1, len(value["stops"])) { pairs.append([value["stops"][index-1]["id"], value["stops"][index]["id"]]); }
        if value["return_to"] { pairs.append([value["stops"][-1]["id"], "return"]); }
        old = value.get("legs", []); legs: any = [];
        for pair in pairs {
            found = [leg for leg in old if leg["from_id"] == pair[0] and leg["to_id"] == pair[1]];
            legs.append(found[0] if found else {"from_id": pair[0], "to_id": pair[1],
                "mode": "flight" if pair[0] == "origin" or pair[1] == "return" else "train", "before_minutes": 60, "after_minutes": 60});
        }
        value["legs"] = legs; return value;
    }
    def begin -> None {
        draft = copy(data["journey"]) if data.get("journey") else rebuild({"version": 1,
            "origin": point(trip.departure_location), "return_to": point(trip.return_location) if trip.return_location else None,
            "stops": [{**point(trip.destination), "id": "city1", "arrival_date": trip.start_date, "departure_date": trip.end_date}], "legs": []});
        version = data.get("version", 0); editing = True; error = "";
    }
    def update(section: str, index: int, field: str, value: any) -> None {
        next = copy(draft);
        if section in ["stops", "legs"] { next[section][index][field] = value; }
        else { next[section][field] = value; }
        if field == "city" {
            target = next[section][index] if section == "stops" else next[section];
            target["lat"] = None; target["lon"] = None;
        }
        draft = next;
    }
    def move(index: int, direction: int) -> None {
        next = copy(draft); other = index + direction;
        value = next["stops"][index]; next["stops"][index] = next["stops"][other]; next["stops"][other] = value;
        draft = rebuild(next);
    }
    def remove(index: int) -> None {
        next = copy(draft); next["stops"] = [stop for (i, stop) in enumerate(next["stops"]) if i != index]; draft = rebuild(next);
    }
    def add -> None {
        next = copy(draft); suffix = 1;
        while "city" + str(suffix) in [stop["id"] for stop in next["stops"]] { suffix += 1; }
        next["stops"].append({**point(""), "id": "city" + str(suffix), "arrival_date": trip.start_date, "departure_date": trip.end_date});
        draft = rebuild(next);
    }
    def label(id: str) -> str {
        if id == "origin" { return draft["origin"]["city"] or "Departure"; }
        if id == "return" { return draft["return_to"]["city"] or "Return"; }
        found = [stop for stop in draft["stops"] if stop["id"] == id];
        return found[0]["city"] or "City";
    }
    async def save(e: FormEvent) -> None {
        e.preventDefault(); if saving { return; } saving = True; error = "";
        try {
            fresh = await save_journey(trip_id=trip.id, payload=draft, expected_version=version);
            editing = False; onSaved(fresh);
        } except Exception as exc { error = str(exc); }
        finally { saving = False; }
    }
    <section className="card route-editor" aria-label="Journey route">
        <div className="section-heading"><div><p className="eyebrow">CITIES & TRANSFERS</p><h2>Your journey</h2></div>
            {(<button type="button" className="secondary" disabled={disabled} onClick={begin}>{"Edit route" if data.get("journey") else "Set up route"}</button>) if not editing else None}</div>
        {(<div><p className="route-summary">{journeyLabel(data["journey"])}</p>
            <ol className="route-stay-summary">{[<li key={stop["id"]}><strong>{stop["city"]}</strong><span>{stop["arrival_date"] + " – " + stop["departure_date"] + " · " + stop["zone"]}</span></li> for stop in data["journey"]["stops"]]}</ol>
            {(<ul className="route-issues">{[<li key={issue}>{issue}</li> for issue in data.get("issues", [])]}</ul>) if data.get("issues") else None}
            <button type="button" className="secondary" disabled={disabled or editing} onClick={lambda { onPlan("plan", "Plan the complete saved journey, including outbound travel, each city stay, intercity transport and the return if specified. Keep saved arrangements and show the full schedule for review."); }}>Plan this journey with AI</button>
        </div>) if data.get("journey") and not editing else None}
        {(<p className="section-caption">Set your departure, destination cities and return, or ask the assistant to propose the complete route. Times will be checked in each city's local time zone.</p>) if not data.get("journey") and not editing else None}
        {(<form onSubmit={save}>
            <fieldset disabled={saving or disabled}><legend>Departure</legend>
                <RoutePlace id="route-origin" value={draft["origin"]} onChange={lambda (field: str, value: any) { update("origin", 0, field, value); }}/>
            </fieldset>
            {[
                <fieldset key={stop["id"]} disabled={saving or disabled}><legend>{str(index+1) + " · Destination city / region"}</legend>
                    <RoutePlace id={"route-stop-" + str(index)} value={stop} onChange={lambda (field: str, value: any) { update("stops", index, field, value); }}/>
                    <div className="form-pair"><label>Arrival date<input aria-label={"City " + str(index+1) + " arrival date"} type="date" value={stop["arrival_date"]} min={trip.start_date} max={trip.end_date} required={True} onChange={lambda (e: ChangeEvent) { update("stops", index, "arrival_date", e.target.value); }}/></label>
                        <label>Departure date<input aria-label={"City " + str(index+1) + " departure date"} type="date" value={stop["departure_date"]} min={stop["arrival_date"]} max={trip.end_date} required={True} onChange={lambda (e: ChangeEvent) { update("stops", index, "departure_date", e.target.value); }}/></label></div>
                    <div className="route-row-actions"><button type="button" disabled={index == 0} onClick={lambda { move(index, -1); }}>Move up</button><button type="button" disabled={index == len(draft["stops"])-1} onClick={lambda { move(index, 1); }}>Move down</button><button type="button" disabled={len(draft["stops"]) == 1} onClick={lambda { remove(index); }}>Remove city</button></div>
                </fieldset> for (index, stop) in enumerate(draft["stops"])
            ]}
            <button type="button" className="secondary" disabled={saving or disabled or len(draft["stops"]) >= 12} onClick={add}>Add city / region</button>
            <label className="route-return-toggle"><input type="checkbox" checked={bool(draft["return_to"])} disabled={saving or disabled} onChange={lambda (e: ChangeEvent) {
                next = copy(draft); next["return_to"] = copy(next["origin"]) if e.target.checked else None; draft = rebuild(next);
            }}/> Include return travel</label>
            {(<fieldset disabled={saving or disabled}><legend>Return to</legend><RoutePlace id="route-return" value={draft["return_to"]} onChange={lambda (field: str, value: any) { update("return_to", 0, field, value); }}/></fieldset>) if draft["return_to"] else None}
            <p className="section-caption">Allow time before departure for check-in and access, and after arrival for baggage and onward travel. Durations and schedules are planning estimates until checked against a source.</p>
            {[
                <fieldset key={str(index)} disabled={saving or disabled}><legend>{label(leg["from_id"]) + " → " + label(leg["to_id"])}</legend>
                    <label>Transport<select aria-label={"Leg " + str(index+1) + " transport"} value={leg["mode"]} onChange={lambda (e: ChangeEvent) { update("legs", index, "mode", e.target.value); }}>{[<option key={mode} value={mode}>{mode}</option> for mode in ["flight", "train", "drive", "bus", "ferry"]]}</select></label>
                    <div className="form-pair"><label>Before departure (minutes)<input type="number" min="0" max="1440" step="1" value={str(leg["before_minutes"])} required={True} onChange={lambda (e: ChangeEvent) { update("legs", index, "before_minutes", int(e.target.value or "0")); }}/></label>
                        <label>After arrival (minutes)<input type="number" min="0" max="1440" step="1" value={str(leg["after_minutes"])} required={True} onChange={lambda (e: ChangeEvent) { update("legs", index, "after_minutes", int(e.target.value or "0")); }}/></label></div>
                </fieldset> for (index, leg) in enumerate(draft["legs"])
            ]}
            {(<p role="alert" className="alert error">{error}</p>) if error else None}
            <div className="route-row-actions"><button type="submit" className="secondary" disabled={saving or disabled}>{"Saving…" if saving else "Save journey route"}</button><button type="button" className="text-button" disabled={saving} onClick={lambda { editing = False; }}>Cancel</button></div>
        </form>) if editing and draft else None}
    </section>
}

def:pub RoutePlace(id: str, value: any, onChange: any) -> JsxElement {
    <div className="route-place">
        <div className="form-pair"><div><label htmlFor={id + "-city"}>City / region</label><input id={id + "-city"} value={value["city"]} required={True} maxLength={160} onChange={lambda (e: ChangeEvent) { onChange("city", e.target.value); }}/></div>
            <div><label htmlFor={id + "-zone"}>Time zone</label><input id={id + "-zone"} value={value["zone"]} list="journey-zones" placeholder="Asia/Tokyo" required={True} maxLength={100} onChange={lambda (e: ChangeEvent) { onChange("zone", e.target.value); }}/></div></div>
        <details><summary>Map coordinates (optional)</summary><div className="form-pair">
            <label>Latitude<input type="number" min="-90" max="90" step="any" value={str(value["lat"]) if value.get("lat") is not None else ""} onChange={lambda (e: ChangeEvent) { onChange("lat", float(e.target.value) if e.target.value else None); }}/></label>
            <label>Longitude<input type="number" min="-180" max="180" step="any" value={str(value["lon"]) if value.get("lon") is not None else ""} onChange={lambda (e: ChangeEvent) { onChange("lon", float(e.target.value) if e.target.value else None); }}/></label>
        </div></details>
    </div>
}
