"""Confirm geographic matches and research exact dated flights from the map."""
import from server.main { search_map_places, get_place_details, save_place_details, search_map_flight, load_recorded_flight_tracks, save_trip_flight_track }

def:pub MapPlaceSearch(trip_id: str, item: any, destination: str, onSaved: any, lookup: any = None) -> JsxElement {
    has query: str = (item.location if item.location and not item.location.startswith("fixture:") else item.title) + ", " + destination,
        matches: any = [], busy: bool = False, error: str = "", searched: bool = False, saved: bool = False;
    can with entry {
        if lookup and lookup.get("status") == "needs_confirmation" { query = lookup["query"]; matches = lookup["matches"]; searched = True; }
    }
    async def search(e: FormEvent) -> None {
        e.preventDefault(); busy = True; error = ""; saved = False;
        try { matches = await search_map_places(query=query); searched = True; }
        except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def choose(place: any) -> None {
        busy = True; error = "";
        try {
            current = await get_place_details(trip_id=trip_id, item_id=item.id);
            if current["location"] != item.location { error = "This stop changed. Reopen it before locating it."; return; }
            await save_place_details(trip_id=trip_id, item_id=item.id, location=item.location,
                expected_revision=current["revision"], payload={"latitude": place["lat"], "longitude": place["lon"],
                    "photo_url": current["photo_url"], "photo_source": current["photo_source"]});
            matches = []; saved = True; await onSaved();
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    <div className="map-location-search">
        <form onSubmit={search}><label>Find this place<input value={query} maxLength={300} required={True}
            onChange={lambda (e: ChangeEvent) { query = e.target.value; matches = []; searched = False; }}/></label>
            <button type="submit" className="map-secondary" disabled={busy}>{"Searching…" if busy else "Search location"}</button></form>
        {[<button type="button" key={str(place["lat"]) + str(place["lon"])} className="map-list-row" disabled={busy}
            onClick={lambda { choose(place); }}><span><strong>{place["label"]}</strong><small>Use this location</small></span></button> for place in matches]}
        {(<p role="status">Location saved on your map.</p>) if saved else None}
        {(<p role="status">No matching places. Try a specific venue or street address.</p>) if searched and not matches and not saved else None}
        {(<p role="alert" className="map-inline-error">{error}</p>) if error else None}
        <small>Place search © OpenStreetMap contributors</small>
    </div>
}

def:pub FlightSearch(trip_id: str, item: any, apiKey: str, onTrack: any, saved: any, onSaved: any) -> JsxElement {
    has callsign: str = "", tracks: any = [], trackSearched: bool = False, trackDay: str = item.date,
        ident: str = "", flightDate: str = item.date, result: any = None, busy: bool = False, operation: str = "", error: str = "";
    async def search(e: FormEvent) -> None {
        e.preventDefault(); busy = True; operation = "web"; error = ""; result = None;
        try { result = await search_map_flight(ident=ident, departure_date=flightDate, api_key=apiKey); }
        except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def findTracks(e: FormEvent) -> None {
        e.preventDefault(); busy = True; operation = "track"; error = ""; tracks = []; trackSearched = False;
        try { found = await load_recorded_flight_tracks(callsign=callsign, day=trackDay); tracks = found["tracks"]; trackSearched = True; }
        except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def chooseTrack(value: any) -> None {
        busy = True; operation = "save"; error = "";
        try {
            savedResult = await save_trip_flight_track(trip_id=trip_id, item_id=item.id, title=item.title, location=item.location,
                departure_date=item.date, callsign=callsign, day=trackDay, track_id=value["id"] if value else "", expected_revision=saved.get("revision", 0));
            await onSaved();
            if savedResult["track"] { onTrack(savedResult["track"]); }
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    <div className="map-flight-search">
        {(<div className="map-saved-flight"><strong>{saved["track"]["callsign"] + " · Saved recorded track"}</strong>
            <p>Available whenever you open this trip.</p><button type="button" className="map-primary" disabled={busy} onClick={lambda { onTrack(saved["track"]); }}>Show saved track</button>
            <button type="button" className="map-secondary" disabled={busy} onClick={lambda { chooseTrack(None); }}>Remove saved track</button></div>) if saved.get("track") else None}
        <h4>Find the actual flight</h4>
        <form onSubmit={search}><div className="form-pair">
            <label>Flight number<input value={ident} placeholder="CA1210" maxLength={12} required={True} disabled={busy}
                onChange={lambda (e: ChangeEvent) { ident = e.target.value; result = None; }}/></label>
            <label>Departure date<input type="date" value={flightDate} required={True} disabled={busy}
                onChange={lambda (e: ChangeEvent) { flightDate = e.target.value; result = None; }}/></label>
            </div><button type="submit" className="map-primary" disabled={busy}>{"Searching the web…" if busy and operation == "web" else "Search flight & track"}</button></form>
        <p className="map-muted">Uses the OpenAI key in your travel assistant. Search availability depends on public flight records.</p>
        {(<p role="alert" className="map-inline-error">{error}</p>) if error else None}
        {(<div className="map-flight-result" role="status"><strong>{result["ident"] + " · " + result["departure_date"]}</strong>
            <p>{result["answer"]}</p><small>{"Checked " + result["checked_at"]}</small>
            {[<a key={source["url"]} href={source["url"]} target="_blank" rel="noopener noreferrer">{source["title"] + " ↗"}</a> for source in result["sources"]]}
            <p className="map-muted">Use the ICAO callsign from the flight record below to look up recorded coordinates.</p>
        </div>) if result else None}
        <form onSubmit={findTracks}><h4>Recorded ADS-B track</h4><p className="map-muted">Choose the UTC date of the first recorded position. Check the registration and times before displaying a match.</p>
            <div className="form-pair"><label>ICAO callsign<input value={callsign} placeholder="CCA1210" required={True} maxLength={8} disabled={busy}
                onChange={lambda (e: ChangeEvent) { callsign = e.target.value; tracks = []; trackSearched = False; }}/></label>
                <label>Track date (UTC)<input type="date" value={trackDay} required={True} disabled={busy}
                    onChange={lambda (e: ChangeEvent) { trackDay = e.target.value; tracks = []; trackSearched = False; }}/></label></div>
            <button type="submit" className="map-secondary" disabled={busy}>{"Looking up…" if busy and operation == "track" else "Find recorded tracks"}</button>
        </form>
        {[<button type="button" className="map-list-row" key={track["id"]} disabled={busy} onClick={lambda { chooseTrack(track); }}><span>
            <strong>{track["callsign"] + " · " + track["registration"]}</strong><small>{track["start"] + " — " + track["end"]}</small><small>{"Saving…" if busy and operation == "save" else "Save & show recorded track ↗"}</small>
        </span></button> for track in tracks]}
        {(<p role="status">No recorded track found for this callsign and UTC date. Try the adjacent UTC date if the flight crossed midnight.</p>) if trackSearched and not tracks else None}
    </div>
}
