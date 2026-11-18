"""Draft fallback regressions: isolated stores and mocked model calls only."""
import os;
import tempfile;
import unittest;
import from unittest.mock { patch }
import from uuid { uuid4 }
import server.main as api;
import assistant.provider as provider;
import assistant.workflow as workflow;
import assistant.schedule as schedule;
import journey.model as journey_model;
import from assistant.workflow { check_plan }
import from journey.fixtures { plan }

def city_trip -> str {
    return api.save_trip("New York weekend", "New York", "2027-01-01", "2027-01-03", "USD", "5000",
        departure_location="Detroit", return_location="Detroit").id;
}

def send(trip_id: str, response: any, mode: str = "plan") -> dict[str, any] {
    with patch.object(provider, "generate", return_value=response), patch.object(provider, "repair") as repair,
        patch.object(provider, "request", side_effect=RuntimeError("Network disabled in fallback regression")) {
        state = api.assistant_chat(trip_id, "Prepare a useful trip", mode, False, str(uuid4()), automatic=True, draft_only=True);
        assert repair.call_count == 0;
        assert len(state["drafts"]) == 1;
        assert not state["messages"][-1].get("issues");
        return state;
    }
}

def complete_fallback(state: dict[str, any]) -> dict[str, any] {
    draft = state["drafts"][0];
    assert draft.get("fallback") and draft["relaxed"] and draft["can_apply"];
    assert "could not prepare a valid draft" not in state["messages"][-1]["text"].lower();
    assert draft["changes"] and len(draft["changes"]) <= 40;
    dates = {row["after"]["date"] for row in draft["changes"]};
    assert all(day in dates for day in ["2027-01-01", "2027-01-02", "2027-01-03"]);
    assert any(row["after"]["category"] == "stay" for row in draft["changes"]);
    assert all(not row["after"].get("flight") for row in draft["changes"]);
    route = draft["journey"];
    assert route["origin"]["city"] == "Detroit" and route["return_to"]["city"] == "Detroit";
    assert route["stops"][0]["city"] == "New York";
    covered = {row["after"].get("journey", {}).get("leg_id") for row in draft["changes"]};
    assert all(leg["id"] in covered for leg in route["legs"]);
    assert draft["trip_after"]["budget_cents"] == 500000;
    return draft;
}

test "out of order transport legs are repaired locally without discarding the itinerary" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = api.save_trip("Japan", "Tokyo", "2027-01-01", "2027-01-07", "USD", "8000",
            departure_location="Detroit", return_location="Detroit").id;
        proposal = plan(); proposal["journey"]["legs"].reverse();
        state = send(id, {"answer": "Review your trip.", "plans": [proposal]});
        draft = state["drafts"][0];
        assert not draft.get("fallback") and len(draft["changes"]) == 8;
        assert [leg["id"] for leg in draft["journey"]["legs"]] == ["origin:tokyo", "tokyo:kyoto", "kyoto:osaka", "osaka:return"];
        api.assistant_review(id, draft["id"], True, True);
        assert len(api.list_items(id)) == 8;
    }
}

test "empty malformed and unusable AI responses always produce complete estimated drafts in planning modes" {
    malformed = plan(); malformed["journey"]["origin"]["zone"] = "Mars/Olympus";
    unrouted = {"title": "An incomplete city plan", "summary": "Missing the requested travel.", "journey": None, "trip_changes": {},
        "changes": [{"item_id": "", "title": "City walk", "category": "activity", "date": "2027-01-02", "time": "14:00",
            "duration_minutes": 60, "location": "New York", "cost_cents": 0, "notes": "Estimated walk."}]};
    invalid_duration = plan(); invalid_duration["changes"][0]["duration_minutes"] = -1;
    invalid_cost = plan(); invalid_cost["changes"][0]["cost_cents"] = 12.5;
    responses: list[any] = [None, {"answer": "No plan.", "plans": []}, {"answer": "Bad shape.", "plans": "invalid"},
        {"answer": "Bad plan.", "plans": [None]}, {"answer": "Invalid route.", "plans": [malformed]},
        {"answer": "No travel.", "plans": [unrouted]}, {"answer": "Bad duration.", "plans": [invalid_duration]},
        {"answer": "Bad price.", "plans": [invalid_cost]}];
    for mode in ["plan", "backup", "replan"] {
        for response in responses {
            with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
                id = city_trip(); draft = complete_fallback(send(id, response, mode));
                assert api.list_items(id) == [];
                api.assistant_review(id, draft["id"], True, True);
                assert api.list_items(id);
                assert api.list_trips()[0].budget_cents == 500000;
            }
        }
    }
}

test "a usable backup survives an invalid sibling without another AI request" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = api.save_trip("Japan", "Tokyo", "2027-01-01", "2027-01-07", "USD", "8000",
            departure_location="Detroit", return_location="Detroit").id;
        state = send(id, {"answer": "Two options.", "plans": [None, plan()]}, "backup");
        draft = state["drafts"][0];
        assert not draft.get("fallback") and len(draft["changes"]) == 8;
        api.assistant_review(id, draft["id"], True, True);
        assert len(api.list_items(id)) == 8;
    }
}

test "AI connection failure returns a marked fallback without a second model call" {
    for mode in ["plan", "backup", "replan"] {
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
            id = city_trip();
            with patch.object(provider, "generate", side_effect=ValueError("Could not reach OpenAI or read its response. Please retry.")) as generate,
                patch.object(provider, "repair") as repair, patch.object(provider, "request", side_effect=RuntimeError("Network disabled")) {
                state = api.assistant_chat(id, "Prepare a useful trip", mode, False, str(uuid4()), automatic=True, draft_only=True);
                assert generate.call_count == 1 and repair.call_count == 0;
            }
            draft = complete_fallback(state);
            assert "estimate" in (state["messages"][-1]["text"] + draft["summary"]).lower();
            api.assistant_review(id, draft["id"], True, True);
            assert len(api.list_items(id)) > 0;
        }
    }
}

test "fallback preserves a paid booking and never automatically writes the draft" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = city_trip();
        booking = api.save_item(id, "Saved paid hotel", "stay", "2027-01-01", "16:00", "New York", "BOOKED", "Keep this booking", "300");
        api.set_item_state(id, booking.id, False, True);
        before = next(item for item in api.list_items(id) if item.id == booking.id);
        state = send(id, {"answer": "Could not build plan.", "plans": []}); draft = state["drafts"][0];
        assert draft.get("fallback") and draft["can_apply"];
        assert all(row["item_id"] != booking.id for row in draft["changes"]);
        assert len(api.list_items(id)) == 1;
        api.assistant_review(id, draft["id"], True, True);
        after = next(item for item in api.list_items(id) if item.id == booking.id);
        for key in ["id", "trip_id", "title", "category", "date", "time", "location", "reference", "notes", "cost_cents", "done", "paid", "duration_minutes"] {
            assert getattr(before, key) == getattr(after, key);
        }
        # Saving assigns the booking to the new route's city; only route metadata changes.
        assert not before.journey and after.journey["city"] == "New York" and after.journey["leg_id"] == "";
        assert len(api.list_items(id)) > 1;
    }
}

test "fallback leaves strict service and raw route validation unchanged" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = city_trip(); check = unittest.TestCase();
        with patch.object(provider, "generate", side_effect=ValueError("Connection failed")), check.assertRaises(ValueError) {
            api.assistant_chat(id, "Plan", "plan", False, str(uuid4()));
        }
        proposal = plan(); proposal["journey"]["legs"].reverse();
        with check.assertRaises(ValueError) { check_plan(api.replan_state(id), {}, proposal); }
        assert api.list_items(id) == [];
    }
}

test "relaxed drafts retain overlapping overbudget items without running strict schedule validators" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = api.save_trip("Japan", "Tokyo", "2027-01-01", "2027-01-07", "USD", "2000",
            departure_location="Detroit", return_location="Detroit").id;
        proposal = plan(); proposal["changes"][2]["date"] = "2027-01-02"; proposal["changes"][2]["time"] = "18:00";
        state = api.replan_state(id);
        with patch.object(workflow, "validate", side_effect=AssertionError("Strict replan validator must not run")),
            patch.object(journey_model, "validate", side_effect=AssertionError("Strict journey validator must not run")),
            patch.object(schedule, "fit_optional", side_effect=AssertionError("Draft items must not be pruned")) {
            draft = check_plan(state, {}, proposal, True, True, True, [], True);
        }
        assert draft["relaxed"] and draft["can_apply"] and len(draft["changes"]) == 8;
        assert draft["total_cents"] == 259500;
        assert any("budget" in warning.lower() for warning in draft["warnings"]);
        museum = next(row["after"] for row in draft["changes"] if row["after"]["title"] == "Tokyo museum");
        hotel = next(row["after"] for row in draft["changes"] if row["after"]["title"] == "Tokyo hotel check-in");
        assert museum["date"] == hotel["date"] and museum["time"] == hotel["time"];
        assert not draft["omitted_items"];
    }
}

test "relaxed drafts are fully validated when saved and an invalid one leaves the trip unchanged" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = api.save_trip("Japan", "Tokyo", "2027-01-01", "2027-01-07", "USD", "8000",
            departure_location="Detroit", return_location="Detroit").id;
        proposal = plan(); proposal["changes"][2]["date"] = "2027-01-02"; proposal["changes"][2]["time"] = "18:00";
        response = {"answer": "Review this estimated itinerary.", "sources": [], "plans": [proposal]};
        with patch.object(provider, "generate", return_value=response), patch.object(provider, "repair") as repair {
            state = api.assistant_chat(id, "Prepare my trip", "plan", False, str(uuid4()), automatic=True, draft_only=True);
            assert repair.call_count == 0;
        }
        draft = state["drafts"][0];
        assert draft["relaxed"] and draft["can_apply"];
        check = unittest.TestCase();
        with check.assertRaisesRegex(ValueError, "can't be saved yet") { api.assistant_review(id, draft["id"], True, True); }
        assert api.list_items(id) == [];
        assert api.assistant_state(id)["drafts"][0]["status"] == "pending";
    }
}
