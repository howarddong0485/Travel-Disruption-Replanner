"""Read map facts without changing the saved itinerary or planner inputs."""
import json;
import math;
import from datetime { datetime }

def install_map_schema(conn: any) -> None {
    conn.execute("""CREATE TABLE IF NOT EXISTS itinerary_map_routes (
        item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
        title TEXT NOT NULL, location TEXT NOT NULL,
        payload TEXT NOT NULL, revision INTEGER NOT NULL)""");
}

def checked_point(point: any) -> dict[str, any] {
    if not isinstance(point, dict) or set(point) != {"label", "lat", "lon"} {
        raise ValueError("Enter a name and coordinates for each endpoint");
    }
    label = point["label"]; lat = point["lat"]; lon = point["lon"];
    if not isinstance(label, str) or not label.strip() or len(label) > 100 {
        raise ValueError("Enter an endpoint name up to 100 characters");
    }
    if type(lat) not in (int, float) or type(lon) not in (int, float) or
        not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180 {
        raise ValueError("Enter valid latitude and longitude for each endpoint");
    }
    return {"label": label.strip(), "lat": lat, "lon": lon};
}

def save_map_route(conn: any, trip_id: str, item_id: str, title: str, location: str,
    expected_revision: any, payload: any) -> dict[str, any] {
    if type(expected_revision) is not int or expected_revision < 0 { raise ValueError("Invalid route revision"); }
    route = None;
    if payload is not None {
        if not isinstance(payload, dict) or set(payload) != {"from", "to", "kind"} or payload["kind"] not in ("flight", "ground") {
            raise ValueError("Choose a flight or ground route with two endpoints");
        }
        origin = checked_point(payload["from"]); arrival = checked_point(payload["to"]);
        if origin["lat"] == arrival["lat"] and abs(origin["lon"] - arrival["lon"]) in (0, 360) {
            raise ValueError("Choose two different endpoints");
        }
        route = {"from": origin, "to": arrival, "kind": payload["kind"]};
    }
    conn.execute("BEGIN IMMEDIATE");
    try {
        item = conn.execute("SELECT title, location FROM items WHERE trip_id=? AND id=? AND category='transport'", (trip_id, item_id)).fetchone();
        row = conn.execute("SELECT revision FROM itinerary_map_routes WHERE item_id=?", (item_id,)).fetchone();
        revision = row["revision"] if row is not None else 0;
        if item is None or item["title"] != title or item["location"] != location or revision != expected_revision {
            raise ValueError("This transport or route changed. Reload the map and try again.");
        }
        conn.execute("""INSERT INTO itinerary_map_routes VALUES (?,?,?,?,?)
            ON CONFLICT(item_id) DO UPDATE SET title=excluded.title,location=excluded.location,
            payload=excluded.payload,revision=excluded.revision""",
            (item_id, title, location, json.dumps(route, allow_nan=False), revision + 1));
        conn.commit();
        return {"route": route, "revision": revision + 1};
    } except Exception { conn.rollback(); raise; }
}

def map_points(conn: any, trip_id: str) -> tuple[dict[str, any], dict[str, any]] {
    pins: dict[str, any] = {}; routes: dict[str, any] = {};
    for row in conn.execute("""SELECT i.id, p.payload FROM items i JOIN itinerary_place_details p
        ON i.id=p.item_id AND i.location=p.location WHERE i.trip_id=? AND i.category NOT IN ('packing','expense')""", (trip_id,)) {
        data = json.loads(row["payload"]);
        if data["latitude"] is not None { pins[row["id"]] = {"lat": data["latitude"], "lon": data["longitude"]}; }
    }
    for row in conn.execute("""SELECT i.id,i.title,i.location,r.title AS saved_title,r.location AS saved_location,
        r.revision,r.payload FROM items i JOIN itinerary_map_routes r ON i.id=r.item_id
        WHERE i.trip_id=? AND i.category='transport'""", (trip_id,)) {
        route = json.loads(row["payload"]) if row["title"] == row["saved_title"] and row["location"] == row["saved_location"] else None;
        routes[row["id"]] = {"route": route, "revision": row["revision"]};
    }
    return (pins, routes);
}

def current_map_plans(conn: any, trip_id: str, version: int, validator: str, now: datetime) -> list[dict[str, any]] {
    plans: list[dict[str, any]] = []; seen: set[str] = set();
    for row in conn.execute("""SELECT payload FROM replan_proposals WHERE trip_id=? AND base_version=?
        AND status='proposed' ORDER BY rowid DESC LIMIT 40""", (trip_id, version)) {
        plan = json.loads(row["payload"]);
        if plan.get("plan_contract") == "roam.alternative-plan.v1" and plan.get("validator_version") == validator and
            datetime.fromisoformat(plan["expires_at"]) > now and plan["candidate_id"] not in seen {
            plans.append(plan); seen.add(plan["candidate_id"]);
        }
    }
    return plans;
}
