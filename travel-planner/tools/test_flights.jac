"""Synthetic flight research regressions. All model/search calls are mocked."""
import os;
import json;
import tempfile;
import from copy { deepcopy }
import from unittest.mock { patch }
import from uuid { uuid4 }
import server.main as api;
import tools.map_providers as maps;
import assistant.provider as provider;
import from journey.fixtures { plan }
import from tools.airports { airport }

def listing(item: dict[str, any], departure: str, arrival: str, source: str) -> dict[str, any] {
    return {"airline": "Fixture Air", "flight_number": "QA101" if departure == "DTW" else "QA102",
        "departure_airport": departure, "arrival_airport": arrival,
        "departure_date": item["date"], "departure_time": item["time"], "arrival_date": item["arrival_date"], "arrival_time": item["arrival_time"],
        "fare_cents": item["cost_cents"], "currency": "USD", "source_url": source};
}

def proposal -> dict[str, any] {
    value = plan();
    value["changes"][0]["flight"] = listing(value["changes"][0], "DTW", "HND", "https://example.com/outbound");
    value["changes"][-1]["flight"] = listing(value["changes"][-1], "KIX", "DTW", "https://example.com/return");
    return value;
}

def response(value: dict[str, any]) -> dict[str, any] {
    return {"answer": "Synthetic flight results", "plans": [value], "sources": [
        {"url": "https://example.com/outbound", "title": "Outbound fixture source"},
        {"url": "https://example.com/return", "title": "Return fixture source"}]};
}

def create -> str {
    return api.save_trip("Flight map test", "Tokyo", "2027-01-01", "2027-01-07", "USD", "8000", departure_location="Detroit", return_location="Detroit").id;
}

test "accepted flight listings appear on the map with real airport coordinates and source links" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create();
        with patch.object(provider, "generate", return_value=response(proposal())) {
            state = api.assistant_chat(id, "Plan flights", "plan", False, str(uuid4()));
        }
        draft = state["drafts"][0];
        with patch.object(maps, "search_places", return_value=[]) { api.assistant_review(id, draft["id"], True, True); }
        data = api.load_trip_map(id); assert len(data["flights"]) == 2;
        outbound = next(item for item in api.list_items(id) if item.title == "Outbound");
        flight = data["flights"][outbound.id];
        assert flight["status"] == "web_sourced" and flight["source_url"] == "https://example.com/outbound";
        assert flight["departure_point"]["lat"] == 42.21377 and flight["departure_point"]["lon"] == -83.353786;
        assert flight["arrival_point"]["label"].startswith("HND") and flight["fare_cents"] == 100000;
        assert flight["availability"] == "Confirm with airline";
        api.save_item(id, outbound.title, "transport", outbound.date, "12:15", outbound.location, "", outbound.notes, "1000", outbound.id,
            {"leg_id": "origin:tokyo", "arrival_date": "2027-01-02", "arrival_time": "16:15"}, 840);
        updated = api.load_trip_map(id)["flights"];
        assert outbound.id not in updated and len(updated) == 1;
    }
}

test "uncited or mismatched flight results remain estimates without blocking the trip" {
    for fault in ["source", "date", "airport"] {
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
            id = create(); value = proposal();
            if fault == "source" { value["changes"][0]["flight"]["source_url"] = "https://example.com/not-a-research-source"; }
            elif fault == "date" { value["changes"][0]["flight"]["departure_date"] = "2027-01-02"; }
            else { value["changes"][0]["flight"]["departure_airport"] = "ZZZ"; }
            with patch.object(provider, "generate", return_value=response(value)) {
                state = api.assistant_chat(id, "Plan flights", "plan", False, str(uuid4()));
            }
            draft = state["drafts"][0]; assert draft["can_apply"];
            assert not draft["changes"][0]["after"]["flight"];
            assert api.load_trip_map(id)["flights"] == {};
        }
    }
}
