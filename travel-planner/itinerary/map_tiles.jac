"""Leaflet street map coordinates shared by accessible React overlays."""
import from "leaflet" { map, tileLayer, polyline, layerGroup }

def:pub createStreetMap(element: any, onMove: any, onError: any) -> any {
    result: any = map(element, {"zoomControl": False, "attributionControl": True,
        "scrollWheelZoom": False, "worldCopyJump": True, "minZoom": 2, "maxZoom": 19});
    result.setView([25, 0], 2);
    tiles: any = tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        "maxZoom": 19, "attribution": '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors'});
    tiles.on("tileerror", lambda { onError(True); });
    tiles.on("tileload", lambda { onError(False); });
    tiles.addTo(result);
    result.on("move zoom resize", onMove);
    return result;
}

def:pub fitStreetMap(map: any, points: any, city: bool = False) -> None {
    if not map or not points { return; }
    anchor = points[0]["lon"];
    coords = [[p["lat"], anchor + ((p["lon"] - anchor + 540) % 360) - 180] for p in points];
    map.fitBounds(coords, {"paddingTopLeft": [75, 110], "paddingBottomRight": [75, 80],
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
    lon = route["from"]["lon"];
    delta = ((route["to"]["lon"] - lon + 540) % 360) - 180;
    return {"marker": streetPoint(map, {"lat": (route["from"]["lat"] + route["to"]["lat"]) / 2,
        "lon": lon + delta / 2})};
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
