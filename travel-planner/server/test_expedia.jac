"""HTTP-boundary checks use a temporary trip database and fake shopping only."""
import os;
import json;
import sqlite3;
import tempfile;
import from unittest.mock { patch }
import from jaclang.testing.testing { JacTestClient }
import replan.expedia as planner;
import from replan.test_expedia { shopping_fixture }

glob SERVER = os.path.join(os.path.dirname(__file__), "main.jac");

test "Expedia endpoint computes drafts without altering any trip records" {
    with tempfile.TemporaryDirectory() as directory {
        with patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3"), "EXPEDIA_API_KEY": "", "EXPEDIA_SHARED_SECRET": "", "EXPEDIA_ENV": "test"}) {
            client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
            try {
                status = client.post("/function/expedia_status", json={}).data["result"];
                assert status == {"configured": False, "mode": "test"};
                trip_id = client.post("/function/replan_demo", json={}).data["result"]["trip_id"];
                before = client.post("/function/replan_state", json={"trip_id": trip_id}).data["result"];
                hotel = next(i for i in before["items"] if i["category"] == "stay");
                args = {"trip_id": trip_id, "item_id": hotel["id"], "checkout": "2026-11-03", "property_ids": ["19248"], "occupancy": "2", "country": "US", "mode": "backup", "kind": "interrupted", "delay_minutes": 0};
                with patch.object(planner, "search_hotels", return_value=shopping_fixture()) {
                    response = client.post("/function/preview_expedia_hotels", json=args);
                    assert response.ok, str(response);
                    assert response.data["result"]["proposals"];
                }
                after = client.post("/function/replan_state", json={"trip_id": trip_id}).data["result"];
                assert after == before;
                db = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
                assert db.execute("SELECT count(*) FROM replan_proposals").fetchone()[0] == 0;
                assert db.execute("SELECT count(*) FROM disruption_events").fetchone()[0] == 0;
                db.close();
                assert not client.post("/function/preview_expedia_hotels", json={**args, "item_id": "foreign"}).ok;
            } finally { client.close(); }
        }
    }
}

test "trip edits during provider search invalidate the preview" {
    with tempfile.TemporaryDirectory() as directory {
        path = os.path.join(directory, "trip.sqlite3");
        with patch.dict(os.environ, {"TRAVEL_DB_PATH": path}) {
            client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
            try {
                trip_id = client.post("/function/replan_demo", json={}).data["result"]["trip_id"];
                state = client.post("/function/replan_state", json={"trip_id": trip_id}).data["result"];
                hotel = next(i for i in state["items"] if i["category"] == "stay");
                def changed(*args: any, **kwargs: any) -> any {
                    conn = sqlite3.connect(path);
                    conn.execute("UPDATE trips SET notes='Changed during search' WHERE id=?", (trip_id,));
                    conn.commit(); conn.close();
                    return shopping_fixture();
                }
                with patch.object(planner, "search_hotels", side_effect=changed) {
                    response = client.post("/function/preview_expedia_hotels", json={"trip_id": trip_id,
                        "item_id": hotel["id"], "checkout": "2026-11-03", "property_ids": ["19248"], "occupancy": "2", "country": "US", "mode": "backup", "kind": "interrupted", "delay_minutes": 0});
                    assert not response.ok;
                    assert "Trip changed" in str(response.data);
                }
            } finally { client.close(); }
        }
    }
}
