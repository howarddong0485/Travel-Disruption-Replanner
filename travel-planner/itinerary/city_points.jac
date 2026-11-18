"""Offline coordinates shared by map previews and flight validation."""
def:pub cityPoint(name: str, known: any = None) -> any {
    supplied = known.get(name) if known else None;
    if supplied and supplied.get("lat") is not None and supplied.get("lon") is not None {
        return {"label": name, "lat": supplied["lat"], "lon": supplied["lon"]};
    }
    cities = {
        "apia": [-13.83, -171.75], "amsterdam": [52.37, 4.90], "ann arbor": [42.28, -83.74], "atlanta": [33.75, -84.39],
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
