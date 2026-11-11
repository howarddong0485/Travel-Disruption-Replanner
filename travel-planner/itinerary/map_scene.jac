"""Group mapped routes, stops and risk dependencies for the workspace."""
import from itinerary.map_geometry { cityPoint }
import from itinerary.presentation { affectedItemIds }

def cityId(point: any) -> str {
    return point["label"].strip().lower();
}

def:pub mapScene(destination: str, items: any, data: any, preview: any) -> any {
    home = cityPoint(destination);
    cities: any = {};
    if home is not None { cities[cityId(home)] = home; }
    routes: any = {**data.get("routes", {})};
    pins: any = data.get("pins", {});
    groups: any = {};
    journey = data.get("journey");
    if journey {
        points: any = {};
        locations = [{**journey["origin"], "id": "origin"}] + journey["stops"];
        if journey["return_to"] { locations.append({**journey["return_to"], "id": "return"}); }
        for location in locations {
            point = {"label": location["city"], "lat": location["lat"], "lon": location["lon"]}
                if location.get("lat") is not None else cityPoint(location["city"]);
            if point is not None { points[location["id"]] = point; cities[cityId(point)] = point; }
        }
        for item in items {
            detail = item.journey;
            if not detail { continue; }
            leg = [leg for leg in journey["legs"] if leg["id"] == detail.get("leg_id")];
            if len(leg) > 0 and leg[0]["from_id"] in points and leg[0]["to_id"] in points {
                routes[item.id] = {"revision": routes.get(item.id, {}).get("revision", 0), "route": {
                    "from": points[leg[0]["from_id"]], "to": points[leg[0]["to_id"]], "kind": "flight" if leg[0]["mode"] == "flight" else "ground"}};
            } elif detail.get("stop_id") in points { groups[item.id] = [cityId(points[detail["stop_id"]])]; }
        }
    }
    for item in items {
        route = routes.get(item.id, {}).get("route");
        if route is not None {
            start = cityId(route["from"]); end = cityId(route["to"]);
            cities[start] = route["from"]; cities[end] = route["to"];
            groups[item.id] = [start, end];
        }
    }
    browser: any = window; keys = browser.Object.keys(cities);
    for item in items {
        if item.id in groups { continue; }
        pin = pins.get(item.id);
        near = "";
        distance = 1.0;
        if pin is not None {
            for key in keys {
                city = cities[key];
                separation = abs(city["lat"] - pin["lat"]) + abs(city["lon"] - pin["lon"]);
                if separation < distance { near = key; distance = separation; }
            }
        } elif home is not None { near = cityId(home); }
        groups[item.id] = [near] if near else [];
    }
    edges = {"items": [{"id": item.id} for item in items], "dependencies": data.get("dependencies", [])};
    alerts: any = [];
    for risk in data.get("risks", []) {
        if risk["status"] not in ["flagged", "unresolved"] or risk.get("category") == "traveler_change" { continue; }
        affected: list[str] = [];
        for id in risk["node_ids"] {
            for related in affectedItemIds(edges, id) {
                if related not in affected { affected.append(related); }
            }
        }
        if len(affected) > 0 { alerts.append({"risk": risk, "affected": affected}); }
    }
    tones: any = {};
    for item in items {
        if preview and item.id in preview["changes"] { tones[item.id] = "preview"; }
        elif any(alert["risk"]["status"] == "flagged" and item.id in alert["affected"] for alert in alerts) {
            tones[item.id] = "disruption";
        } elif any(item.id in alert["affected"] for alert in alerts) or (preview and item.id in preview["affected"]) {
            tones[item.id] = "check";
        } else { tones[item.id] = "planned"; }
    }
    cityList: any = [];
    for key in keys {
        ids = [item.id for item in items if key in groups[item.id]];
        tone = "planned";
        for value in ["disruption", "preview", "check"] {
            if any(tones[id] == value for id in ids) { tone = value; break; }
        }
        cityList.append({"id": key, "point": cities[key], "items": ids, "tone": tone});
    }
    return {"cities": cityList, "routes": routes, "pins": pins, "tones": tones, "alerts": alerts};
}
