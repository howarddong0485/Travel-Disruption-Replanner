"""HTTP serialization, service restart, idempotency and saved-trip isolation."""
import os;
import uuid;
import sqlite3;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

def history_travel_snapshot -> str {
    conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
    try { return "\n".join(conn.iterdump()); } finally { conn.close(); }
}

test "history HTTP lifecycle persists separately and never mutates the saved trip" {
    names = ["TRAVEL_DB_PATH", "BACKUP_HISTORY_DB_PATH"];
    previous = {name: os.environ.get(name) for name in names};
    with tempfile.TemporaryDirectory() as directory {
        os.environ[names[0]] = os.path.join(directory, "travel.sqlite3");
        os.environ[names[1]] = os.path.join(directory, "history.sqlite3");
        path = os.path.join(os.path.dirname(__file__), "main.jac");
        client = JacTestClient.from_file(path, base_path=os.path.join(directory, "store"));
        try {
            trip = client.post("/function/save_trip", json={"title": "History isolation", "destination": "Boston",
                "start_date": "2026-11-17", "end_date": "2026-11-18", "budget": "600"}).data["result"];
            client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Keep me", "date": "2026-11-17", "cost": "15"});
            before = history_travel_snapshot();
            session_id = str(uuid.uuid4());
            initial = client.post("/function/load_backup_history", json={"session_id": session_id});
            assert initial.ok and initial.data["result"]["revision"] == 0;
            payload = {"session_id": session_id, "request_id": str(uuid.uuid4()), "expected_revision": 0,
                "sample_date": "2026-11-17", "inventory_change": "unchanged"};
            first = client.post("/function/save_backup_refresh", json=payload);
            assert first.ok and first.data["result"]["revision"] == 1;
            duplicate = client.post("/function/save_backup_refresh", json=payload);
            assert duplicate.ok and duplicate.data["result"]["replayed"];
            assert duplicate.data["result"]["report"] == first.data["result"]["report"];
            assert first.data["result"]["report"]["results"][0]["changes"]["cost"]["delta_minor"] == 3000;
            payload["request_id"] = str(uuid.uuid4());
            conflict = client.post("/function/save_backup_refresh", json=payload);
            assert conflict.ok and conflict.data["result"]["outcome"] == "conflict";
            assert conflict.data["result"]["report"] is None;
            payload["expected_revision"] = 1; payload["inventory_change"] = "provider_failure";
            failed_provider = client.post("/function/save_backup_refresh", json=payload);
            assert failed_provider.ok and failed_provider.data["result"]["report"]["summary"]["needs_validation"] == 2;
            assert history_travel_snapshot() == before;
            client.close();
            client = JacTestClient.from_file(path, base_path=os.path.join(directory, "restart-store"));
            restored = client.post("/function/load_backup_history", json={"session_id": session_id}).data["result"];
            assert restored["revision"] == 2 and len(restored["entries"]) == 2;
            assert "report" not in restored;
            assert restored["entries"][0]["recorded_options"][0]["cost_minor"] is None;
            assert restored["entries"][0]["recorded_options"][0]["changes"]["cost"]["delta_minor"] is None;
            assert restored["entries"][1]["recorded_options"][0]["changes"]["cost"]["delta_minor"] == 3000;
            assert client.post("/function/load_backup_history", json={"session_id": str(uuid.uuid4())}).data["result"]["entries"] == [];
            for changes in [{"budget": "NaN"}, {"expected_revision": True}, {"expected_revision": 1.0}, {"expected_revision": "1"}, {"expected_revision": None}, {"request_id": "bad"}, {"sample_date": ""}] {
                invalid = dict(payload); invalid.update(changes);
                assert not client.post("/function/save_backup_refresh", json=invalid).ok, str(changes);
            }
            assert client.post("/function/load_backup_history", json={"session_id": session_id}).data["result"]["revision"] == 2;
            assert history_travel_snapshot() == before;
        } finally {
            client.close();
            for name in names {
                if previous[name] is None { os.environ.pop(name, None); }
                else { os.environ[name] = previous[name]; }
            }
        }
    }
}
