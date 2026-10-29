"""Refresh API checks against an isolated saved-trip database."""
import os;
import sqlite3;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

def refresh_storage_snapshot() -> str {
    conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
    try { return "\n".join(conn.iterdump()); } finally { conn.close(); }
}

test "refresh transitions are serialized and never change saved trips" {
    previous = os.environ.get("TRAVEL_DB_PATH");
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(os.path.join(os.path.dirname(__file__), "main.jac"), base_path=os.path.join(directory, "store"));
        try {
            trip = client.post("/function/save_trip", json={"title": "Refresh isolation", "destination": "Boston",
                "start_date": "2026-11-17", "end_date": "2026-11-18", "budget": "600"}).data["result"];
            client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Keep me", "date": "2026-11-17", "cost": "15"});
            before = refresh_storage_snapshot();
            last_id = "";
            for (change, passes, rejected, unknown) in [
                ("unchanged", 2, 0, 0), ("price_increase", 1, 1, 0), ("sold_out", 1, 1, 0),
                ("all_sold_out", 0, 2, 0), ("expired_evidence", 1, 0, 1),
                ("provider_failure", 0, 0, 2), ("partial_failure", 1, 0, 1), ("unchanged", 2, 0, 0)
            ] {
                response = client.post("/function/refresh_backup_validation", json={"inventory_change": change, "sample_date": "2026-11-17"});
                assert response.ok, str(response.data);
                r = response.data["result"];
                assert r["summary"] == {"passed_fixture_checks": passes, "invalid": rejected, "needs_validation": unknown};
                assert r["trip_date"] == "2026-11-17" and r["scope"] == "standalone_fixture";
                assert r["refresh_id"] != last_id;
                assert r["results"][0]["changes"]["version"] == "backup-changes-v1";
                assert r["results"][0]["changes"]["cost"]["original_total_minor"] == 41000;
                if change == "provider_failure" {
                    assert r["results"][0]["changes"]["cost"]["delta_minor"] is None;
                }
                last_id = r["refresh_id"];
                assert refresh_storage_snapshot() == before;
            }
            for payload in [{"inventory_change": "bad"}, {"inventory_change": ""}, {"sample_date": "2026-02-30"}, {"budget": "NaN"}] {
                assert not client.post("/function/refresh_backup_validation", json=payload).ok;
                assert refresh_storage_snapshot() == before;
            }
        } finally {
            client.close();
            if previous is None { os.environ.pop("TRAVEL_DB_PATH", None); }
            else { os.environ["TRAVEL_DB_PATH"] = previous; }
        }
    }
}
