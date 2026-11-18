"""Isolated browser-test map seed using synthetic fixtures and no network calls.
Run: jac run tests/seed_flights.jac. The temporary DB path is written to
/tmp/roam-flight-map-smoke-state.json for the browser-test server."""
import from tests.workspace_fixture { TEST_WORKSPACE }
import os;
import json;
import tempfile;
import from pathlib { Path }
import from uuid { uuid4 }
import from unittest.mock { patch }
import server.main as api;
import tools.map_providers as maps;
import assistant.provider as provider;
import from tools.test_flights { proposal, response }
with entry {
    if not os.environ.get("TRAVEL_DB_PATH") { os.environ["TRAVEL_DB_PATH"] = tempfile.mkdtemp(prefix="roam-flight-map-") + "/trip.db"; }
    id = api.save_trip(TEST_WORKSPACE, "Flight map browser regression", "Tokyo", "2027-01-01", "2027-01-07", "USD", "8000", departure_location="Detroit", return_location="Detroit").id;
    value = proposal(); value["journey"]["stops"] = [value["journey"]["stops"][0]];
    value["journey"]["stops"][0]["departure_date"] = "2027-01-07";
    value["journey"]["legs"] = [value["journey"]["legs"][0], value["journey"]["legs"][-1]];
    value["journey"]["legs"][-1]["from_id"] = "tokyo";
    value["changes"] = [value["changes"][0], value["changes"][1], value["changes"][2], value["changes"][-1]];
    value["changes"][-1]["leg_id"] = "tokyo:return";
    value["changes"][-1]["flight"]["departure_airport"] = "HND";
    with patch.object(provider, "generate", return_value=response(value)), patch.object(provider, "request", side_effect=RuntimeError("Network disabled in synthetic test")) {
        state = api.assistant_chat(TEST_WORKSPACE, id, "Synthetic flight map test", "plan", False, str(uuid4()));
    }
    with patch.object(maps, "search_places", return_value=[]) { api.assistant_review(TEST_WORKSPACE, id, state["drafts"][0]["id"], True, True); }
    Path("/tmp/roam-flight-map-smoke-state.json").write_text(json.dumps({"trip_id": id, "db": os.environ["TRAVEL_DB_PATH"]}));
    print(json.dumps({"trip_id": id, "mapped_flights": len(api.load_trip_map(TEST_WORKSPACE, id)["flights"])}));
}
