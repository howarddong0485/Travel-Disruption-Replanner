"""Destination geocoding and place discovery; never room/restaurant availability."""
import os;
import re;
import math;
import urllib.parse;
import from datetime { datetime, timezone }
import from tools.provider_http { request }

glob CATEGORIES = {"hotels": "accommodation.hotel", "restaurants": "catering.restaurant", "attractions": "tourism.sights"};

def search(destination: str, country: str = "US", category: str = "hotels") -> dict[str, any] {
    key = os.environ.get("GEOAPIFY_API_KEY", "").strip();
    if not key { raise ValueError("Set GEOAPIFY_API_KEY on the server using your free account key"); }
    if not destination.strip() or len(destination) > 160 or not re.fullmatch(r"[A-Z]{2}", country) {
        raise ValueError("Enter a destination and a two-letter destination country code");
    }
    if category not in CATEGORIES { raise ValueError("Choose hotels, restaurants or attractions"); }
    query = urllib.parse.urlencode({"text": destination.strip(), "filter": "countrycode:" + country.lower(), "limit": 1, "apiKey": key});
    geo = request("https://api.geoapify.com/v1/geocode/search?" + query, {}, provider="Geoapify");
    features = geo.get("features", []);
    if not features { return {"places": [], "resolved_destination": "", "source": "Geoapify", "status": "not_found"}; }
    center = features[0]["properties"];
    lon = float(center["lon"]); lat = float(center["lat"]);
    if not math.isfinite(lon) or not math.isfinite(lat) or not (-180 <= lon <= 180 and -90 <= lat <= 90) {
        raise RuntimeError("Geoapify returned invalid coordinates");
    }
    query = urllib.parse.urlencode({"categories": CATEGORIES[category],
        "filter": "circle:" + str(lon) + "," + str(lat) + ",5000",
        "bias": "proximity:" + str(lon) + "," + str(lat), "limit": 10, "apiKey": key});
    data = request("https://api.geoapify.com/v2/places?" + query, {}, provider="Geoapify");
    places = [];
    for feature in data.get("features", []) {
        p = feature.get("properties", {});
        if not p.get("place_id") { continue; }
        places.append({"id": p["place_id"], "title": p.get("name", p.get("formatted", "Place")),
            "address": p.get("formatted", ""), "latitude": p.get("lat"), "longitude": p.get("lon"),
            "categories": p.get("categories", []), "source": "Geoapify / OpenStreetMap",
            "checked_at": datetime.now(timezone.utc).isoformat(), "availability": "unknown", "cost_cents": None});
    }
    return {"places": places, "resolved_destination": center.get("formatted", destination),
        "source": "Geoapify / OpenStreetMap", "status": "found" if places else "not_found",
        "scope": "Places within 5 km of the resolved destination. Prices, availability, opening hours and eligibility are not verified."};
}
