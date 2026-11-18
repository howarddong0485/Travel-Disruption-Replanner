"""Projection, viewport and drawing for the trip map."""
def:pub cityPoint(name: str, known: any = None) -> any {
    supplied = known.get(name) if known else None;
    if supplied and supplied.get("lat") is not None and supplied.get("lon") is not None {
        return {"label": name, "lat": supplied["lat"], "lon": supplied["lon"]};
    }
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
    if city.lower() == "nyc" { city = "New York City"; }
    coords = cities.get(city.lower());
    return {"label": city, "lat": coords[0], "lon": coords[1]} if coords is not None else None;
}

def wrapped(lon: float, center: float) -> float {
    return ((lon - center) % 360.0 + 540.0) % 360.0 - 180.0;
}

def:pub mapViewport(points: any, width: float, height: float, zoom: float, panX: float, panY: float) -> any {
    lon = 0.0; lat = 15.0; ratio = 1.0;
    top = min(172.0, height * 0.36); bottom = max(top + 120.0, height - 84.0);
    plotWidth = max(150.0, width - (96.0 if width < 560 else 148.0));
    plotHeight = max(120.0, bottom - top);
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
        # Leave space around the endpoints for labels and around the line for its arc.
        scale = min(30.0, plotWidth / (max(8.0, (east - west) * ratio) * 1.35),
            plotHeight / (max(6.0, north - south) * 1.35));
    }
    return {"lon": lon, "lat": lat, "scale": scale * zoom, "ratio": ratio,
        "x": width / 2.0 + panX, "y": (top + bottom) / 2.0 + panY};
}

def:pub screenPoint(point: any, view: any) -> any {
    return {"x": view["x"] + wrapped(point["lon"], view["lon"]) * view["scale"] * view["ratio"],
        "y": view["y"] - (point["lat"] - view["lat"]) * view["scale"]};
}

def:pub screenRoute(route: any, view: any) -> any {
    start = screenPoint(route["from"], view); end = screenPoint(route["to"], view);
    browser: any = window;
    dx = end["x"] - start["x"]; dy = end["y"] - start["y"];
    distance = browser.Math.hypot(dx, dy);
    lift = min(82.0, max(22.0, distance * 0.18)) if route["kind"] == "flight" and distance > 1 else 0.0;
    # A perpendicular bend naturally puts each travel direction on its own side,
    # including north/south legs. Project both endpoints in the same wrapped view.
    normalX = dy / max(1.0, distance); normalY = -dx / max(1.0, distance);
    middle = {"x": (start["x"] + end["x"]) / 2.0, "y": (start["y"] + end["y"]) / 2.0};
    return {"start": start, "end": end,
        "control": {"x": middle["x"] + normalX * lift * 2.0, "y": middle["y"] + normalY * lift * 2.0},
        "marker": {"x": middle["x"] + normalX * lift, "y": middle["y"] + normalY * lift},
        "angle": browser.Math.atan2(dy, dx) * 180.0 / browser.Math.PI};
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
    gradient.addColorStop(0, "#132f44"); gradient.addColorStop(1, "#091928");
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
    ctx.lineWidth = 1; ctx.strokeStyle = "#75bad012"; ctx.stroke();
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
    ctx.fillStyle = "#203c4e"; ctx.fill("evenodd"); ctx.strokeStyle = "#3d5c70"; ctx.lineWidth = 0.75; ctx.stroke();
    for record in routes {
        curve = record["curve"]; start = curve["start"]; end = curve["end"]; control = curve["control"];
        ctx.beginPath(); ctx.moveTo(start["x"], start["y"]); ctx.quadraticCurveTo(control["x"], control["y"], end["x"], end["y"]);
        active = record["id"] == selected;
        color = mapColor(record["tone"]) if record["tone"] in ["disruption", "check", "preview"] else
            "#bea6ff" if record.get("direction") == "Return" else "#7de3f4" if record["route"]["kind"] == "flight" else "#9bb9ca";
        ctx.lineCap = "round"; ctx.strokeStyle = color;
        ctx.lineWidth = 10 if active else 6; ctx.globalAlpha = 0.18 if active else 0.09; ctx.stroke();
        ctx.globalAlpha = 1; ctx.lineWidth = 3.2 if active else 2.2;
        dashed = record.get("estimated", False) or (record["route"]["kind"] != "flight" and record["tone"] in ["disruption", "check"]);
        ctx.setLineDash([6, 5] if dashed else []);
        ctx.stroke(); ctx.setLineDash([]);
        if record["route"]["kind"] == "flight" {
            t = 0.70; other = 1.0 - t;
            arrowX = other * other * start["x"] + 2.0 * other * t * control["x"] + t * t * end["x"];
            arrowY = other * other * start["y"] + 2.0 * other * t * control["y"] + t * t * end["y"];
            tangentX = other * (control["x"] - start["x"]) + t * (end["x"] - control["x"]);
            tangentY = other * (control["y"] - start["y"]) + t * (end["y"] - control["y"]);
            ctx.save(); ctx.translate(arrowX, arrowY); ctx.rotate(browser.Math.atan2(tangentY, tangentX));
            ctx.beginPath(); ctx.moveTo(6, 0); ctx.lineTo(-4, -3.8); ctx.lineTo(-1.8, 0); ctx.lineTo(-4, 3.8); ctx.closePath();
            ctx.fillStyle = color; ctx.strokeStyle = "#102536"; ctx.lineWidth = 1.1; ctx.stroke(); ctx.fill(); ctx.restore();
            for endpoint in [start, end] {
                ctx.beginPath(); ctx.arc(endpoint["x"], endpoint["y"], 2.6, 0, browser.Math.PI * 2.0);
                ctx.fillStyle = color; ctx.fill();
            }
        }
    }
}
