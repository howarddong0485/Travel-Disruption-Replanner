"""Edit the geographic endpoints of a saved transport item."""
import from server.main { save_trip_map_route }
import from itinerary.map_geometry { cityPoint }

def routeEndpoint(name: str, lat: str, lon: str) -> any {
    if lat.strip() and lon.strip() { return {"label": name.strip(), "lat": float(lat), "lon": float(lon)}; }
    if lat.strip() or lon.strip() { return None; }
    return cityPoint(name);
}

def:pub MapRouteEditor(trip_id: str, item: any, data: any, onSaved: any, onCancel: any) -> JsxElement {
    saved = data.get("route");
    has fromName: str = saved["from"]["label"] if saved is not None else "",
        toName: str = saved["to"]["label"] if saved is not None else "",
        fromLat: str = str(saved["from"]["lat"]) if saved is not None else "",
        fromLon: str = str(saved["from"]["lon"]) if saved is not None else "",
        toLat: str = str(saved["to"]["lat"]) if saved is not None else "",
        toLon: str = str(saved["to"]["lon"]) if saved is not None else "",
        kind: str = saved["kind"] if saved is not None else "flight",
        busy: bool = False, failure: str = "";
    async def persist(payload: any) -> None {
        if busy { return; }
        busy = True; failure = "";
        try {
            await save_trip_map_route(trip_id=trip_id, item_id=item.id, title=item.title, location=item.location,
                expected_revision=data.get("revision", 0), payload=payload);
            await onSaved();
        } except Exception as exc { failure = str(exc); }
        finally { busy = False; }
    }
    async def submit(e: FormEvent) -> None {
        e.preventDefault();
        origin = routeEndpoint(fromName, fromLat, fromLon);
        arrival = routeEndpoint(toName, toLat, toLon);
        if origin is None or arrival is None {
            failure = "Enter a supported city or supply coordinates for each endpoint."; return;
        }
        await persist({"from": origin, "to": arrival, "kind": kind});
    }
    <form className="map-route-editor" onSubmit={submit}>
        <label>Transport type<select value={kind} disabled={busy} onChange={lambda (e: ChangeEvent) { kind = e.target.value; }}>
            <option value="flight">Flight</option><option value="ground">Ground transport</option></select></label>
        <div className="form-pair">
            <label>From city or airport<input value={fromName} required={True} maxLength={100} disabled={busy}
                onChange={lambda (e: ChangeEvent) { fromName = e.target.value; fromLat = ""; fromLon = ""; }}/></label>
            <label>To city or airport<input value={toName} required={True} maxLength={100} disabled={busy}
                onChange={lambda (e: ChangeEvent) { toName = e.target.value; toLat = ""; toLon = ""; }}/></label>
        </div>
        <details><summary>Enter exact coordinates</summary>
            <div className="form-pair">
                <label>From latitude<input value={fromLat} type="number" min="-90" max="90" step="any" disabled={busy}
                    onChange={lambda (e: ChangeEvent) { fromLat = e.target.value; }}/></label>
                <label>From longitude<input value={fromLon} type="number" min="-180" max="180" step="any" disabled={busy}
                    onChange={lambda (e: ChangeEvent) { fromLon = e.target.value; }}/></label>
                <label>To latitude<input value={toLat} type="number" min="-90" max="90" step="any" disabled={busy}
                    onChange={lambda (e: ChangeEvent) { toLat = e.target.value; }}/></label>
                <label>To longitude<input value={toLon} type="number" min="-180" max="180" step="any" disabled={busy}
                    onChange={lambda (e: ChangeEvent) { toLon = e.target.value; }}/></label>
            </div>
        </details>
        {(<p className="map-inline-error" role="alert">{failure}</p>) if failure else None}
        <div className="map-popup-actions">
            <button type="submit" className="map-primary" disabled={busy}>{ "Saving…" if busy else "Save route"}</button>
            <button type="button" className="map-secondary" disabled={busy} onClick={onCancel}>Cancel</button>
            {(<button type="button" className="map-secondary" disabled={busy} onClick={lambda { persist(None); }}>Remove route</button>) if saved is not None else None}
        </div>
    </form>
}
