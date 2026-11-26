"""Regressions for the ordinary saved-trip Replan audit; no paid model calls."""
import from tests.workspace_fixture { TEST_WORKSPACE }
import os;
import tempfile;
import unittest;
import from copy { deepcopy }
import from datetime { datetime, timedelta, timezone }
import from unittest.mock { patch }
import from uuid { uuid4 }
import assistant.provider as provider;
import tools.map_providers as maps;
import server.main as service;
import from assistant.workflow { check_plan }
import from planning.fixtures { sample_state }
import from replan.connections { validate_connections }

test "saved-item summaries use checked arithmetic even when the model contradicts itself" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        trip = service.save_trip(TEST_WORKSPACE, "Chicago regression", "Chicago", "2027-01-01", "2027-01-02", "USD", "600");
        museum = service.save_item(TEST_WORKSPACE, trip.id, "Architecture Center", "activity", "2027-01-01", "10:00", "Chicago", cost="15");
        service.save_item(TEST_WORKSPACE, trip.id, "Other costs", "expense", cost="50");
        service.replan_save_rules(TEST_WORKSPACE, trip.id, museum.id, 90, "", False);
        response = {"answer":"Cannot fit; the revised total is $80 (was $55).", "plans":[{
            "title":"Later museum", "summary":"Impossible overlap, total $80.", "changes":[{
                "item_id":museum.id, "title":museum.title, "category":"activity", "date":"2027-01-01", "time":"15:30",
                "duration_minutes":90, "location":"Chicago", "cost_cents":2500, "notes":"Estimated admission"}]}]};
        with patch.object(provider, "generate", return_value=response) {
            result = service.assistant_chat(TEST_WORKSPACE, trip.id, "Move the museum to 15:30, $25; keep everything else", "replan", False, str(uuid4()));
        }
        text = result["messages"][-1]["text"]; draft = result["drafts"][0];
        assert "USD 65.00 → USD 75.00" in text and "15:30" in text;
        assert "$80" not in text and "Cannot fit" not in text and "Impossible" not in draft["summary"];
        assert draft["original_total_cents"] == 6500 and draft["total_cents"] == 7500;
        before = [(i.id, i.title, i.date, i.time, i.cost_cents, i.notes) for i in service.list_items(TEST_WORKSPACE, trip.id)];
        service.assistant_review(TEST_WORKSPACE, trip.id, draft["id"], False, False);
        assert [(i.id, i.title, i.date, i.time, i.cost_cents, i.notes) for i in service.list_items(TEST_WORKSPACE, trip.id)] == before;
    }
}

test "large drafts with long generated summaries can still be priced and saved" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        trip = service.save_trip(TEST_WORKSPACE, "Long draft", "Chicago", "2027-01-01", "2027-01-03", "USD", "1000");
        changes = [];
        for index in range(30) {
            changes.append({"item_id":"", "title":("Stop " + str(index) + " ").ljust(160, "x"), "category":"activity",
                "date":"2027-01-0" + str(1 + index // 10), "time":str(8 + index % 10).zfill(2) + ":00", "duration_minutes":30,
                "location":"Chicago", "cost_cents":None if index == 0 else 0, "notes":"Estimate"});
        }
        response = {"answer":"Draft", "plans":[{"title":"Busy trip", "summary":"Many stops.", "changes":changes}]};
        # The missing price triggers a repair request; return the same draft.
        with patch.object(provider, "generate", return_value=response), patch.object(provider, "repair", return_value=response) {
            result = service.assistant_chat(TEST_WORKSPACE, trip.id, "Plan a busy trip", "plan", False, str(uuid4()));
        }
        draft = result["drafts"][0];
        assert len(draft["summary"]) > 5000;
        priced = service.assistant_update_prices(TEST_WORKSPACE, trip.id, draft["id"], {"0":"5"});
        assert priced["drafts"][0]["can_apply"];
        with patch.object(maps, "search_places", return_value=[]) {
            service.assistant_review(TEST_WORKSPACE, trip.id, draft["id"], True, True);
        }
        assert len([i for i in service.list_items(TEST_WORKSPACE, trip.id) if i.category == "activity"]) == 30;
    }
}

test "assistant and saved-trip validation enforce the longest evidenced transfer" {
    now = datetime.now(timezone.utc); (state, facts) = sample_state(now);
    day = state["trip"]["start_date"];
    facts["evidence"].append({"id":"route-proof", "source_ref":"fixture://route", "retrieved_at":now.isoformat()});
    facts["evidence_deadlines"]["route-proof"] = (now + timedelta(minutes=5)).isoformat();
    facts["travel_estimates"] = [{"from_node_id":"arrival", "to_node_id":"activity", "minutes":90, "evidence_id":"route-proof"}];
    original = next(i for i in state["items"] if i["id"] == "activity");
    proposed = {**original, "item_id":"activity", "time":"10:20"};
    plan = {"title":"Too short", "summary":"Looks fine", "changes":[proposed]};
    check = unittest.TestCase();
    with check.assertRaisesRegex(ValueError, "90 minutes") { check_plan(state, facts, plan); }
    proposed["time"] = "11:30";
    assert check_plan(state, facts, plan)["can_apply"];
    nodes = {i["id"]:deepcopy(i) for i in state["items"]}; nodes["activity"]["time"] = "11:30";
    validate_connections(state, nodes, facts, now);
    with check.assertRaisesRegex(ValueError, "expired") { validate_connections(state, nodes, facts, now + timedelta(minutes=6)); }
    nodes["activity"]["location"] = "A different venue";
    with check.assertRaisesRegex(ValueError, "Refresh travel time") { validate_connections(state, nodes, facts, now); }
}

test "saved reschedules retain venue-bound routes and location edits invalidate them" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        saved = service.create_planning_demo(TEST_WORKSPACE); trip_id = saved["trip_id"];
        before = service.planning_state(TEST_WORKSPACE, trip_id); item = next(i for i in service.list_items(TEST_WORKSPACE, trip_id) if i.category == "activity");
        assert before["facts"]["transfers"];
        service.save_item(TEST_WORKSPACE, trip_id, item.title, item.category, item.date, "11:30", item.location, item.reference, item.notes, str(item.cost_cents / 100), item.id);
        after = service.planning_state(TEST_WORKSPACE, trip_id);
        assert after["facts"]["transfers"] == before["facts"]["transfers"];
        service.save_item(TEST_WORKSPACE, trip_id, item.title, item.category, item.date, "11:30", "New venue", item.reference, item.notes, str(item.cost_cents / 100), item.id);
        changed = service.planning_state(TEST_WORKSPACE, trip_id);
        assert all(r["from_id"] != item.id and r["to_id"] != item.id for r in changed["facts"]["transfers"]);
    }
}

test "backup retries a model refusal against the authoritative rain demo schedule" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        trip_id = service.create_planning_demo(TEST_WORKSPACE)["trip_id"];
        item = next(i for i in service.replan_state(TEST_WORKSPACE, trip_id)["items"] if i["category"] == "activity");
        message = "Move only the Outdoor garden visit to 11:30, keeping the venue, duration and cost.";
        refusal = {"answer":"The fixed arrival transfer ends at 12:00.", "plans":[]};
        proposed = {"answer":"Timing draft", "plans":[{"title":"Later garden visit", "summary":"",
            "changes":[{**item, "item_id":item["id"], "time":"11:30"}]}]};
        with patch.object(provider, "generate", return_value=refusal), patch.object(provider, "repair", return_value=proposed) as retry {
            result = service.assistant_chat(TEST_WORKSPACE, trip_id, message, "backup", False, str(uuid4()));
            assert retry.call_count == 1;
            timeline = retry.call_args.args[0]["saved_timeline"];
            transfer = next(row for row in timeline if row["title"] == "Arrival transfer");
            assert "09:00" in transfer["start"] and "10:00" in transfer["end"] and "America/New_York" in transfer["end"];
            assert retry.call_args.kwargs["message"] == message;
        }
        assert result["drafts"][0]["can_apply"] and result["drafts"][0]["changes"][0]["after"]["time"] == "11:30";
        assert "12:00" not in result["messages"][-1]["text"];
        assert next(i for i in service.list_items(TEST_WORKSPACE, trip_id) if i.id == item["id"]).time == "11:00";
    }
}

test "venue-change drafts retain the proposal and recheck dated evidence before accepting" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        trip_id = service.create_planning_demo(TEST_WORKSPACE)["trip_id"];
        item = next(i for i in service.replan_state(TEST_WORKSPACE, trip_id)["items"] if i["category"] == "activity");
        venue = "Boston Public Library Central Library";
        proposal = {"answer":"Draft", "plans":[{"title":"Indoor visit", "summary":"",
            "changes":[{**item, "item_id":item["id"], "title":"Library visit", "location":venue}]}]};
        with patch.object(provider, "generate", return_value=proposal), patch.object(provider, "repair") as retry {
            result = service.assistant_chat(TEST_WORKSPACE, trip_id, "Move this activity indoors", "replan", False, str(uuid4()));
            retry.assert_not_called();
        }
        draft = result["drafts"][0]; id = draft["id"];
        requirements = draft["connection_requirements"];
        assert len(requirements) == 2 and not draft["can_apply"] and draft["status"] == "pending";
        arriving = next(pair for pair in requirements if pair["to_venue"] == venue);
        assert arriving["from_title"] == "Arrival transfer" and "10:00" in arriving["departure"];
        check = unittest.TestCase();
        with check.assertRaisesRegex(ValueError, "travel-time evidence") { service.assistant_review(TEST_WORKSPACE, trip_id, id, True, True); }
        with check.assertRaisesRegex(ValueError, "each connection") { service.assistant_update_connections(TEST_WORKSPACE, trip_id, id, {}); }
        expires = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat();
        evidence = {pair["id"]: {"minutes":20, "source":"Test route reference", "expires_at":expires} for pair in requirements};
        too_long = deepcopy(evidence); too_long[arriving["id"]]["minutes"] = 90;
        with check.assertRaisesRegex(ValueError, "90 minutes") { service.assistant_update_connections(TEST_WORKSPACE, trip_id, id, too_long); }
        checked = service.assistant_update_connections(TEST_WORKSPACE, trip_id, id, evidence)["drafts"][0];
        assert checked["can_apply"] and not checked["connection_requirements"] and checked["expires"] == expires;
        assert next(i for i in service.list_items(TEST_WORKSPACE, trip_id) if i.id == item["id"]).location == item["location"];
        with patch.object(maps, "search_places", return_value=[]) { service.assistant_review(TEST_WORKSPACE, trip_id, id, True, True); }
        routes = service.planning_state(TEST_WORKSPACE, trip_id)["facts"]["transfers"];
        assert len([route for route in routes if venue in (route["from_venue"], route["to_venue"])]) == 2;
        assert next(i for i in service.list_items(TEST_WORKSPACE, trip_id) if i.id == item["id"]).location == venue;
    }
}
