"""Leaflet street map coordinates shared by accessible React overlays."""
import from "leaflet" { map, tileLayer, polyline, layerGroup }

def:pub createStreetMap(element: any, onMove: any, onError: any) -> any {
    result: any = map(element, {"zoomControl": False, "attributionControl": True,
        "scrollWheelZoom": False, "worldCopyJump": True, "minZoom": 2, "maxZoom": 19});
    result.setView([25, 0], 2);
    tiles: any = tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        "referrerPolicy": "strict-origin-when-cross-origin",
        "maxZoom": 19, "attribution": '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors'});
    tiles.on("tileerror", lambda { onError(True); });
    tiles.on("tileload", lambda { onError(False); });
    tiles.addTo(result);
    result.on("move zoom resize", onMove);
    return result;
}

def:pub fitStreetMap(map: any, points: any, city: bool = False) -> None {
    if not map or len(points) == 0 { return; }
    anchor = points[0]["lon"];
    coords = [[p["lat"], anchor + ((p["lon"] - anchor + 540) % 360) - 180] for p in points];
    map.fitBounds(coords, {"paddingTopLeft": [60, 180], "paddingBottomRight": [60, 100],
        "maxZoom": 15 if city else 7, "animate": False});
}

def:pub streetPoint(map: any, point: any) -> any {
    if not map { return {"x": -1000, "y": -1000}; }
    center = map.getCenter().lng;
    longitude = center + ((point["lon"] - center + 540) % 360) - 180;
    result = map.latLngToContainerPoint([point["lat"], longitude]);
    return {"x": result.x, "y": result.y};
}

def:pub streetRoute(map: any, route: any) -> any {
    start = streetPoint(map, route["from"]); end = streetPoint(map, route["to"]);
    browser: any = window;
    dx = end["x"] - start["x"]; dy = end["y"] - start["y"];
    distance = browser.Math.hypot(dx, dy);
    lift = min(82.0, max(22.0, distance * 0.18)) if route["kind"] == "flight" and distance > 1 else 0.0;
    normalX = dy / max(1.0, distance); normalY = -dx / max(1.0, distance);
    middle = {"x": (start["x"] + end["x"]) / 2.0, "y": (start["y"] + end["y"]) / 2.0};
    return {"start": start, "end": end,
        "control": {"x": middle["x"] + normalX * lift * 2.0, "y": middle["y"] + normalY * lift * 2.0},
        "marker": {"x": middle["x"] + normalX * lift, "y": middle["y"] + normalY * lift},
        "angle": browser.Math.atan2(dy, dx) * 180.0 / browser.Math.PI};
}


def:pub drawRecordedTrack(map: any, track: any, fit: bool = True) -> any {
    group: any = layerGroup();
    points: any = [];
    for segment in track["segments"] {
        unwrapped: any = [];
        previous: float = segment[0][0] if segment else 0.0;
        for point in segment {
            longitude = previous + ((point[0] - previous + 540) % 360) - 180;
            unwrapped.append([point[1], longitude]); previous = longitude;
            points.append({"lat": point[1], "lon": longitude});
        }
        polyline(unwrapped, {"color": "#117eae", "weight": 4, "opacity": 0.9}).addTo(group);
    }
    group.addTo(map); if fit { fitStreetMap(map, points); }
    return group;
}
