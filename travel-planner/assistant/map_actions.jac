"""Execute bounded copilot map tools using server records, never model coordinates."""
import json;
import itinerary.map_enrichment as enrichment;
import tools.map_providers as providers;
import from itinerary.place_data { read_place_details, write_place_details }

def execute(conn: any, trip_id: str, requests: list[any]) -> dict[str, any] {
    actions: list[any] = []; messages: list[str] = [];
    for request in requests[:3] {
        args = request["arguments"];
        try {
            if request["name"] == "locate_itinerary_places" {
                located = 0; remaining = 1;
                for batch in range(10) {
                    result = enrichment.resolve_places(conn, trip_id);
                    located += result["located"]; remaining = result["remaining"];
                    if not remaining { break; }
                }
                messages.append(str(located) + " places located and saved. Existing coordinates are preserved.");
                states = enrichment.lookup_states(conn, trip_id);
                for (item_id, state) in states.items() {
                    current = read_place_details(conn, trip_id, item_id);
                    if current["latitude"] is not None { continue; }
                    item = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (item_id, trip_id)).fetchone();
                    if state["status"] == "needs_confirmation" {
                        actions.append({"kind": "place", "item_id": item_id, "title": item["title"],
                            "signature": enrichment.place_context(conn, trip_id, item)["signature"],
                            "revision": current["revision"], "location": item["location"], "choices": state["matches"]});
                    } else { messages.append(item["title"] + ": location unavailable; refine its address or retry from the map."); }
                }
                if remaining { messages.append("More places remain. Ask me to continue locating them."); }
            } elif request["name"] == "lookup_flight_track" {
                item = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=? AND category='transport'", (args["item_id"], trip_id)).fetchone();
                if item is None { raise ValueError("Choose a saved flight from this trip first."); }
                tracks = providers.recorded_tracks(args["callsign"], args["day"])["tracks"];
                saved = enrichment.flight_tracks(conn, trip_id).get(item["id"], {});
                actions.append({"kind": "flight", "item_id": item["id"], "title": item["title"], "location": item["location"],
                    "date": item["date"], "callsign": args["callsign"], "day": args["day"], "revision": saved.get("revision", 0),
                    "choices": [{key: track[key] for key in ["id", "callsign", "registration", "start", "end", "source"]} for track in tracks]});
                messages.append(item["title"] + (": recorded tracks found. Check the registration and UTC times, then confirm a match below." if tracks else ": no recorded track available for that callsign and UTC date. No path was invented or saved."));
            }
        } except Exception as error { conn.rollback(); messages.append("Map lookup could not complete: " + str(error)); }
    }
    return {"answer": "\n".join(messages), "map_actions": actions};
}

def confirm(conn: any, trip_id: str, message_id: str, action_index: int, choice_index: int) -> None {
    row = conn.execute("SELECT payload FROM assistant_messages WHERE id=? AND trip_id=? AND role='assistant'", (message_id, trip_id)).fetchone();
    if row is None { raise ValueError("This result does not belong to this trip."); }
    payload = json.loads(row["payload"]); actions = payload.get("map_actions", []);
    if type(action_index) is not int or not 0 <= action_index < len(actions) { raise ValueError("Invalid map result."); }
    action = actions[action_index];
    if type(choice_index) is not int or not 0 <= choice_index < len(action["choices"]) { raise ValueError("Invalid map choice."); }
    if action.get("confirmed", False) { return; }
    choice = action["choices"][choice_index];
    if action["kind"] == "flight" {
        enrichment.save_flight_track(conn, trip_id, action["item_id"], action["title"], action["location"], action["date"],
            action["callsign"], action["day"], choice["id"], action["revision"]);
    } else {
        item = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (action["item_id"], trip_id)).fetchone();
        if item is None or enrichment.place_context(conn, trip_id, item)["signature"] != action["signature"] { raise ValueError("This place changed. Ask for a fresh lookup."); }
        current = read_place_details(conn, trip_id, action["item_id"]);
        write_place_details(conn, trip_id, action["item_id"], action["location"], action["revision"],
            {"latitude": choice["lat"], "longitude": choice["lon"], "photo_url": current["photo_url"], "photo_source": current["photo_source"]});
    }
    action["confirmed"] = True;
    conn.execute("UPDATE assistant_messages SET payload=? WHERE id=? AND trip_id=?", (json.dumps(payload), message_id, trip_id));
    conn.commit();
}
