"""Unmapped route cities with a way to place them on the map."""
import from workspace { workspaceKey }
import from server.main { search_map_places, journey_state, locate_journey_city }

def readable(text: str, fallback: str) -> str {
    offset = text.find(" failed: ");
    detail = (text[offset + 9:] if offset >= 0 else text).strip();
    return fallback if not detail or "<" in detail or len(detail) > 200 else detail;
}

def:pub UnmappedStop(trip_id: str, place: any, editable: bool, onSaved: any) -> JsxElement {
    has open: bool = False, query: str = place["city"], matches: any = [], busy: bool = False,
        searched: bool = False, error: str = "";
    async def search(e: FormEvent) -> None {
        e.preventDefault(); busy = True; error = ""; matches = []; searched = False;
        try { matches = await search_map_places(query=query); searched = True; }
        except Exception as exc { error = readable(str(exc), "Place search did not respond. Try again, or enter coordinates in the Route tab."); }
        finally { busy = False; }
    }
    async def choose(found: any) -> None {
        busy = True; error = "";
        try {
            key = await workspaceKey();
            current = await journey_state(workspace_key=key, trip_id=trip_id);
            await locate_journey_city(workspace_key=key, trip_id=trip_id, city=place["city"],
                lat=found["lat"], lon=found["lon"], expected_version=current["version"]);
            open = False; matches = [];
            await onSaved();
        } except Exception as exc { error = readable(str(exc), "This location could not be saved. Reload the map and try again."); }
        finally { busy = False; }
    }
    <div className="map-unlocated-location">
        <strong>{place["city"]}</strong>
        <small>{"Location not mapped yet" + ("" if editable else " · Save the route to locate it")}</small>
        {(<button type="button" className="map-secondary" aria-label={"Find " + place["city"] + " on the map"}
            onClick={lambda { open = True; }}>Find on map</button>) if editable and not open else None}
        {(<form className="map-location-search" onSubmit={search}>
            <label>{"Search for " + place["city"]}<input value={query} maxLength={300} required={True} disabled={busy}
                onChange={lambda (e: ChangeEvent) { query = e.target.value; matches = []; searched = False; }}/></label>
            <button type="submit" className="map-secondary" disabled={busy}>{"Searching…" if busy else "Search"}</button>
            {[<button type="button" key={str(found["lat"]) + str(found["lon"])} className="map-list-row" disabled={busy}
                onClick={lambda { choose(found); }}><span><strong>{found["label"]}</strong><small>Use this location for the route</small></span></button>
                for found in matches]}
            {(<p role="status">No matching places. Try the city with its state or country.</p>) if searched and not matches else None}
            <small>Or enter exact coordinates for this city in the Route tab.</small>
        </form>) if editable and open else None}
        {(<p role="alert" className="map-inline-error">{error}</p>) if error else None}
    </div>
}
