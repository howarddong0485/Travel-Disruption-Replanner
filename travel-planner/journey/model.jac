"""Ordered cities, explicit transport legs and timezone-aware journey checks."""
import json;
import re;
import math;
import from copy { deepcopy }
import from datetime { datetime, timedelta, timezone, date }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }

def install(conn: any) -> None {
    conn.execute("CREATE TABLE IF NOT EXISTS journeys (trip_id TEXT PRIMARY KEY REFERENCES trips(id) ON DELETE CASCADE, payload TEXT NOT NULL)");
    conn.execute("CREATE TABLE IF NOT EXISTS journey_items (item_id TEXT PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE, payload TEXT NOT NULL)");
    for table in ["journeys", "journey_items"] {
        for operation in ["INSERT", "UPDATE", "DELETE"] {
            ref = "OLD" if operation == "DELETE" else "NEW";
            lookup = ref + ".trip_id" if table == "journeys" else "(SELECT trip_id FROM items WHERE id=" + ref + ".item_id)";
            conn.execute("CREATE TRIGGER IF NOT EXISTS " + table + "_" + operation.lower() + " AFTER " + operation + " ON " + table +
                " BEGIN UPDATE trip_versions SET version=version+1 WHERE trip_id=" + lookup + "; END");
        }
    }
    conn.commit();
}

def read(conn: any, trip_id: str) -> any {
    row = conn.execute("SELECT payload FROM journeys WHERE trip_id=?", (trip_id,)).fetchone();
    return json.loads(row["payload"]) if row else None;
}

def item_details(conn: any, item_id: str) -> dict[str, any] {
    row = conn.execute("SELECT payload FROM journey_items WHERE item_id=?", (item_id,)).fetchone();
    return json.loads(row["payload"]) if row else {};
}

def write(conn: any, trip_id: str, journey: any) -> None {
    conn.execute("INSERT INTO journeys VALUES (?,?) ON CONFLICT(trip_id) DO UPDATE SET payload=excluded.payload",
        (trip_id, json.dumps(journey, sort_keys=True, allow_nan=False)));
}

def write_item(conn: any, item_id: str, detail: dict[str, any]) -> None {
    if detail {
        conn.execute("INSERT INTO journey_items VALUES (?,?) ON CONFLICT(item_id) DO UPDATE SET payload=excluded.payload",
            (item_id, json.dumps(detail, sort_keys=True, allow_nan=False)));
    } else { conn.execute("DELETE FROM journey_items WHERE item_id=?", (item_id,)); }
}

def checked_date(value: any) -> str {
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) { raise ValueError("Use a date in YYYY-MM-DD format."); }
    date.fromisoformat(value); return value;
}

def place(raw: any) -> dict[str, any] {
    if not isinstance(raw, dict) { raise ValueError("Each city needs a name and time zone."); }
    city = raw.get("city"); zone = raw.get("zone");
    if not isinstance(city, str) or not city.strip() or len(city) > 160 { raise ValueError("Enter a city or region name."); }
    if not isinstance(zone, str) or not zone or len(zone) > 100 { raise ValueError("Choose an IANA time zone for " + city + "."); }
    try { ZoneInfo(zone); } except (ZoneInfoNotFoundError, ValueError) { raise ValueError("Unknown time zone for " + city + "."); }
    lat = raw.get("lat"); lon = raw.get("lon");
    if (lat is None) != (lon is None) { raise ValueError("Provide both coordinates or leave both blank."); }
    if lat is not None and lon is not None and (type(lat) not in (int, float) or type(lon) not in (int, float) or
        not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180) {
        raise ValueError("Invalid city coordinates.");
    }
    return {"city": city.strip(), "zone": zone, "lat": lat, "lon": lon};
}

def normalize(raw: any, trip: dict[str, any]) -> dict[str, any] {
    if not isinstance(raw, dict) or raw.get("version") != 1 or not isinstance(raw.get("stops"), list) or not 1 <= len(raw["stops"]) <= 12 {
        raise ValueError("A journey needs 1–12 ordered destination cities.");
    }
    origin = place(raw.get("origin")); returning = place(raw["return_to"]) if raw.get("return_to") is not None else None;
    stops = []; ids = {"origin", "return"};
    for raw_stop in raw["stops"] {
        stop = place(raw_stop); key = raw_stop.get("id");
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", key) or key in ids { raise ValueError("City stops need distinct IDs."); }
        first = checked_date(raw_stop.get("arrival_date")); last = checked_date(raw_stop.get("departure_date"));
        if not trip["start_date"] <= first <= last <= trip["end_date"] { raise ValueError("City dates must fit the trip: " + stop["city"]); }
        ids.add(key); stops.append({**stop, "id": key, "arrival_date": first, "departure_date": last});
    }
    pairs = [("origin", stops[0]["id"])];
    pairs.extend((left["id"], right["id"]) for (left, right) in zip(stops, stops[1:]));
    if returning is not None { pairs.append((stops[-1]["id"], "return")); }
    supplied = raw.get("legs", []);
    if not isinstance(supplied, list) or len(supplied) != len(pairs) { raise ValueError("Include one transport leg between every adjacent pair of cities."); }
    legs = [];
    for (index, pair) in enumerate(pairs) {
        leg = supplied[index];
        if not isinstance(leg, dict) or (leg.get("from_id"), leg.get("to_id")) != pair { raise ValueError("Transport legs must follow the saved city order."); }
        if leg.get("mode") not in ["flight", "train", "drive", "bus", "ferry"] { raise ValueError("Choose a supported transport mode."); }
        for key in ["before_minutes", "after_minutes"] {
            if type(leg.get(key)) is not int or not 0 <= leg[key] <= 1440 { raise ValueError("Transfer buffers must be 0–1440 minutes."); }
        }
        legs.append({"id": pair[0] + ":" + pair[1], "from_id": pair[0], "to_id": pair[1],
            "mode": leg["mode"], "before_minutes": leg["before_minutes"], "after_minutes": leg["after_minutes"]});
    }
    return {"version": 1, "origin": origin, "stops": stops, "return_to": returning, "legs": legs};
}

def places(journey: dict[str, any]) -> dict[str, any] {
    result = {stop["id"]: stop for stop in journey["stops"]};
    result["origin"] = journey["origin"];
    if journey["return_to"] is not None { result["return"] = journey["return_to"]; }
    return result;
}

def instant(local: str, zone: str) -> datetime {
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}", local) { raise ValueError("Use a local date and HH:MM time."); }
    naive = datetime.fromisoformat(local); tz = ZoneInfo(zone); values = set();
    for fold in [0, 1] {
        value = naive.replace(tzinfo=tz, fold=fold).astimezone(timezone.utc);
        if value.astimezone(tz).replace(tzinfo=None) == naive { values.add(value); }
    }
    if len(values) != 1 { raise ValueError("This local time is ambiguous or does not exist during a clock change; choose an unambiguous time."); }
    # Existing scheduling code compares naive datetimes. Routed times use UTC throughout.
    return next(iter(values)).replace(tzinfo=None);
}

def local_time(value: datetime, zone: str) -> datetime {
    return value.replace(tzinfo=timezone.utc).astimezone(ZoneInfo(zone)).replace(tzinfo=None);
}

def bind(item: dict[str, any], raw: dict[str, any], journey: dict[str, any]) -> dict[str, any] {
    stop_id = raw.get("stop_id", ""); leg_id = raw.get("leg_id", ""); lookup = places(journey);
    if not isinstance(stop_id, str) or not isinstance(leg_id, str) or bool(stop_id) == bool(leg_id) {
        raise ValueError("Assign " + item["title"] + " to one city stop or one intercity leg.");
    }
    if leg_id {
        matches = [leg for leg in journey["legs"] if leg["id"] == leg_id];
        if item["category"] != "transport" or not matches { raise ValueError("Only transport items can cover a saved intercity leg."); }
        leg = matches[0]; start_zone = lookup[leg["from_id"]]["zone"]; end_zone = lookup[leg["to_id"]]["zone"];
        arrival_date = checked_date(raw.get("arrival_date")); arrival_time = raw.get("arrival_time");
        if not isinstance(arrival_time, str) { raise ValueError("Provide the arrival time at the destination."); }
        first = instant(item["date"] + "T" + item["time"], start_zone);
        last = instant(arrival_date + "T" + arrival_time, end_zone);
        duration = int((last - first).total_seconds() / 60);
        if not 1 <= duration <= 1440 or duration != item["duration_minutes"] { raise ValueError("Transport duration must match its departure and arrival instants (up to 24 hours per leg)."); }
    } else {
        if stop_id not in {s["id"] for s in journey["stops"]} { raise ValueError("Unknown destination city for " + item["title"] + "."); }
        start_zone = lookup[stop_id]["zone"]; end_zone = start_zone;
        first = instant(item["date"] + "T" + item["time"], start_zone);
        last = local_time(first + timedelta(minutes=item["duration_minutes"]), end_zone);
        arrival_date = last.date().isoformat(); arrival_time = last.strftime("%H:%M");
    }
    return {"stop_id": stop_id, "leg_id": leg_id, "zone": start_zone, "end_zone": end_zone,
        "arrival_date": arrival_date, "arrival_time": arrival_time,
        "city": lookup[stop_id]["city"] if stop_id else "",
        "from_city": lookup[leg["from_id"]]["city"] if leg_id else "",
        "to_city": lookup[leg["to_id"]]["city"] if leg_id else "",
        "mode": leg["mode"] if leg_id else ""};
}

def validate(journey: dict[str, any], trip: dict[str, any], items: list[dict[str, any]], complete: bool = True) -> list[str] {
    normalize(journey, trip); lookup = places(journey); transport = {}; visits = []; issues = [];
    for item in items {
        if item["category"] in ["packing", "expense"] { continue; }
        detail = item.get("journey", {});
        if not detail {
            if complete { raise ValueError("Assign " + item["title"] + " to a city or transport leg before planning this journey."); }
            issues.append("Assign " + item["title"] + " to a city or transport leg."); continue;
        }
        expected = bind(item, detail, journey);
        if expected != detail { raise ValueError("City or time-zone details changed for " + item["title"] + "; update the item in the same plan."); }
        first = instant(item["date"] + "T" + item["time"], detail["zone"]);
        last = first + timedelta(minutes=item["duration_minutes"]);
        if detail["leg_id"] {
            key = detail["leg_id"];
            if key in transport { raise ValueError("Only one transport item may cover each intercity leg."); }
            transport[key] = (first, last, item);
        } else {
            stop = lookup[detail["stop_id"]];
            if not stop["arrival_date"] <= item["date"] <= detail["arrival_date"] <= stop["departure_date"] {
                raise ValueError("Activity is outside the stay in " + stop["city"] + ".");
            }
            visits.append((detail["stop_id"], first, last, item["title"]));
        }
    }
    ordered_visits = sorted(visits, key=lambda (v: any) -> any { (v[1], v[2]); });
    for (left, right) in zip(ordered_visits, ordered_visits[1:]) {
        if right[1] < left[2] { raise ValueError("Scheduled visits overlap: " + left[3] + " and " + right[3] + "."); }
    }
    previous_end = None;
    for leg in journey["legs"] {
        record = transport.get(leg["id"]);
        if record is None { issues.append("Add transport: " + lookup[leg["from_id"]]["city"] + " → " + lookup[leg["to_id"]]["city"]); continue; }
        (first, last, item) = record; detail = item["journey"];
        expected_departure = trip["start_date"] if leg["from_id"] == "origin" else lookup[leg["from_id"]]["departure_date"];
        expected_arrival = trip["end_date"] if leg["to_id"] == "return" else lookup[leg["to_id"]]["arrival_date"];
        if item["date"] != expected_departure or detail["arrival_date"] != expected_arrival {
            raise ValueError("Transport dates must match the city arrival/departure dates.");
        }
        if previous_end is not None and first - timedelta(minutes=leg["before_minutes"]) < previous_end {
            raise ValueError("Intercity transport overlaps or leaves too little transfer time.");
        }
        previous_end = last + timedelta(minutes=leg["after_minutes"]);
        for (stop_id, visit_start, visit_end, title) in visits {
            if stop_id == leg["to_id"] and visit_start < previous_end { raise ValueError(title + " starts before arrival and the transfer buffer."); }
            if stop_id == leg["from_id"] and visit_end > first - timedelta(minutes=leg["before_minutes"]) { raise ValueError(title + " leaves too little time before the next city transfer."); }
        }
    }
    if complete and issues { raise ValueError("Complete the journey: " + "; ".join(issues)); }
    return issues;
}

def replacement_items(state: dict[str, any], replacements: list[dict[str, any]]) -> dict[str, any] {
    if not state.get("journey") { return {}; }
    nodes = {item["id"]: deepcopy(item) for item in state["items"]};
    for replacement in replacements {
        if replacement["action"] != "reschedule" { raise ValueError("Use the journey planner for replacements across cities; the sample catalog cannot verify their city."); }
        candidate = replacement["item"]; item = nodes[replacement["replaces_id"]]; detail = item["journey"];
        if candidate["start"]["zone"] != detail["zone"] or candidate["end"]["zone"] != detail["end_zone"] { raise ValueError("A reschedule must preserve the route's local time zones."); }
        item.update(date=candidate["start"]["local"][:10], time=candidate["start"]["local"][11:16]);
        item["duration_minutes"] = int((instant(candidate["end"]["local"], detail["end_zone"]) - instant(candidate["start"]["local"], detail["zone"])).total_seconds() / 60);
        detail = {**detail, "arrival_date": candidate["end"]["local"][:10], "arrival_time": candidate["end"]["local"][11:16]};
        item["journey"] = bind(item, detail, state["journey"]);
    }
    validate(state["journey"], state["trip"], list(nodes.values()));
    return nodes;
}
