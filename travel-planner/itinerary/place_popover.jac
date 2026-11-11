"""Place preview with optional user-supplied photo and map pin."""
import from server.main { get_place_details, save_place_details }
import from itinerary.actions { focusItineraryControl }
import from itinerary.places { itineraryMapLink }
import from journey.display { journeyCity }

def:pub PlacePreview(trip_id: str, item: any, destination: str, control: str,
    onReview: any, onSelect: any, onSaved: any) -> JsxElement {
    has data: any = None, failure: str = "", busy: bool = False, photoFailed: bool = False,
        latitude: str = "", longitude: str = "", photo: str = "", credit: str = "",
        alive: Ref[bool] = Ref(True);
    def fill(fresh: any) -> None {
        data = fresh; latitude = str(fresh["latitude"]) if fresh["latitude"] is not None else "";
        longitude = str(fresh["longitude"]) if fresh["longitude"] is not None else "";
        photo = fresh["photo_url"]; credit = fresh["photo_source"]; photoFailed = False;
    }
    async def load -> None {
        failure = "";
        try {
            fresh = await get_place_details(trip_id=trip_id, item_id=item.id);
            if alive.current {
                if fresh["location"] != item.location {
                    data = None; failure = "This address changed. Refresh the trip before opening its place details.";
                } else { fill(fresh); }
            }
        } except Exception { if alive.current { failure = "Could not load this place. Reload its details."; } }
    }
    async def save(e: FormEvent) -> None {
        e.preventDefault(); if busy or data is None { return; }
        busy = True; failure = "";
        try {
            payload = {"latitude": float(latitude) if latitude.strip() else None, "longitude": float(longitude) if longitude.strip() else None,
                "photo_url": photo, "photo_source": credit};
            fresh = await save_place_details(trip_id=trip_id, item_id=item.id, location=data["location"],
                expected_revision=data["revision"], payload=payload);
            if alive.current { fill(fresh); onSaved(); }
        } except Exception as exc { if alive.current { failure = str(exc); } }
        finally { if alive.current { busy = False; } }
    }
    can with entry { load(); }
    can with exit { alive.current = False; }
    map = "";
    if data and data["latitude"] is not None {
        lat = data["latitude"]; lon = data["longitude"];
        map = "https://www.openstreetmap.org/export/embed.html?bbox=" +
            str(max(-180, lon - 0.01)) + "," + str(max(-90, lat - 0.007)) + "," +
            str(min(180, lon + 0.01)) + "," + str(min(90, lat + 0.007)) + "&layer=mapnik&marker=" + str(lat) + "," + str(lon);
    }
    <div className="place-preview-content">
        <h3>{item.title}</h3><p>{item.location if not item.location.startswith("fixture:") else "Sample location"}</p>
        {(<figure className="place-photo"><img src={data["photo_url"]} alt={item.title} referrerPolicy="no-referrer"
            onError={lambda { photoFailed = True; }}/><figcaption>{data["photo_source"]}</figcaption></figure>)
            if data and data["photo_url"] and not photoFailed else
            (<p className="place-media-empty">{ "Photo could not be loaded." if photoFailed else "Add a photo to recognize this stop at a glance."}</p>)}
        {(<iframe className="place-map-preview" title={"Map preview for " + item.title} src={map}
            loading="lazy" referrerPolicy="no-referrer" sandbox="allow-scripts allow-same-origin allow-popups"/>) if map else
            (<p className="place-media-empty">Add coordinates to preview the map here.</p>)}
        <div className="place-suggestions">
            {(<a className="itinerary-chip" href={itineraryMapLink(item.location, journeyCity(item, destination))} target="_blank" rel="noopener noreferrer">Open map ↗</a>) if item.location and not item.location.startswith("fixture:") else None}
            <button type="button" className="itinerary-chip" onClick={lambda { onSelect(item.id); }}>Show in Places</button>
            <button type="button" className="itinerary-chip" onClick={lambda { onReview(item.id, "", control); }}>Review this stop</button>
            {(<button type="button" className="itinerary-chip" onClick={lambda { onReview(item.id, "weather", control); }}>Find indoor alternatives</button>) if item.category == "activity" else None}
            {(<button type="button" className="itinerary-chip" onClick={lambda { onReview(item.id, "timing", control); }}>Find a later dining time</button>) if item.category == "food" else None}
        </div>
        {(<p className="alert error" role="alert">{failure}<button type="button" className="text-button" onClick={load}>Reload details</button></p>) if failure else None}
        {(<details className="place-attachments"><summary>Add or edit photo and map pin</summary>
            <p>Use a photo you have permission to display. These details help identify the place.</p>
            <form onSubmit={save}>
                <label>Photo URL<input type="url" value={photo} placeholder="https://…" maxLength={2000}
                    disabled={busy} onChange={lambda (e: ChangeEvent) { photo = e.target.value; }}/></label>
                <label>Photo source or photographer<input value={credit} maxLength={400} required={bool(photo)}
                    disabled={busy} onChange={lambda (e: ChangeEvent) { credit = e.target.value; }}/></label>
                <div className="form-pair">
                    <label>Latitude<input type="number" min="-90" max="90" step="any" value={latitude} required={bool(longitude)}
                        disabled={busy} onChange={lambda (e: ChangeEvent) { latitude = e.target.value; }}/></label>
                    <label>Longitude<input type="number" min="-180" max="180" step="any" value={longitude} required={bool(latitude)}
                        disabled={busy} onChange={lambda (e: ChangeEvent) { longitude = e.target.value; }}/></label>
                </div>
                <button type="submit" className="itinerary-chip" disabled={busy}>{"Saving…" if busy else "Save place details"}</button>
            </form>
        </details>) if data else None}
    </div>
}

def:pub PlacePopover(trip_id: str, item: any, destination: str, disabled: bool,
    onReview: any, onSelect: any, onSaved: any) -> JsxElement {
    has open: bool = False, placement: any = {}, outside: Ref[any] = Ref(None);
    control = "place-details-" + item.id;
    def close -> None { open = False; focusItineraryControl(control); }
    def toggle -> None {
        if open { close(); return; }
        browser: any = window; trigger: any = document.getElementById(control);
        rect = trigger.getBoundingClientRect(); width = min(350, browser.innerWidth - 24);
        height = min(620, browser.innerHeight * 0.82);
        top = rect.bottom + 8 if rect.bottom + height + 8 <= browser.innerHeight else max(12, rect.top - height - 8);
        placement = {"left": str(max(12, min(rect.left, browser.innerWidth - width - 12))) + "px",
            "top": str(top) + "px", "bottom": "auto", "right": "auto", "width": str(width) + "px",
            "maxHeight": str(browser.innerHeight - top - 12) + "px"};
        open = True;
    }
    def review(id: str, reason: str, source: str) -> None { open = False; onReview(id, reason, source); }
    can with [open] entry {
        if open { focusItineraryControl(control + "-close"); }
    }
    can with entry {
        outside.current = lambda (e: any) {
            anchor: any = document.getElementById(control + "-anchor");
            if anchor and not anchor.contains(e.target) { open = False; }
        };
        window.addEventListener("pointerdown", outside.current);
    }
    can with exit { window.removeEventListener("pointerdown", outside.current); }
    <div id={control + "-anchor"} className="place-popover-anchor" onBlur={lambda (e: any) {
        if e.relatedTarget and not e.currentTarget.contains(e.relatedTarget) { open = False; }
    }} onKeyDown={lambda (e: any) {
        if open and e.key == "Escape" { e.stopPropagation(); close(); }
    }}>
        <button type="button" id={control} className="text-button place-detail-button" disabled={disabled}
            aria-label={"Place details for " + item.title} aria-expanded={open} aria-controls={control + "-popup"}
            onClick={toggle}>Place details</button>
        {(<div id={control + "-popup"} className="place-popover" style={placement} role="dialog" aria-modal={False} aria-label={"Details for " + item.title}>
            <button type="button" id={control + "-close"} className="itinerary-chip place-popover-close"
                aria-label="Close place details" onClick={close}>×</button>
            <PlacePreview key={item.id + item.location} trip_id={trip_id} item={item} destination={destination}
                control={control} onReview={review} onSelect={lambda (id: str) { open = False; onSelect(id); }} onSaved={onSaved}/>
        </div>) if open else None}
    </div>
}
