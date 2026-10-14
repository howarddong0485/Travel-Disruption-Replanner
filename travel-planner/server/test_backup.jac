"""Backup endpoint integration checks with an isolated SQLite database."""
import os;
import tempfile;
import sqlite3;
import from jaclang.testing.testing { JacTestClient }

def stored_snapshot -> str {
    conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
    try { return "\n".join(conn.iterdump()); }
    finally { conn.close(); }
}

test "preview endpoint serializes drafts and never alters trips items or costs" {
    previous = os.environ.get("TRAVEL_DB_PATH");
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(os.path.join(os.path.dirname(__file__), "main.jac"), base_path=os.path.join(directory, "store"));
        try {
            trip = client.post("/function/save_trip", json={"title": "Backup demo", "destination": "Boston", "start_date": "2026-11-01", "end_date": "2026-11-03", "budget": "100"}).data["result"];
            other = client.post("/function/save_trip", json={"title": "Other trip", "destination": "Boston", "start_date": "2026-11-01", "end_date": "2026-11-03"}).data["result"];
            activity = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Outdoor walk", "date": "2026-11-02", "cost": "10"}).data["result"];
            dinner = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Dinner", "category": "food", "date": "2026-11-02", "cost": "20"}).data["result"];
            undated = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Undated activity"}).data["result"];
            completed = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Finished activity", "date": "2026-11-02"}).data["result"];
            client.post("/function/set_item_state", json={"trip_id": trip["id"], "item_id": completed["id"], "done": True, "paid": False});
            before = stored_snapshot();
            for (item_id, trigger) in [(activity["id"], "rain"), (dinner["id"], "arrival_delay")] {
                response = client.post("/function/preview_backups", json={"trip_id": trip["id"], "item_id": item_id, "trigger": trigger});
                assert response.ok, str(response.data);
                result = response.data["result"];
                assert result["status"] == "needs_validation" and len(result["options"]) == 2;
                assert result["options"][0]["candidate"]["currency"] == "USD";
                assert result["options"][0]["replaced_item_id"] == item_id;
                assert stored_snapshot() == before;
            }
            for (trip_id, item_id, trigger) in [
                (other["id"], activity["id"], "rain"),
                ("missing", activity["id"], "rain"),
                (trip["id"], "", "rain"),
                (trip["id"], dinner["id"], "rain"),
                (trip["id"], activity["id"], "arrival_delay"),
                (trip["id"], activity["id"], "snow"),
                (trip["id"], undated["id"], "rain"),
                (trip["id"], completed["id"], "rain")
            ] {
                assert not client.post("/function/preview_backups", json={"trip_id": trip_id, "item_id": item_id, "trigger": trigger}).ok;
                assert stored_snapshot() == before;
            }
            client.post("/function/delete_item", json={"trip_id": trip["id"], "item_id": activity["id"]});
            after_delete = stored_snapshot();
            assert not client.post("/function/preview_backups", json={"trip_id": trip["id"], "item_id": activity["id"], "trigger": "rain"}).ok;
            assert stored_snapshot() == after_delete;
        } finally {
            client.close();
            if previous is None { os.environ.pop("TRAVEL_DB_PATH", None); }
            else { os.environ["TRAVEL_DB_PATH"] = previous; }
        }
    }
}
