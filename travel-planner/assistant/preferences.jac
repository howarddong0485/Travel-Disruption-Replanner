"""Validated trip-scoped planning controls; no itinerary writes."""

def install(conn: any) -> None {
    conn.execute("CREATE TABLE IF NOT EXISTS assistant_trip_preferences (trip_id TEXT PRIMARY KEY REFERENCES trips(id) ON DELETE CASCADE, pet_friendly INTEGER NOT NULL DEFAULT 0 CHECK(pet_friendly IN (0,1)), pace TEXT NOT NULL DEFAULT 'balanced' CHECK(pace IN ('intense','balanced','relax')))");
    conn.commit();
}

def read(conn: any, trip_id: str) -> dict[str, any] {
    row = conn.execute("SELECT pet_friendly,pace FROM assistant_trip_preferences WHERE trip_id=?", (trip_id,)).fetchone();
    return {"pet_friendly": bool(row["pet_friendly"]), "pace": row["pace"]} if row else {"pet_friendly": False, "pace": "balanced"};
}

def save(conn: any, trip_id: str, pet_friendly: any, pace: str, expected_version: any) -> None {
    if type(pet_friendly) is not bool { raise ValueError("Pet-friendly must be true or false."); }
    if pace not in ["intense", "balanced", "relax"] { raise ValueError("Choose Intense, Balanced or Relax."); }
    if type(expected_version) is not int or expected_version < 1 { raise ValueError("Invalid trip version. Reload and retry."); }
    conn.execute("BEGIN IMMEDIATE");
    row = conn.execute("SELECT version FROM trip_versions WHERE trip_id=?", (trip_id,)).fetchone();
    if row is None { raise ValueError("Trip no longer exists."); }
    if row["version"] != expected_version { raise ValueError("Your trip changed. Reload preferences and try again."); }
    if read(conn, trip_id) != {"pet_friendly": pet_friendly, "pace": pace} {
        conn.execute("INSERT INTO assistant_trip_preferences VALUES (?,?,?) ON CONFLICT(trip_id) DO UPDATE SET pet_friendly=excluded.pet_friendly,pace=excluded.pace", (trip_id, int(pet_friendly), pace));
        conn.execute("UPDATE trip_versions SET version=version+1 WHERE trip_id=?", (trip_id,));
    }
    conn.commit();
}
