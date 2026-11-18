"""Read-only map snapshots for saved trips, pending drafts and empty trip routes."""
import from itinerary.city_points { cityPoint }

def:pub routePath(curve: any) -> str {
    return "M " + str(curve["start"]["x"]) + " " + str(curve["start"]["y"]) + " Q " +
        str(curve["control"]["x"]) + " " + str(curve["control"]["y"]) + " " +
        str(curve["end"]["x"]) + " " + str(curve["end"]["y"]);
}

def endpointFor(place: any, city: str, known: any) -> any {
    base = place if place and place.get("city", "").strip().lower() == city.strip().lower() else {};
    if base.get("lat") is not None and base.get("lon") is not None { return {**base, "city": city}; }
    point = cityPoint(city, known);
    return {**base, "city": city, "lat": point["lat"] if point else None, "lon": point["lon"] if point else None};
}

def completeMapRoute(trip: any, supplied: any, known: any) -> any {
    source = supplied or {};
    savedOrigin = source.get("origin") or {};
    departure = trip.departure_location or savedOrigin.get("city") or "";
    returning = trip.return_location or departure;
    origin = endpointFor(source.get("origin"), departure, known);
    returnPoint = endpointFor(source.get("return_to"), returning, known);
    if returning == departure { returnPoint = {**origin}; }
    stops = [endpointFor(stop, str(stop["city"]), known) for stop in source.get("stops", [])];
    if len(stops) == 0 { stops.append({**endpointFor(None, trip.destination, known), "id": "destination"}); }
    order: any = ["origin"] if departure else [];
    for stop in stops { order.append(stop["id"]); }
    if returning { order.append("return"); }
    legs: any = [];
    for index in range(len(order) - 1) {
        left = order[index]; right = order[index + 1];
        matches = [leg for leg in source.get("legs", []) if leg["from_id"] == left and leg["to_id"] == right];
        leg = {**matches[0]} if len(matches) > 0 else {"id": left + ":" + right, "from_id": left, "to_id": right,
            "mode": "flight" if left == "origin" or right == "return" else "train"};
        legs.append(leg);
    }
    return {**source, "origin": origin, "return_to": returnPoint, "stops": stops, "legs": legs};
}

def:pub mapOverview(trip: any, saved: any, data: any, journey: any, draft: any) -> any {
    supplied = draft.get("journey") if draft and draft.get("journey") else journey or data.get("journey");
    route = completeMapRoute(trip, supplied, data.get("location_points", {}));
    result: any = [item for item in saved];
    changed: any = []; unknownPrices: any = [];
    flights: any = {**data.get("flights", {})};
    pins: any = {**data.get("pins", {})};
    routes: any = {**data.get("routes", {})};
    if draft {
        for change in draft.get("changes", []) {
            after = change.get("after");
            if not after { continue; }
            id = after.get("id") or "draft-" + str(len(changed));
            result = [item for item in result if item.id != change.get("item_id") and item.id != id];
            item = {"reference": "", "notes": "", "location": "", "time": "", "journey": {}, **after, "id": id};
            result.append(item); changed.append(id);
            if change.get("price_unknown") { unknownPrices.append(id); }
            # A changed stop must not keep a saved location or flight belonging to its old schedule.
            pins[id] = None; routes[id] = {"route": None, "revision": 0}; flights[id] = None;
            if after.get("flight", {}).get("source_url") { flights[id] = after["flight"]; }
        }
    }
    pins = {key: value for (key, value) in pins.items() if value is not None};
    locations: any = [{**route["origin"], "id": "origin"}];
    for stop in route["stops"] { locations.append(stop); }
    if route.get("return_to") { locations.append({**route["return_to"], "id": "return"}); }
    byId: any = {};
    for place in locations { byId[place["id"]] = place; }
    provisional: any = [];
    for leg in route["legs"] {
        if any(item.journey.get("leg_id") == leg["id"] for item in result) { continue; }
        if leg["from_id"] not in byId or leg["to_id"] not in byId { continue; }
        id = "overview-" + leg["id"];
        start = byId[leg["from_id"]]; end = byId[leg["to_id"]];
        result.append({"id": id, "title": start["city"] + " → " + end["city"], "category": "transport",
            "date": trip.end_date if leg["to_id"] == "return" else start.get("departure_date", trip.start_date), "time": "",
            "location": start["city"] + " → " + end["city"], "notes": "Illustrative flight only. No airline, flight number, schedule, fare or availability has been verified." if leg["mode"] == "flight" else "Estimated travel route. Times and availability have not been confirmed.",
            "reference": "", "cost_cents": None, "duration_minutes": 0,
            "journey": {"leg_id": leg["id"], "mode": leg["mode"], "zone": "", "arrival_date": "", "arrival_time": "", "end_zone": ""}});
        provisional.append(id);
    }
    travel: any = [];
    for leg in route["legs"] {
        if leg["from_id"] != "origin" and leg["to_id"] != "return" { continue; }
        matching = [item for item in result if item.journey.get("leg_id") == leg["id"]];
        if len(matching) == 0 { continue; }
        item = matching[0]; start = byId[leg["from_id"]]; end = byId[leg["to_id"]];
        listing = flights.get(item.id);
        startMapped = (start.get("lat") is not None and start.get("lon") is not None) or cityPoint(start["city"]) is not None;
        endMapped = (end.get("lat") is not None and end.get("lon") is not None) or cityPoint(end["city"]) is not None;
        travel.append({"id": item.id, "direction": "Departure" if leg["from_id"] == "origin" else "Return",
            "from": start["city"], "to": end["city"], "mode": leg["mode"], "estimated": not bool(listing and listing.get("source_url")),
            "mapped": startMapped and endMapped});
    }
    unlocated: any = [];
    for place in locations {
        if place["city"] and place.get("lat") is None and cityPoint(place["city"]) is None and not any(row["city"] == place["city"] for row in unlocated) {
            ids = [item.id for item in result if item.journey.get("stop_id") == place["id"]];
            unlocated.append({"id": place["id"], "city": place["city"], "items": ids});
        }
    }
    return {"items": result, "changed": changed, "provisional": provisional, "unlocated": unlocated, "unknown_prices": unknownPrices, "travel": travel,
        "data": {**data, "journey": route, "flights": flights, "pins": pins, "routes": routes}};
}
