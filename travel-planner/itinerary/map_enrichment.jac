"""Persistent map enrichment for every saved trip, independent of browser or chat."""
import json;
import hashlib;
import from datetime { datetime, timezone }
import tools.map_providers as providers;
import from journey.model { item_details }
import from itinerary.place_data { read_place_details, write_place_details }

def install(conn: any) -> None {
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS itinerary_map_lookups (
            item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            signature TEXT NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS itinerary_flight_tracks (
            item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
            signature TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL);
    """);
}

def place_context(conn: any, trip_id: str, item: any) -> dict[str, str] {
    trip = conn.execute("SELECT destination FROM trips WHERE id=?", (trip_id,)).fetchone();
    if trip is None { raise ValueError("Trip not found"); }
    detail = item_details(conn, item["id"]);
    city = detail.get("city") or trip["destination"];
    venue = item["location"].strip() or item["title"].strip();
    query = venue if city.casefold() in venue.casefold() else venue + ", " + city;
    signature = hashlib.sha256(json.dumps([item["title"], item["location"], city]).encode()).hexdigest();
    return {"city": city, "query": query[:300], "signature": signature};
}

def lookup_states(conn: any, trip_id: str) -> dict[str, any] {
    result: dict[str, any] = {};
    for item in conn.execute("SELECT * FROM items WHERE trip_id=? AND category IN ('stay','food','activity')", (trip_id,)).fetchall() {
        context = place_context(conn, trip_id, item);
        row = conn.execute("SELECT * FROM itinerary_map_lookups WHERE item_id=?", (item["id"],)).fetchone();
        if row and row["signature"] == context["signature"] {
            result[item["id"]] = {"status": row["status"], **json.loads(row["payload"])};
        }
    }
    return result;
}

def resolve_places(conn: any, trip_id: str, retry: bool = False) -> dict[str, any] {
    if conn.execute("SELECT id FROM trips WHERE id=?", (trip_id,)).fetchone() is None { raise ValueError("Trip not found"); }
    pending: list[any] = [];
    states = lookup_states(conn, trip_id);
    for item in conn.execute("SELECT * FROM items WHERE trip_id=? AND category IN ('stay','food','activity') ORDER BY date,time,id", (trip_id,)).fetchall() {
        if item["location"].startswith("fixture:") { continue; }
        current = read_place_details(conn, trip_id, item["id"]);
        if current["latitude"] is not None { continue; }
        if item["id"] not in states or retry { pending.append(item); }
    }
    located = 0;
    for item in pending[:4] {
        context = place_context(conn, trip_id, item);
        current = read_place_details(conn, trip_id, item["id"]);
        status = "needs_confirmation"; matches: list[any] = []; message = "";
        try {
            matches = providers.search_places(context["query"]);
            if not matches { status = "not_found"; }
            # Do not hold a write transaction during a network request. Recheck edits afterwards.
            fresh = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (item["id"], trip_id)).fetchone();
            if fresh is None or place_context(conn, trip_id, fresh)["signature"] != context["signature"] { continue; }
            if len(matches) == 1 {
                write_place_details(conn, trip_id, item["id"], current["location"], current["revision"],
                    {"latitude": matches[0]["lat"], "longitude": matches[0]["lon"],
                        "photo_url": current["photo_url"], "photo_source": current["photo_source"]});
                status = "located"; located += 1;
            }
        } except Exception {
            conn.rollback(); status = "unavailable"; message = "Location search is unavailable. Retry or choose a place manually.";
        }
        # Recheck after a failed save as well, so deleted or edited items cannot gain stale evidence.
        fresh = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (item["id"], trip_id)).fetchone();
        if fresh is None or place_context(conn, trip_id, fresh)["signature"] != context["signature"] { continue; }
        conn.execute("INSERT INTO itinerary_map_lookups VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET signature=excluded.signature,status=excluded.status,payload=excluded.payload",
            (item["id"], context["signature"], status, json.dumps({"query": context["query"], "city": context["city"], "matches": matches,
                "message": message, "checked_at": datetime.now(timezone.utc).isoformat()})));
        conn.commit();
    }
    return {"located": located, "remaining": max(0, len(pending) - 4)};
}

def flight_signature(item: any) -> str {
    return hashlib.sha256(json.dumps([item["title"], item["location"], item["date"], item["category"]]).encode()).hexdigest();
}

def flight_tracks(conn: any, trip_id: str) -> dict[str, any] {
    result: dict[str, any] = {};
    for item in conn.execute("SELECT * FROM items WHERE trip_id=? AND category='transport'", (trip_id,)).fetchall() {
        row = conn.execute("SELECT * FROM itinerary_flight_tracks WHERE item_id=?", (item["id"],)).fetchone();
        if row { result[item["id"]] = {"revision": row["revision"], "track": json.loads(row["payload"]) if row["signature"] == flight_signature(item) else None}; }
    }
    return result;
}

def save_flight_track(conn: any, trip_id: str, item_id: str, title: str, location: str, departure_date: str,
    callsign: str, day: str, track_id: str, expected_revision: int) -> dict[str, any] {
    item = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=? AND category='transport'", (item_id, trip_id)).fetchone();
    if item is None or [item["title"], item["location"], item["date"]] != [title, location, departure_date] {
        raise ValueError("This flight changed. Reload the map before choosing a track.");
    }
    signature = flight_signature(item);
    track = None;
    if track_id {
        found = providers.recorded_tracks(callsign, day)["tracks"];
        matches = [record for record in found if record["id"] == track_id];
        if len(matches) != 1 { raise ValueError("The selected track is no longer available. Search again."); }
        track = matches[0];
    }
    conn.execute("BEGIN IMMEDIATE");
    try {
        fresh = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (item_id, trip_id)).fetchone();
        row = conn.execute("SELECT revision FROM itinerary_flight_tracks WHERE item_id=?", (item_id,)).fetchone();
        revision = row["revision"] if row else 0;
        if fresh is None or flight_signature(fresh) != signature or type(expected_revision) is not int or expected_revision != revision {
            raise ValueError("This flight or saved track changed. Reload the map and try again.");
        }
        conn.execute("INSERT INTO itinerary_flight_tracks VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET signature=excluded.signature,payload=excluded.payload,revision=excluded.revision",
            (item_id, signature, json.dumps(track, allow_nan=False), revision + 1));
        conn.commit(); return {"track": track, "revision": revision + 1};
    } except Exception { conn.rollback(); raise; }
}
