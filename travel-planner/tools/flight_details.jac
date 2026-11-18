"""Source-bound flight research; never claims bookable inventory or a verified fare."""
import json;
import hashlib;
import re;
import math;
import from datetime { datetime, timezone }
import from zoneinfo { ZoneInfo }
import from urllib.parse { urlsplit }
import from tools.airports { airport }

def install(conn: any) -> None {
    conn.execute("CREATE TABLE IF NOT EXISTS itinerary_flights (item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE, fingerprint TEXT NOT NULL, payload TEXT NOT NULL)");
}

def signature(item: dict[str, any]) -> str {
    values = {key: item.get(key) for key in ["title", "date", "time", "location", "cost_cents", "duration_minutes", "journey"]};
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest();
}

def kilometres(left: dict[str, any], right: dict[str, any]) -> float {
    (lat1, lon1, lat2, lon2) = (math.radians(left["lat"]), math.radians(left["lon"]), math.radians(right["lat"]), math.radians(right["lon"]));
    step = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2;
    return 12742.0 * math.asin(min(1.0, math.sqrt(step)));
}

# An airport must serve the leg endpoint it claims. Known city coordinates allow 150 km
# (e.g. Narita–Tokyo, Beauvais–Paris). Otherwise the airport's solar offset must fall
# within 2.5 hours of the endpoint zone's UTC offset on that local date, which rejects
# swapped or unrelated airports (LAX for Detroit, LHR for Tokyo) without network lookups.
def serves(point: dict[str, any], place: any, zone: str, day: str) -> bool {
    if isinstance(place, dict) and place.get("lat") is not None and place.get("lon") is not None {
        return kilometres(point, place) <= 150.0;
    }
    try { shift: any = ZoneInfo(zone).utcoffset(datetime.fromisoformat(day + "T12:00")); }
    except (ValueError, KeyError) { return False; }
    offset = shift.total_seconds() / 3600;
    gap = (point["lon"] / 15.0 - offset) % 24.0;
    return min(gap, 24.0 - gap) <= 2.5;
}

def leg_places(item: dict[str, any], journey: any) -> list[any] {
    if not isinstance(journey, dict) { return [None, None]; }
    lookup = {stop["id"]: stop for stop in journey.get("stops", [])};
    lookup["origin"] = journey.get("origin"); lookup["return"] = journey.get("return_to");
    legs = [leg for leg in journey.get("legs", []) if leg.get("id") == item["journey"].get("leg_id")];
    return [lookup.get(legs[0]["from_id"]), lookup.get(legs[0]["to_id"])] if legs else [None, None];
}

def checked(raw: any, item: dict[str, any], currency: str, sources: list[dict[str, any]], journey: any = None) -> dict[str, any] {
    if not isinstance(raw, dict) or item.get("journey", {}).get("mode") != "flight" { return {}; }
    fields = ["airline", "flight_number", "departure_airport", "arrival_airport", "departure_date", "departure_time", "arrival_date", "arrival_time", "source_url", "currency"];
    if any(not isinstance(raw.get(key), str) or len(raw[key]) > (2000 if key == "source_url" else 120) for key in fields) { return {}; }
    try { link = urlsplit(raw["source_url"]); }
    except ValueError { return {}; }
    if link.scheme != "https" or not link.hostname or link.username or link.password or raw["source_url"] not in [source.get("url") for source in sources] { return {}; }
    if not raw["airline"].strip() or not re.fullmatch(r"[A-Z0-9 /,-]{2,60}", raw["flight_number"].upper()) { return {}; }
    if any(not re.fullmatch(r"[A-Z]{3}", raw[key]) for key in ["departure_airport", "arrival_airport"]) or raw["departure_airport"] == raw["arrival_airport"] { return {}; }
    departure_point = airport(raw["departure_airport"]); arrival_point = airport(raw["arrival_airport"]);
    if departure_point is None or arrival_point is None { return {}; }
    detail = item["journey"];
    if [raw[key] for key in ["departure_date", "departure_time", "arrival_date", "arrival_time"]] != [item["date"], item["time"], detail["arrival_date"], detail["arrival_time"]] { return {}; }
    (start, end) = leg_places(item, journey);
    if not serves(departure_point, start, detail.get("zone", ""), item["date"]) or not serves(arrival_point, end, detail.get("end_zone", ""), detail["arrival_date"]) { return {}; }
    quote: any = raw.get("fare_cents");
    quoted = type(quote) is int and quote >= 0 and quote == item["cost_cents"] and raw["currency"] == currency;
    result = {key: raw[key] for key in fields};
    result.update({"flight_number": raw["flight_number"].upper(), "fare_cents": quote if quoted else None,
        "status": "web_sourced", "availability": "Confirm with airline", "price_status": "Web-listed fare; reconfirm" if quoted else "Planning estimate; fare not confirmed",
        "checked_at": raw.get("checked_at") or datetime.now(timezone.utc).isoformat(),
        "departure_point": departure_point, "arrival_point": arrival_point});
    return result;
}

def write(conn: any, item_id: str, item: dict[str, any]) -> None {
    flight = item.get("flight", {});
    if flight {
        conn.execute("INSERT INTO itinerary_flights VALUES (?,?,?) ON CONFLICT(item_id) DO UPDATE SET fingerprint=excluded.fingerprint,payload=excluded.payload", (item_id, signature(item), json.dumps(flight)));
    } else {
        existing = conn.execute("SELECT fingerprint FROM itinerary_flights WHERE item_id=?", (item_id,)).fetchone();
        if existing is None or existing["fingerprint"] != signature(item) { conn.execute("DELETE FROM itinerary_flights WHERE item_id=?", (item_id,)); }
    }
}

def read_for_items(conn: any, items: list[dict[str, any]]) -> dict[str, any] {
    flights: dict[str, any] = {};
    for item in items {
        row = conn.execute("SELECT fingerprint,payload FROM itinerary_flights WHERE item_id=?", (item["id"],)).fetchone();
        if row is not None and row["fingerprint"] == signature(item) { flights[item["id"]] = json.loads(row["payload"]); }
    }
    return flights;
}
