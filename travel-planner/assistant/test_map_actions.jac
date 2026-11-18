"""Copilot tool routing and persisted confirmation, with external services mocked."""
import from tests.workspace_fixture { TEST_WORKSPACE }
import os;
import tempfile;
import json;
import from uuid { uuid4 }
import from unittest.mock { patch }
import server.main as api;
import assistant.provider as provider;
import tools.map_providers as maps;

test "natural chat dispatches place tool and confirms ambiguity from persisted conversation" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": folder + "/trip.sqlite3"}) {
        trip = api.save_trip(TEST_WORKSPACE, "New trip", "Reykjavik", "2026-11-15", "2026-11-20");
        item = api.save_item(TEST_WORKSPACE, trip.id, "Harpa", location="Harpa");
        response = {"output": [{"type": "function_call", "name": "locate_itinerary_places", "arguments": "{}"}]};
        matches = [{"label": "Harpa concert hall", "lat": 64.15, "lon": -21.93}, {"label": "Harpa stop", "lat": 64.16, "lon": -21.94}];
        with patch.object(provider, "request", return_value=response), patch.object(maps, "search_places", return_value=matches) {
            state = api.assistant_chat(TEST_WORKSPACE, trip.id, "请把景点标到地图", "ask", True, str(uuid4()));
        }
        message = state["messages"][-1];
        assert len(message["map_actions"][0]["choices"]) == 2;
        assert item.id not in api.load_trip_map(TEST_WORKSPACE, trip.id)["pins"];
        api.assistant_confirm_map(TEST_WORKSPACE, trip.id, message["id"], 0, 0);
        assert api.load_trip_map(TEST_WORKSPACE, trip.id)["pins"][item.id]["lat"] == 64.15;
        assert api.assistant_state(TEST_WORKSPACE, trip.id)["messages"][-1]["map_actions"][0]["confirmed"];
    }
}

test "flight tool does not save coordinates until confirmed and rejects stale flight edits" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": folder + "/trip.sqlite3"}) {
        trip = api.save_trip(TEST_WORKSPACE, "Flight trip", "Osaka", "2026-11-15", "2026-11-20");
        item = api.save_item(TEST_WORKSPACE, trip.id, "NH37", "transport", "2026-11-15", location="Tokyo to Osaka");
        call = {"output": [{"type": "function_call", "name": "lookup_flight_track", "arguments": json.dumps({"item_id": item.id, "callsign": "ANA37", "day": "2026-11-15"})}]};
        track = {"id": "record", "callsign": "ANA37", "registration": "JA830A", "start": "2026-11-15T09:20:00Z", "end": "2026-11-15T10:10:00Z", "source": "https://adsb.aero", "segments": [[[139.7,35.5],[135.4,34.8]]]};
        with patch.object(provider, "request", return_value=call), patch.object(maps, "recorded_tracks", return_value={"tracks": [track]}) {
            state = api.assistant_chat(TEST_WORKSPACE, trip.id, "Find actual ANA37 track", "ask", True, str(uuid4()));
            message = state["messages"][-1];
            assert api.load_trip_map(TEST_WORKSPACE, trip.id)["tracks"] == {};
            api.assistant_confirm_map(TEST_WORKSPACE, trip.id, message["id"], 0, 0);
            assert api.load_trip_map(TEST_WORKSPACE, trip.id)["tracks"][item.id]["track"]["id"] == "record";
            state = api.assistant_chat(TEST_WORKSPACE, trip.id, "Find the track again", "ask", True, str(uuid4()));
            api.save_item(TEST_WORKSPACE, trip.id, "NH37", "transport", "2026-11-16", location="Tokyo to Osaka", item_id=item.id);
            caught = False;
            try { api.assistant_confirm_map(TEST_WORKSPACE, trip.id, state["messages"][-1]["id"], 0, 0); }
            except ValueError { caught = True; }
            assert caught;
        }
    }
}

test "accepting an AI itinerary resolves its new venue without opening the map" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": folder + "/trip.sqlite3"}) {
        trip = api.save_trip(TEST_WORKSPACE, "AI trip", "Reykjavik", "2026-11-15", "2026-11-20", "USD", "1000");
        proposal = {"answer": "Draft", "plans": [{"title": "Visit", "summary": "Visit the church", "changes": [
            {"item_id": "", "title": "Hallgrimskirkja", "category": "activity", "date": "2026-11-16", "time": "10:00", "duration_minutes": 60,
                "location": "Hallgrimskirkja", "cost_cents": 0, "notes": "Verify opening hours"}]}]};
        with patch.object(provider, "generate", return_value=proposal) {
            state = api.assistant_chat(TEST_WORKSPACE, trip.id, "Plan my trip", "plan", False, str(uuid4()));
        }
        with patch.object(maps, "search_places", return_value=[{"label": "Hallgrimskirkja", "lat": 64.14, "lon": -21.92}]) {
            saved = api.assistant_review(TEST_WORKSPACE, trip.id, state["drafts"][0]["id"], True, True);
        }
        assert len(api.load_trip_map(TEST_WORKSPACE, trip.id)["pins"]) == 1;
        assert "1 places located" in saved["messages"][-1]["text"];
        with patch.object(maps, "search_places", side_effect=AssertionError("replayed accept must not geocode")) {
            replay = api.assistant_review(TEST_WORKSPACE, trip.id, state["drafts"][0]["id"], True, True);
        }
        assert len(replay["messages"]) == len(saved["messages"]);
    }
}
