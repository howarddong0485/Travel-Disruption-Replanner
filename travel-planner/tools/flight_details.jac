"""Source-bound flight research; never claims bookable inventory or a verified fare."""
import json;
import hashlib;
import re;
import from datetime { datetime, timezone }
import from urllib.parse { urlsplit }
import from tools.airports { airport }

def install(conn: any) -> None {
    conn.execute("CREATE TABLE IF NOT EXISTS itinerary_flights (item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE, fingerprint TEXT NOT NULL, payload TEXT NOT NULL)");
}

def signature(item: dict[str, any]) -> str {
    values = {key: item.get(key) for key in ["title", "date", "time", "location", "cost_cents", "duration_minutes", "journey"]};
    return hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest();
}

def checked(raw: any, item: dict[str, any], currency: str, sources: list[dict[str, any]]) -> dict[str, any] {
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
