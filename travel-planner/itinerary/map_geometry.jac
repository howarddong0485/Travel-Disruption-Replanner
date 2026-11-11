"""Projection, viewport and drawing for the trip map."""
def:pub cityPoint(name: str) -> any {
    cities = {
        "amsterdam": [52.37, 4.90], "ann arbor": [42.28, -83.74], "atlanta": [33.75, -84.39],
        "bangkok": [13.76, 100.50], "barcelona": [41.39, 2.17], "beijing": [39.90, 116.41],
        "berlin": [52.52, 13.41], "boston": [42.36, -71.06], "chicago": [41.88, -87.63],
        "detroit": [42.33, -83.05], "dubai": [25.20, 55.27], "hong kong": [22.32, 114.17],
        "honolulu": [21.31, -157.86], "istanbul": [41.01, 28.98], "kyoto": [35.01, 135.77],
        "london": [51.51, -0.13], "los angeles": [34.05, -118.24], "madrid": [40.42, -3.70],
        "mexico city": [19.43, -99.13], "miami": [25.76, -80.19], "montreal": [45.50, -73.57],
        "new york": [40.71, -74.01], "new york city": [40.71, -74.01], "osaka": [34.69, 135.50],
        "paris": [48.86, 2.35], "rome": [41.90, 12.50], "san francisco": [37.77, -122.42],
        "seattle": [47.61, -122.33], "seoul": [37.57, 126.98], "shanghai": [31.23, 121.47],
        "singapore": [1.35, 103.82], "sydney": [-33.87, 151.21], "taipei": [25.03, 121.57],
        "tokyo": [35.68, 139.69], "toronto": [43.65, -79.38], "vancouver": [49.28, -123.12],
        "washington": [38.91, -77.04]
    };
    city = name.split(",")[0].strip();
    coords = cities.get(city.lower());
    return {"label": city, "lat": coords[0], "lon": coords[1]} if coords is not None else None;
}

def wrapped(lon: float, center: float) -> float {
    return ((lon - center) % 360.0 + 540.0) % 360.0 - 180.0;
}

def:pub mapViewport(points: any, width: float, height: float, zoom: float, panX: float, panY: float) -> any {
    lon = 0.0; lat = 15.0; ratio = 1.0;
    scale = min(width / 365.0, height / 175.0);
    if len(points) > 0 {
        first = points[0]["lon"];
        longitudes = [wrapped(point["lon"], first) for point in points];
        latitudes = [point["lat"] for point in points];
        west = min(longitudes); east = max(longitudes); south = min(latitudes); north = max(latitudes);
        lon = wrapped(first + (west + east) / 2.0, 0.0);
        lat = (south + north) / 2.0;
        browser: any = window;
        ratio = max(0.28, browser.Math.cos(lat * browser.Math.PI / 180.0));
        scale = min(28.0, width * 0.70 / max(16.0, (east - west) * ratio),
            height * 0.53 / max(10.0, north - south));
    }
    return {"lon": lon, "lat": lat, "scale": scale * zoom, "ratio": ratio,
        "x": width / 2.0 + panX, "y": height * 0.53 + panY};
}

def:pub screenPoint(point: any, view: any) -> any {
    return {"x": view["x"] + wrapped(point["lon"], view["lon"]) * view["scale"] * view["ratio"],
        "y": view["y"] - (point["lat"] - view["lat"]) * view["scale"]};
}

def:pub screenRoute(route: any, view: any) -> any {
    start = screenPoint(route["from"], view); end = screenPoint(route["to"], view);
    end["x"] = start["x"] + wrapped(route["to"]["lon"], route["from"]["lon"]) * view["scale"] * view["ratio"];
    browser: any = window;
    distance = browser.Math.hypot(end["x"] - start["x"], end["y"] - start["y"]);
    lift = min(105.0, distance * 0.24) if route["kind"] == "flight" else 0.0;
    middle = {"x": (start["x"] + end["x"]) / 2.0, "y": (start["y"] + end["y"]) / 2.0};
    return {"start": start, "end": end, "control": {"x": middle["x"], "y": middle["y"] - lift * 2.0},
        "marker": {"x": middle["x"], "y": middle["y"] - lift}};
}

def:pub mapColor(tone: str) -> str {
    return "#ff7185" if tone == "disruption" else "#fac778" if tone == "check" else "#76f2b4" if tone == "preview" else "#78e1fb";
}

def:pub drawTripMap(canvas: any, land: any, view: any, routes: any, width: int, height: int, selected: str) -> None {
    if canvas is None or width < 1 or height < 1 { return; }
    browser: any = window;
    density = min(2.0, browser.devicePixelRatio or 1.0);
    canvas.width = int(width * density); canvas.height = int(height * density);
    ctx = canvas.getContext("2d"); ctx.scale(density, density);
    gradient = ctx.createRadialGradient(width * 0.55, height * 0.43, 12, width * 0.55, height * 0.43, max(width, height) * 0.72);
    gradient.addColorStop(0, "#153249"); gradient.addColorStop(1, "#0b1726");
    ctx.fillStyle = gradient; ctx.fillRect(0, 0, width, height);
    scaleX = view["scale"] * view["ratio"]; scaleY = view["scale"];
    ctx.beginPath();
    for lon in range(-180, 181, 10) {
        x = view["x"] + wrapped(lon, view["lon"]) * scaleX;
        ctx.moveTo(x, 0); ctx.lineTo(x, height);
    }
    for lat in range(-80, 81, 10) {
        y = view["y"] - (lat - view["lat"]) * scaleY;
        ctx.moveTo(0, y); ctx.lineTo(width, y);
    }
    ctx.lineWidth = 1; ctx.strokeStyle = "#75bad018"; ctx.stroke();
    ctx.beginPath();
    for shift in [-360, 0, 360] {
        offset = view["x"] + (shift - view["lon"]) * scaleX;
        if offset + 180 * scaleX < 0 or offset - 180 * scaleX > width { continue; }
        for ring in land {
            ctx.moveTo(offset + ring[0] * scaleX, view["y"] - (ring[1] - view["lat"]) * scaleY);
            for index in range(2, len(ring), 2) {
                ctx.lineTo(offset + ring[index] * scaleX, view["y"] - (ring[index + 1] - view["lat"]) * scaleY);
            }
            ctx.closePath();
        }
    }
    ctx.fillStyle = "#28485a"; ctx.fill("evenodd"); ctx.strokeStyle = "#53788a"; ctx.lineWidth = 0.85; ctx.stroke();
    for record in routes {
        curve = record["curve"]; start = curve["start"]; end = curve["end"]; control = curve["control"];
        ctx.beginPath(); ctx.moveTo(start["x"], start["y"]); ctx.quadraticCurveTo(control["x"], control["y"], end["x"], end["y"]);
        active = record["id"] == selected;
        ctx.strokeStyle = mapColor(record["tone"]);
        ctx.lineWidth = 11 if active else 7; ctx.globalAlpha = 0.19; ctx.stroke();
        ctx.globalAlpha = 1; ctx.lineWidth = 3.4 if active else 2.4;
        ctx.setLineDash([8, 5] if record["tone"] == "disruption" or record["tone"] == "check" else []);
        ctx.stroke(); ctx.setLineDash([]);
    }
}
