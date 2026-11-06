"""HTTP previews use isolated databases and synthetic provider responses."""
import os;
import sqlite3;
import tempfile;
import from datetime { datetime, timezone }
import from unittest.mock { Mock, patch }
import from jaclang.testing.testing { JacTestClient }
import tools.alternatives.liteapi as lite;
import tools.geoapify as geo;
import from tools.test_free_providers { rates_fixture }

glob SERVER = os.path.join(os.path.dirname(__file__), "main.jac");

test "free-provider endpoints compute previews with no itinerary writes" {
    with tempfile.TemporaryDirectory() as directory {
        with patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3"), "LITEAPI_API_KEY": "sand_example", "GEOAPIFY_API_KEY": "example-geo"}) {
            client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
            try {
                status = client.post("/function/travel_provider_status", json={}).data["result"];
                assert status["liteapi"] == {"configured": True, "mode": "sandbox"};
                trip_id = client.post("/function/replan_demo", json={}).data["result"]["trip_id"];
                before = client.post("/function/replan_state", json={"trip_id": trip_id}).data["result"];
                hotel = next(i for i in before["items"] if i["category"] == "stay");
                # The synthetic demo has fixed November 2026 dates. Freeze only
                # the provider clock so this offline test does not age out.
                provider_clock = Mock(now=Mock(return_value=datetime(2026, 11, 1, tzinfo=timezone.utc)));
                with patch.object(lite, "datetime", provider_clock), patch.object(lite, "request", return_value=rates_fixture()) {
                    response = client.post("/function/preview_liteapi_hotels", json={"trip_id": trip_id, "item_id": hotel["id"],
                        "checkout": "2026-11-03", "city": "Boston", "destination_country": "US", "occupancy": "2", "nationality": "US",
                        "mode": "backup", "kind": "interrupted", "delay_minutes": 0});
                    assert response.ok, str(response);
                    assert response.data["result"]["proposals"][0]["offer"]["cost_cents"] == 12234;
                }
                with patch.object(geo, "request", return_value={"features": []}) {
                    response = client.post("/function/discover_travel_places", json={"trip_id": trip_id, "destination": "Boston", "country": "US", "category": "hotels"});
                    assert response.ok and response.data["result"]["places"] == [];
                }
                after = client.post("/function/replan_state", json={"trip_id": trip_id}).data["result"];
                assert after == before;
                db = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
                assert db.execute("SELECT count(*) FROM replan_proposals").fetchone()[0] == 0;
                db.close();
            } finally { client.close(); }
        }
    }
}
