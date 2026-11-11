"""The map workspace for saved itineraries, transport and disruptions."""
import from server.main { load_trip_map }
import from itinerary.actions { focusItineraryControl }
import from itinerary.map_land { landPolygons }
import from itinerary.map_geometry { mapViewport, screenPoint, screenRoute, drawTripMap }
import from itinerary.map_scene { mapScene }
import from itinerary.map_route_editor { MapRouteEditor }
import from itinerary.presentation { planTitle, moneyLabel, shiftLabel }
import from itinerary.review { itinerarySchedule }

def markerStyle(point: any) -> any {
    return {"left": str(point["x"]) + "px", "top": str(point["y"]) + "px"};
}

def inside(point: any, width: int, height: int) -> bool {
    return 18 < point["x"] < width - 18 and 63 < point["y"] < height - 55;
}

def toneLabel(tone: str) -> str {
    return "Disruption" if tone == "disruption" else "Needs confirmation" if tone == "check" else
        "Plan B preview" if tone == "preview" else "Planned";
}

def firstOrNone(matches: any) -> any {
    return matches[0] if len(matches) > 0 else None;
}

def savedLocationApplies(item: any, preview: any) -> bool {
    if not preview or item.id not in preview["changes"] { return True; }
    return preview["changes"][item.id]["venue"] == item.location;
}

def:pub TripMap(trip: any, items: any, revision: int, preview: any, disabled: bool,
    onReview: any, onPlanB: any, onStop: any, onTimeline: any, onSample: any) -> JsxElement {
    has data: any = {}, loadError: str = "", width: int = 800, height: int = 530,
        zoom: float = 1.0, panX: float = 0.0, panY: float = 0.0, popup: any = None,
        popupTab: str = "plan", editing: bool = False,
        land: Ref[any] = Ref(None), observer: Ref[any] = Ref(None), interval: Ref[int] = Ref(0),
        alive: Ref[bool] = Ref(False), sequence: Ref[int] = Ref(0), drag: Ref[any] = Ref(None),
        onWindowFocus: Ref[any] = Ref(None);
    browser: any = window;
    stageId = "trip-map-" + trip.id;
    closeId = stageId + "-close";
    async def reload -> None {
        sequence.current += 1; token = sequence.current;
        try {
            fresh = await load_trip_map(trip_id=trip.id);
            if alive.current and sequence.current == token { data = fresh; loadError = ""; }
        } except Exception {
            if alive.current and sequence.current == token {
                data = {}; loadError = "Could not refresh map details.";
            }
        }
    }
    def resize -> None {
        stage: any = document.getElementById(stageId);
        if stage { width = stage.clientWidth; height = stage.clientHeight; }
    }
    def resetView -> None { zoom = 1.0; panX = 0.0; panY = 0.0; }
    def closePopup(restore: bool = True) -> None {
        if popup is None { return; }
        control = popup["control"]; popup = None; editing = False;
        if restore { window.requestAnimationFrame(lambda { focusItineraryControl(control); }); }
    }
    def openPopup(kind: str, id: str, control: str) -> None {
        popup = {"kind": kind, "id": id, "control": control}; popupTab = "plan"; editing = False;
    }
    def startPan(e: any) -> None {
        if e.button != 0 { return; }
        drag.current = {"x": e.clientX, "y": e.clientY, "left": panX, "top": panY, "moved": False};
        e.currentTarget.setPointerCapture(e.pointerId);
    }
    def movePan(e: any) -> None {
        if drag.current is None { return; }
        dx = e.clientX - drag.current["x"]; dy = e.clientY - drag.current["y"];
        if abs(dx) + abs(dy) < 4 and not drag.current["moved"] { return; }
        drag.current["moved"] = True;
        panX = min(width * 3.0, max(-width * 3.0, drag.current["left"] + dx));
        panY = min(height * 3.0, max(-height * 3.0, drag.current["top"] + dy));
    }
    def endPan -> None {
        if drag.current is not None and not drag.current["moved"] { closePopup(False); }
        drag.current = None;
    }

    can with entry {
        alive.current = True; land.current = browser.JSON.parse(landPolygons());
        resize();
        observer.current = new(browser.ResizeObserver, resize);
        observer.current.observe(document.getElementById(stageId));
        onWindowFocus.current = lambda { reload(); };
        window.addEventListener("focus", onWindowFocus.current);
        interval.current = window.setInterval(lambda { if not browser.document.hidden { reload(); } }, 45000);
    }
    can with exit {
        alive.current = False; sequence.current += 1;
        if observer.current { observer.current.disconnect(); }
        browser.clearInterval(interval.current);
        window.removeEventListener("focus", onWindowFocus.current);
    }
    can with [items, revision] entry { reload(); }
    can with [popup] entry { if popup is not None { focusItineraryControl(closeId); } }

    scene = mapScene(trip.destination, items, data, preview);
    cities = scene["cities"]; pins = scene["pins"]; routeData = scene["routes"];
    mappedRoutes = [{"id": item.id, "item": item, "route": routeData[item.id]["route"], "tone": scene["tones"][item.id]}
        for item in items if item.id in routeData and routeData[item.id]["route"] is not None and
            savedLocationApplies(item, preview) and (not preview or item.id not in preview["changes"] or
                preview["changes"][item.id]["title"] == item.title)];
    pointList = [city["point"] for city in cities] + [pins[item.id] for item in items if item.id in pins];
    view = mapViewport(pointList, width, height, zoom, panX, panY);
    cityMarkers = [{"data": city, "screen": screenPoint(city["point"], view)} for city in cities];
    routeMarkers = [{**record, "curve": screenRoute(record["route"], view)} for record in mappedRoutes];
    placeMarkers = [{"item": item, "screen": screenPoint(pins[item.id], view), "tone": scene["tones"][item.id]}
        for item in items if item.id in pins and savedLocationApplies(item, preview) and
            not any(record["id"] == item.id for record in mappedRoutes)];
    visiblePlaces = [record for record in placeMarkers if inside(record["screen"], width, height) and
        not any(record["item"].id in city["data"]["items"] and
            abs(city["screen"]["x"] - record["screen"]["x"]) + abs(city["screen"]["y"] - record["screen"]["y"]) < 38
            for city in cityMarkers)];
    activeId = popup["id"] if popup else "";
    activeKind = popup["kind"] if popup else "";
    can with [width, height, zoom, panX, panY, data, items, preview, activeId] entry {
        canvas: any = document.getElementById(stageId + "-canvas");
        if canvas and land.current is not None { drawTripMap(canvas, land.current, view, routeMarkers, width, height, activeId); }
    }
    selectedCity = firstOrNone([city for city in cityMarkers if city["data"]["id"] == activeId and activeKind == "city"]);
    selectedRoute = firstOrNone([route for route in routeMarkers if route["id"] == activeId and activeKind == "route"]);
    selectedItem = firstOrNone([item for item in items if item.id == activeId and activeKind in ["route", "place"]]);
    selectedPlace = firstOrNone([record for record in placeMarkers if record["item"].id == activeId and activeKind == "place"]);
    ids = selectedCity["data"]["items"] if selectedCity is not None else [activeId] if selectedItem is not None else [];
    selectedStops = [item for item in items if item.id in ids];
    alerts = scene["alerts"];
    relatedAlerts = [record for record in alerts if any(id in record["affected"] for id in ids)];
    relatedPlans = [plan for plan in data.get("plans", []) if any(change["replaces_id"] in ids for change in plan["replacements"])];
    activeAlerts = [record for record in alerts if record["risk"]["status"] == "flagged"];
    anchor = selectedCity["screen"] if selectedCity is not None else selectedRoute["curve"]["marker"] if selectedRoute is not None
        else selectedPlace["screen"] if selectedPlace is not None else {"x": width - 80, "y": 72};
    popupWidth = min(width - 24.0, 346.0);
    popupLeft = anchor["x"] + 23.0 if anchor["x"] + popupWidth + 35.0 <= width else anchor["x"] - popupWidth - 23.0;
    popupTop = max(68.0, min(anchor["y"] - 52.0, height - 342.0));
    panelStyle = {"left": str(max(12.0, min(width - popupWidth - 12.0, popupLeft))) + "px",
        "top": str(popupTop) + "px"};
    dialogTitle = selectedCity["data"]["point"]["label"] if selectedCity is not None else selectedItem.title if selectedItem is not None
        else "Trip alerts" if activeKind == "alerts" else "Map details";

    def reviewStop(id: str, reason: str) -> None {
        control = popup["control"]; closePopup(False); onReview(id, reason, control);
    }
    def showAlert(record: any) -> None {
        risk = record["risk"]; control = popup["control"];
        closePopup(False);
        onPlanB(risk["node_ids"][0], [risk["id"]], [], "", control);
    }
    def showPlan(option: any) -> None {
        control = popup["control"];
        compatible = [plan for plan in relatedPlans if len(plan["risk_ids"]) == len(option["risk_ids"]) and
            all(id in option["risk_ids"] for id in plan["risk_ids"])];
        closePopup(False);
        onPlanB(option["replacements"][0]["replaces_id"], option["risk_ids"], compatible, option["id"], control);
    }
    def jumpTo(id: str) -> None { closePopup(False); onStop(id); }
    def closeEditor -> None {
        editing = False;
        window.requestAnimationFrame(lambda { focusItineraryControl(closeId); });
    }
    async def routeSaved -> None { await reload(); resetView(); closeEditor(); }

    <section className="trip-map" id={stageId} aria-label="Trip map" data-preview={bool(preview and preview["choice"])}
        onKeyDown={lambda (e: any) { if e.key == "Escape" and popup { e.stopPropagation(); closePopup(); } }}>
        <canvas className="map-canvas" id={stageId + "-canvas"} aria-hidden="true"
            onPointerDown={startPan} onPointerMove={movePan} onPointerUp={endPan}
            onPointerCancel={lambda { drag.current = None; }}/>
        <header className="map-top">
            <div className="map-heading"><span aria-hidden="true">⌖</span><div><h2>Trip map</h2>
                <p>{str(len(cities)) + (" city" if len(cities) == 1 else " cities") + " · " +
                    str(len(mappedRoutes)) + (" route" if len(mappedRoutes) == 1 else " routes")}</p></div></div>
            <div className="map-tools">
                {(<button type="button" id={stageId + "-alerts"} className="map-alert-button" data-active={len(activeAlerts) > 0}
                    aria-expanded={activeKind == "alerts"}
                    onClick={lambda { openPopup("alerts", "", stageId + "-alerts"); }}>
                    {str(len(alerts)) + (" alert" if len(alerts) == 1 else " alerts")}</button>) if len(alerts) > 0 else None}
                <button type="button" id={stageId + "-details"} aria-expanded={activeKind == "details"}
                    onClick={lambda { openPopup("details", "", stageId + "-details"); }}>Map details</button>
            </div>
        </header>
        {[<button type="button" className="map-city-pin" key={record["data"]["id"]} style={markerStyle(record["screen"])}
            id={stageId + "-city-" + record["data"]["id"]} data-tone={record["data"]["tone"]}
            aria-label={"Explore " + record["data"]["point"]["label"]}
            aria-expanded={activeKind == "city" and activeId == record["data"]["id"]}
            onClick={lambda { openPopup("city", record["data"]["id"], stageId + "-city-" + record["data"]["id"]); }}>
            <span className="map-pin-core" aria-hidden="true"/><span className="map-city-label">{record["data"]["point"]["label"]}</span>
        </button> for record in cityMarkers if inside(record["screen"], width, height)]}
        {[<button type="button" className="map-route-pin" key={record["id"]} style={markerStyle(record["curve"]["marker"])}
            id={stageId + "-route-" + record["id"]} data-tone={record["tone"]}
            aria-label={("Flight route: " if record["route"]["kind"] == "flight" else "Ground route: ") + record["item"].title}
            aria-expanded={activeKind == "route" and activeId == record["id"]}
            onClick={lambda { openPopup("route", record["id"], stageId + "-route-" + record["id"]); }}>
            <span className="map-route-symbol" aria-hidden="true">{ "✈" if record["route"]["kind"] == "flight" else "↗"}</span>
            {(<span className="map-route-shift">{shiftLabel(preview["time_changes"][record["id"]])}</span>)
                if preview and record["id"] in preview["time_changes"] else None}
        </button> for record in routeMarkers if inside(record["curve"]["marker"], width, height)]}
        {[<button type="button" className="map-place-pin" key={record["item"].id} style={markerStyle(record["screen"])}
            id={stageId + "-place-" + record["item"].id} data-tone={record["tone"]}
            aria-label={"Explore stop " + record["item"].title} aria-expanded={activeKind == "place" and activeId == record["item"].id}
            onClick={lambda { openPopup("place", record["item"].id, stageId + "-place-" + record["item"].id); }}>
            <span aria-hidden="true">•</span>
        </button> for record in visiblePlaces]}
        {(<div className="map-empty"><strong>{trip.destination}</strong>
            <p>Add route endpoints or coordinates to put this trip on the map.</p>
            <button type="button" className="map-primary" onClick={lambda { openPopup("details", "", stageId + "-details"); }}>Add map details</button>
        </div>) if len(pointList) == 0 and popup is None else None}
        {(<div className="map-load-error" role="status">{loadError}
            <button type="button" onClick={reload}>Retry</button></div>) if loadError else None}
        {(<div className="map-preview-tag" role="status">Plan B preview · Saved itinerary unchanged</div>) if preview and preview["choice"] else None}
        <div className="map-zoom" role="group" aria-label="Map view controls">
            <button type="button" aria-label="Zoom in" disabled={zoom >= 4} onClick={lambda { zoom = min(4.0, zoom * 1.35); }}>+</button>
            <button type="button" aria-label="Zoom out" disabled={zoom <= 0.55} onClick={lambda { zoom = max(0.55, zoom / 1.35); }}>−</button>
            <button type="button" aria-label="Fit all trip points" onClick={resetView}>⤢</button>
        </div>
        <footer className="map-footer">
            <div className="map-legend"><span data-tone="planned">Planned</span>
                {(<span data-tone="disruption">Disruption</span>) if len(activeAlerts) > 0 else None}
                {(<span data-tone="check">Needs confirmation</span>) if len(alerts) > len(activeAlerts) else None}
                {(<span data-tone="preview">Plan B preview</span>) if preview and preview["choice"] else None}
            </div>
            <div className="map-footer-links"><small>Natural Earth</small><button type="button" onClick={onTimeline}>Timeline ↓</button></div>
        </footer>
        {(<section className="map-popup" style={panelStyle} role="dialog" aria-label={dialogTitle} data-kind={activeKind}>
            <header className="map-popup-heading">
                <div><p>{ "CITY" if activeKind == "city" else "SAVED TRANSPORT" if activeKind == "route" else
                    "ITINERARY STOP" if activeKind == "place" else "TRIP MAP"}</p><h3>{dialogTitle}</h3></div>
                <button type="button" id={closeId} aria-label="Close map details" onClick={lambda { closePopup(); }}>×</button>
            </header>
            {(<div className="map-popup-tabs" role="group" aria-label="Map plan views">
                <button type="button" aria-pressed={popupTab == "plan"} onClick={lambda { popupTab = "plan"; }}>Saved plan</button>
                <button type="button" aria-pressed={popupTab == "backup"} onClick={lambda { popupTab = "backup"; }}>Plan B
                    {(" · " + str(len(relatedPlans))) if len(relatedPlans) > 0 else ""}</button>
            </div>) if activeKind in ["city", "route", "place"] and not editing else None}
            <div className="map-popup-content">
                {(<MapRouteEditor trip_id={trip.id} item={selectedItem} data={routeData.get(activeId, {})}
                    onSaved={routeSaved} onCancel={closeEditor}/>) if editing and selectedItem is not None else None}
                {(<div className="map-popup-stack">
                    {(<div className="map-endpoints"><strong>{selectedRoute["route"]["from"]["label"]}</strong>
                        <span aria-hidden="true">{ "✈" if selectedRoute["route"]["kind"] == "flight" else "→"}</span>
                        <strong>{selectedRoute["route"]["to"]["label"]}</strong></div>) if selectedRoute is not None else None}
                    <p>{itinerarySchedule(selectedItem.date, selectedItem.time) + " · " + selectedItem.journey.get("zone", "Saved local time")}</p>
                    {(<p>{"Arrives " + selectedItem.journey["arrival_date"] + " " + selectedItem.journey["arrival_time"] + " · " + selectedItem.journey["end_zone"]}</p>) if selectedItem.journey.get("leg_id") else None}
                    {(<p className="map-proposed-time">{"Proposed " + preview["changes"][activeId]["start"]["local"].replace("T", " ")}</p>)
                        if preview and activeId in preview["changes"] else None}
                    {(<p>{ "Booking reference " + selectedItem.reference}</p>) if selectedItem.reference else None}
                    <p className="map-muted">{ "Planned path · approximate" if selectedRoute is not None else "Add endpoints to draw this route."}</p>
                    {(<div className="map-state-pill" data-tone={scene["tones"][activeId]}>{toneLabel(scene["tones"][activeId])}</div>)}
                    {(<p className="map-risk-copy">{relatedAlerts[0]["risk"]["summary"]}</p>) if len(relatedAlerts) > 0 else None}
                    <div className="map-popup-actions">
                        <button type="button" className="map-primary" disabled={disabled} onClick={lambda { reviewStop(activeId, "timing"); }}>Report a delay</button>
                        {(<button type="button" className="map-secondary" disabled={disabled} onClick={lambda { editing = True; }}>
                            { "Edit route" if selectedRoute is not None else "Add route"}</button>) if not selectedItem.journey.get("leg_id") else <p className="map-muted">Edit cities in the Route tab and transport times in the itinerary.</p>}
                    </div>
                </div>) if activeKind == "route" and selectedItem is not None and popupTab == "plan" and not editing else None}
                {(<div className="map-popup-stack">
                    {(<p className="map-risk-copy">{str(len(relatedAlerts)) + (" alert on this plan" if len(relatedAlerts) == 1 else " alerts on this plan")}</p>) if len(relatedAlerts) > 0 else None}
                    {(<p className="map-muted">No stops are associated with this city yet.</p>) if len(selectedStops) == 0 else None}
                    {[<button type="button" className="map-list-row" key={item.id} onClick={lambda { jumpTo(item.id); }}>
                        <span className="map-status-dot" data-tone={scene["tones"][item.id]} aria-hidden="true"/>
                        <span><strong>{item.title}</strong><small>{itinerarySchedule(item.date, item.time)}</small></span><span aria-hidden="true">↗</span>
                    </button> for item in selectedStops]}
                </div>) if activeKind in ["city", "place"] and popupTab == "plan" else None}
                {(<div className="map-popup-stack">
                    {(<p className="map-muted">No current backup options. Choose a recorded alert to find alternatives.</p>) if len(relatedPlans) == 0 and len(relatedAlerts) > 0 else None}
                    {(<p className="map-muted">No current backup options for these stops.</p>) if len(relatedPlans) == 0 and len(relatedAlerts) == 0 else None}
                    {[<button type="button" className="map-list-row map-option" key={option["id"]} disabled={disabled}
                        onClick={lambda { showPlan(option); }}>
                        <span><strong>{planTitle(option)}</strong><small>{moneyLabel(option["comparison"]["projected_total_minor"], trip.currency) +
                            (" · Ready for review" if option["selectable"] else " · Needs confirmation")}</small></span><span aria-hidden="true">→</span>
                    </button> for option in relatedPlans[:5]]}
                    {(<button type="button" className="map-secondary" disabled={disabled}
                        onClick={lambda { reviewStop(selectedStops[0].id, ""); }}>Review a change</button>) if len(relatedAlerts) == 0 and len(selectedStops) > 0 else None}
                </div>) if activeKind in ["city", "route", "place"] and popupTab == "backup" else None}
                {[<div className="map-alert-row" key={record["risk"]["id"]} data-tone={ "disruption" if record["risk"]["status"] == "flagged" else "check"}>
                    <strong>{record["risk"]["summary"]}</strong>
                    <small>{str(len(record["affected"])) + (" stop to check" if len(record["affected"]) == 1 else " stops to check")}</small>
                    <button type="button" className="map-secondary" disabled={disabled} onClick={lambda { showAlert(record); }}>Review alternatives →</button>
                </div> for record in (alerts if activeKind == "alerts" else relatedAlerts if popupTab == "backup" else [])
                    if not editing]}
                {(<div className="map-popup-stack">
                    {(<p className="map-muted">Choose a transport item to set route endpoints, or a stop to open its location details.</p>)}
                    {(<p className="map-muted">Add an itinerary item to get started.</p>) if len(items) == 0 else None}
                    {[<button type="button" className="map-list-row" key={item.id} disabled={disabled} onClick={lambda {
                        if item.category == "transport" { openPopup("route", item.id, stageId + "-details"); }
                        else { jumpTo(item.id); }
                    }}><span><strong>{item.title}</strong><small>{ "Flight or ground route" if item.category == "transport"
                        else "Itinerary stop"}</small></span><span aria-hidden="true">↗</span></button> for item in items]}
                    <button type="button" className="map-secondary" disabled={disabled} onClick={onSample}>Explore sample trip</button>
                </div>) if activeKind == "details" else None}
            </div>
        </section>) if popup is not None else None}
    </section>
}
