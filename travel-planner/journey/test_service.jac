"""End-to-end service checks with isolated stores and mocked model responses."""
import os;
import tempfile;
import unittest;
import from copy { deepcopy }
import from unittest.mock { patch }
import from uuid { uuid4 }
import server.main as api;
import assistant.provider as provider;
import journey.model as journey;
import from journey.fixtures { route, plan }
import from assistant.workflow { check_plan }
import from replan.engine { build_combination }

def create -> str {
    return api.save_trip("Japan", "Tokyo", "2027-01-01", "2027-01-07", "USD", "8000", "", "", "Detroit", "Detroit").id;
}
def send(trip_id: str, proposal: any) -> any {
    response = {"answer": "Review your route.", "sources": [], "plans": [proposal]};
    with patch.object(provider, "generate", return_value=response), patch.object(provider, "repair", return_value=response) {
        return api.assistant_chat(trip_id, "Plan the whole journey", "plan", False, str(uuid4()));
    }
}

test "journey complete cross-zone plan saves route and all transport only on acceptance" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); response = send(id, plan()); draft = response["drafts"][0];
        assert draft["can_apply"] and draft["total_cents"] == 259500;
        assert api.journey_state(id)["journey"] is None and api.list_items(id) == [];
        api.assistant_review(id, draft["id"], True, True);
        items = api.list_items(id); saved = api.journey_state(id);
        assert len(items) == 8 and len(saved["journey"]["stops"]) == 3 and not saved["issues"];
        returning = next(item for item in items if item.title == "Return");
        assert returning.time == "16:00" and returning.journey["arrival_time"] == "14:00" and returning.duration_minutes == 720;
        assert len(api.load_trip_map(id)["journey"]["legs"]) == 4;
        api.assistant_review(id, draft["id"], True, True); assert len(api.list_items(id)) == 8;
    }
}

test "journey rejects missing legs and impossible arrival or city activity" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); state = api.replan_state(id); check = unittest.TestCase();
        for kind in ["missing", "early", "wrong_city", "duration", "duplicate", "outside"] {
            bad = plan();
            if kind == "missing" { bad["changes"].pop(); }
            elif kind == "early" { bad["changes"][4]["time"] = "13:00"; }
            elif kind == "wrong_city" { bad["changes"][4]["stop_id"] = "foreign"; }
            elif kind == "duration" { bad["changes"][0]["duration_minutes"] = 60; }
            elif kind == "duplicate" { bad["changes"].append(deepcopy(bad["changes"][0])); }
            else { bad["journey"]["stops"][0]["arrival_date"] = "2026-12-31"; }
            with check.assertRaises(ValueError) { check_plan(state, {}, bad); }
        }
        assert api.list_items(id) == [];
    }
}

test "journey route changes invalidate drafts and stale editors without partial writes" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); before = api.journey_state(id); draft = send(id, plan())["drafts"][0];
        saved = api.save_journey(id, route(), before["version"]);
        assert len(saved["issues"]) == 4;
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { api.assistant_review(id, draft["id"], True, True); }
        with check.assertRaises(ValueError) { api.save_journey(id, route(), before["version"]); }
        assert api.list_items(id) == [];
        fresh = send(id, plan())["drafts"][0]; api.assistant_review(id, fresh["id"], False, False);
        assert api.list_items(id) == [] and api.journey_state(id)["journey"] == saved["journey"];
    }
}

test "journey manual edits preserve zones and reject impossible transfers transactionally" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); draft = send(id, plan())["drafts"][0]; api.assistant_review(id, draft["id"], True, True);
        item = next(i for i in api.list_items(id) if i.title == "Kyoto walk"); check = unittest.TestCase();
        with check.assertRaises(ValueError) { api.save_item(id, item.title, item.category, item.date, "12:45", item.location, "", item.notes, "0", item.id); }
        assert next(i for i in api.list_items(id) if i.id == item.id).time == "14:00";
        updated = api.save_item(id, item.title, item.category, item.date, "14:30", item.location, "", item.notes, "0", item.id);
        assert updated.journey["arrival_time"] == "16:30";
        with check.assertRaises(ValueError) { api.save_trip("Japan", "Tokyo", "2027-01-01", "2027-01-05", "USD", "8000", "", id); }
        with check.assertRaises(ValueError) { api.save_trip("Japan", "Tokyo", "2026-12-31", "2027-01-07", "USD", "8000", "", id); }
    }
}

test "journey schema rejects invalid zones duplicate stops order and DST ambiguity" {
    trip = {"start_date": "2027-01-01", "end_date": "2027-01-07"}; check = unittest.TestCase();
    for kind in ["zone", "duplicate", "order", "coordinates"] {
        bad = route();
        if kind == "zone" { bad["origin"]["zone"] = "Mars/Olympus"; }
        elif kind == "duplicate" { bad["stops"][1]["id"] = "tokyo"; }
        elif kind == "order" { bad["legs"][1]["to_id"] = "osaka"; }
        else { bad["origin"]["lat"] = 500; bad["origin"]["lon"] = 0; }
        with check.assertRaises(ValueError) { journey.normalize(bad, trip); }
    }
    with check.assertRaises(ValueError) { journey.instant("2027-03-14T02:30", "America/Detroit"); }
    with check.assertRaises(ValueError) { journey.instant("2027-11-07T01:30", "America/Detroit"); }
    assert journey.instant("2027-01-07T16:00", "Asia/Tokyo") < journey.instant("2027-01-07T14:00", "America/Detroit");
}

test "journey one-way routes need outbound and intercity transport but no invented return" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); proposal = plan(); proposal["journey"]["return_to"] = None; proposal["journey"]["legs"].pop(); proposal["changes"].pop();
        draft = send(id, proposal)["drafts"][0]; api.assistant_review(id, draft["id"], True, True);
        assert api.list_trips()[0].return_location == "" and len(api.journey_state(id)["journey"]["legs"]) == 3;
    }
}

test "journey rejects conflicting city edits and overlapping manual activities" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); draft = send(id, plan())["drafts"][0]; api.assistant_review(id, draft["id"], True, True);
        check = unittest.TestCase(); state = api.replan_state(id);
        with check.assertRaises(ValueError) { check_plan(state, {}, {"title": "Different origin", "summary": "", "changes": [], "trip_changes": {"departure_location": "Boston"}}); }
        with check.assertRaises(ValueError) { api.save_item(id, "Overlapping lunch", "food", "2027-01-04", "15:00", "Kyoto", "", "", "0", "", {"stop_id": "kyoto"}, 60); }
        assert len(api.list_items(id)) == 8;
        changed = route(); changed["stops"][1]["city"] = "Nagoya";
        with check.assertRaises(ValueError) { api.save_journey(id, changed, api.journey_state(id)["version"]); }
        assert api.journey_state(id)["journey"]["stops"][1]["city"] == "Kyoto";
        outbound = next(i for i in api.list_items(id) if i.title == "Outbound");
        api.replan_save_rules(id, outbound.id, 840, "2027-01-01T12:30", False);
        with check.assertRaises(ValueError) { api.replan_save_rules(id, outbound.id, 60, "", False); }
        assert next(i for i in api.list_items(id) if i.id == outbound.id).duration_minutes == 840;
    }
}

test "journey backup reschedules preserve city timing and reject cross-city sample replacements" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        id = create(); draft = send(id, plan())["drafts"][0]; api.assistant_review(id, draft["id"], True, True);
        state = api.replan_state(id); item = next(i for i in state["items"] if i["title"] == "Kyoto walk");
        candidate = {"action": "reschedule", "replaces_id": item["id"], "item": {"start": {"local": "2027-01-04T14:30", "zone": "Asia/Tokyo"}, "end": {"local": "2027-01-04T16:30", "zone": "Asia/Tokyo"}}};
        result = journey.replacement_items(state, [candidate]);
        assert result[item["id"]]["journey"]["arrival_time"] == "16:30";
        check = unittest.TestCase(); candidate["item"]["start"]["local"] = "2027-01-04T12:00";
        with check.assertRaises(ValueError) { journey.replacement_items(state, [candidate]); }
        candidate["action"] = "replace";
        with check.assertRaises(ValueError) { journey.replacement_items(state, [candidate]); }
        with check.assertRaises(ValueError) { build_combination(state, {"item_id": item["id"], "type": "interrupted"}, [item["id"]], {}); }
    }
}
