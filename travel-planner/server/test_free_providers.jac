"""HTTP previews use isolated databases and synthetic provider responses."""
import from tests.workspace_fixture { TEST_WORKSPACE }
import os;
import json;
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
                trip_id = client.post("/function/replan_demo", json={"workspace_key":TEST_WORKSPACE}).data["result"]["trip_id"];
                before = client.post("/function/replan_state", json={"workspace_key":TEST_WORKSPACE, "trip_id": trip_id}).data["result"];
                hotel = next(i for i in before["items"] if i["category"] == "stay");
                # The synthetic demo has fixed November 2026 dates. Freeze only
                # the provider clock so this offline test does not age out.
                provider_clock = Mock(now=Mock(return_value=datetime(2026, 11, 1, tzinfo=timezone.utc)));
                with patch.object(lite, "datetime", provider_clock), patch.object(lite, "request", return_value=rates_fixture()) {
                    response = client.post("/function/preview_liteapi_hotels", json={"workspace_key":TEST_WORKSPACE, "trip_id": trip_id, "item_id": hotel["id"],
                        "checkout": "2026-11-03", "city": "Boston", "destination_country": "US", "occupancy": "2", "nationality": "US",
                        "mode": "backup", "kind": "interrupted", "delay_minutes": 0});
                    assert response.ok, str(response);
                    assert response.data["result"]["proposals"][0]["offer"]["cost_cents"] == 12234;
                }
                with patch.object(geo, "request", return_value={"features": []}) {
                    response = client.post("/function/discover_travel_places", json={"workspace_key":TEST_WORKSPACE, "trip_id": trip_id, "destination": "Boston", "country": "US", "category": "hotels"});
                    assert response.ok and response.data["result"]["places"] == [];
                }
                after = client.post("/function/replan_state", json={"workspace_key":TEST_WORKSPACE, "trip_id": trip_id}).data["result"];
                assert after == before;
                db = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
                assert db.execute("SELECT count(*) FROM replan_proposals").fetchone()[0] == 0;
                db.close();
            } finally { client.close(); }
        }
    }
}

test "supplier quotes are private read-only and report the response mode" {
    with tempfile.TemporaryDirectory() as directory {
        with patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3"),
            "LITEAPI_API_KEY": "prod_synthetic", "EXPEDIA_ENV": "invalid"}) {
            client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
            try {
                status = client.post("/function/travel_provider_status", json={}).data["result"];
                assert status["liteapi"] == {"configured": True, "mode": "live"};
                assert status["expedia"]["error"] == "Invalid server configuration";
                assert "prod_synthetic" not in json.dumps(status);
                workspace = {"workspace_key": TEST_WORKSPACE};
                trip_id = client.post("/function/save_trip", json={**workspace, "title": "Supplier quote trip", "destination": "Boston",
                    "start_date": "2027-02-01", "end_date": "2027-02-04"}).data["result"]["id"];
                trip = {**workspace, "trip_id": trip_id};
                before = client.post("/function/replan_state", json=trip).data["result"];
                query = {**trip, "checkin": "2027-02-02", "checkout": "2027-02-04", "city": "Boston", "destination_country": "US"};
                endpoint = "/function/quote_liteapi_hotels";
                provider_clock = Mock(now=Mock(return_value=datetime(2027, 1, 31, tzinfo=timezone.utc)));
                sandbox = rates_fixture(); live = {**sandbox, "sandbox": False};
                with patch.object(lite, "datetime", provider_clock), patch.object(lite, "request", side_effect=[sandbox, live,
                    RuntimeError("LiteAPI is unavailable or returned invalid JSON. Retry later.")]) as request {
                    denied = client.post(endpoint, json={**query, "workspace_key": "25ff096b-c658-4a7d-9e5f-193a91f16459"});
                    assert not denied.ok;
                    out_of_trip = client.post(endpoint, json={**query, "checkin": "2027-01-30"}).data["result"];
                    assert "within the saved trip dates" in out_of_trip["error"];
                    request.assert_not_called();
                    result = client.post(endpoint, json=query).data["result"];
                    assert result["mode"] == "sandbox";
                    assert result["quotes"] == [{"property_id": "hotel-1", "title": "Synthetic City Hotel", "room_name": "Synthetic Queen",
                        "cost_cents": 12234, "currency": "USD", "checkin": "2027-02-02", "checkout": "2027-02-04", "occupancy": "2",
                        "checked_at": "2027-01-31T00:00:00+00:00", "refundability": "NRFN"}];
                    assert client.post(endpoint, json=query).data["result"]["mode"] == "live";
                    assert "unavailable" in client.post(endpoint, json=query).data["result"]["error"];
                }
                assert client.post("/function/replan_state", json=trip).data["result"] == before;
            } finally { client.close(); }
        }
    }
}
