"""Optional visual attachments bound to an item's saved address."""
import json;
import math;
import from urllib.parse { urlsplit }
import from datetime { datetime, timezone }

def read_place_details(conn: any, trip_id: str, item_id: str) -> dict[str, any] {
    item = conn.execute("SELECT location FROM items WHERE trip_id=? AND id=? AND category NOT IN ('packing','expense')", (trip_id, item_id)).fetchone();
    if item is None { raise ValueError("Choose a place in the current trip"); }
    row = conn.execute("SELECT * FROM itinerary_place_details WHERE item_id=?", (item_id,)).fetchone();
    data: dict[str, any] = {"latitude": None, "longitude": None, "photo_url": "", "photo_source": "", "checked_at": ""};
    if row is not None and row["location"] == item["location"] { data.update(json.loads(row["payload"])); }
    return {**data, "item_id": item_id, "location": item["location"], "revision": row["revision"] if row is not None else 0};

}

def write_place_details(conn: any, trip_id: str, item_id: str, location: str,
    expected_revision: any, payload: dict[str, any]) -> dict[str, any] {
    if type(expected_revision) is not int or expected_revision < 0 { raise ValueError("Invalid place revision"); }
    if not isinstance(payload, dict) or set(payload) != {"latitude", "longitude", "photo_url", "photo_source"} {
        raise ValueError("Supply a photo URL, photo credit and optional coordinates");
    }
    lat = payload["latitude"]; lon = payload["longitude"];
    if (lat is None) != (lon is None) { raise ValueError("Supply both latitude and longitude"); }
    if lat is not None and (type(lat) not in (int, float) or type(lon) not in (int, float) or
        not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180) {
        raise ValueError("Coordinates must be valid latitude and longitude");
    }
    photo = payload["photo_url"]; source = payload["photo_source"];
    if not isinstance(photo, str) or not isinstance(source, str) or len(photo) > 2000 or len(source) > 400 {
        raise ValueError("Photo details are too long");
    }
    photo = photo.strip(); source = source.strip();
    if photo {
        url = urlsplit(photo);
        if url.scheme != "https" or not url.hostname or url.username or url.password {
            raise ValueError("Use an HTTPS photo URL");
        }
        if not source { raise ValueError("Add a photo source or photographer credit"); }
    }
    conn.execute("BEGIN IMMEDIATE");
    try {
        current = read_place_details(conn, trip_id, item_id);
        if current["revision"] != expected_revision or current["location"] != location {
            raise ValueError("This place changed. Reload before saving its photo or map pin.");
        }
        data = {"latitude": lat, "longitude": lon, "photo_url": photo, "photo_source": source,
            "checked_at": datetime.now(timezone.utc).isoformat()};
        conn.execute("INSERT INTO itinerary_place_details VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET location=excluded.location,payload=excluded.payload,revision=excluded.revision",
            (item_id, location, json.dumps(data, allow_nan=False), expected_revision + 1));
        result = read_place_details(conn, trip_id, item_id);
        conn.commit(); return result;
    } except Exception { conn.rollback(); raise; }
}
