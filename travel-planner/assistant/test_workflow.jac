"""Isolated AI integration regressions; model responses are mocked, never paid calls."""
import os;
import json;
import tempfile;
import sqlite3;
import unittest;
import from copy { deepcopy }
import from uuid { uuid4 }
import from unittest.mock { patch }
import assistant.provider as provider;
import server.main as service;
import from assistant.workflow { check_plan }

def trip -> str {
    return service.save_trip("AI test", "Boston", "2027-01-01", "2027-01-03", "USD", "500").id;
}
def change(item_id: str = "", cost: any = 2000) -> dict[str, any] {
    return {"item_id": item_id, "title": "Museum visit", "category": "activity", "date": "2027-01-01",
        "time": "10:00", "duration_minutes": 60, "location": "Boston", "cost_cents": cost, "notes": "Estimated admission; verify hours."};
}
def result(changes: any = None) -> dict[str, any] {
    return {"answer": "Here is an estimated option.", "sources": [{"url": "https://example.com/museum", "title": "Museum source"}],
        "plans": [{"title": "Museum morning", "summary": "An indoor alternative.", "changes": changes if changes is not None else [change()]}]};
}
def send(id: str, response: dict[str, any], request_id: str = "") -> dict[str, any] {
    with patch.object(provider, "generate", return_value=response), patch.object(provider, "repair", return_value=response) {
        return service.assistant_chat(id, "Plan my museum visit", "plan", True, request_id or str(uuid4()));
    }
}

test "search never writes items and explicit reviewed acceptance is atomic and idempotent" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); request_id = str(uuid4());
        with patch.object(provider, "generate", return_value=result()) as model {
            state = service.assistant_chat(id, "Plan my museum visit", "plan", True, request_id);
            assert len(state["messages"]) == 2 and len(state["drafts"]) == 1;
            replay = service.assistant_chat(id, "Plan my museum visit", "plan", True, request_id);
            assert model.call_count == 1 and len(replay["messages"]) == 2;
        }
        assert service.list_items(id) == [];
        draft = state["drafts"][0]; assert draft["can_apply"] and draft["total_cents"] == 2000;
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { service.assistant_review(id, draft["id"], True, False); }
        assert service.list_items(id) == [];
        accepted = service.assistant_review(id, draft["id"], True, True);
        assert accepted["drafts"][0]["status"] == "accepted";
        assert len(service.list_items(id)) == 1 and service.list_items(id)[0].cost_cents == 2000;
        service.assistant_review(id, draft["id"], True, True);
        assert len(service.list_items(id)) == 1;
    }
}

test "trip-specific chat, foreign reviews and rejection preserve saved state" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); other = trip(); state = send(id, result()); draft = state["drafts"][0];
        assert service.assistant_state(other)["messages"] == [];
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { service.assistant_review(other, draft["id"], True, True); }
        rejected = service.assistant_review(id, draft["id"], False, False);
        assert rejected["drafts"][0]["status"] == "rejected" and service.list_items(id) == [];
        with check.assertRaises(ValueError) { service.assistant_review(id, draft["id"], True, True); }
        with check.assertRaises(ValueError) { service.assistant_review(id, draft["id"], "true", True); }
    }
}

test "changed trip rejects old drafts and in-flight writes produce stale proposals" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); draft = send(id, result())["drafts"][0];
        service.save_item(id, "Passport", "packing");
        assert service.assistant_state(id)["drafts"][0]["status"] == "stale";
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { service.assistant_review(id, draft["id"], True, True); }
        def changed(*args: any, **kwargs: any) -> any { service.save_item(id, "Charger", "packing"); return result(); }
        with patch.object(provider, "generate", side_effect=changed) {
            state = service.assistant_chat(id, "Plan", "plan", False, str(uuid4()));
        }
        assert all(d["status"] == "stale" for d in state["drafts"]);
        assert len(service.list_items(id)) == 2;
    }
}

test "unknown price, expired drafts, protected items, foreign IDs and broken constraints cannot be applied" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); check = unittest.TestCase();
        unknown = send(id, result([change(cost=None)]))["drafts"][0];
        assert unknown["total_cents"] is None and not unknown["can_apply"];
        with check.assertRaises(ValueError) { service.assistant_review(id, unknown["id"], True, True); }
        draft = send(id, result())["drafts"][0];
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        conn.execute("UPDATE assistant_drafts SET expires='2000-01-01T00:00:00+00:00' WHERE id=?", (draft["id"],)); conn.commit(); conn.close();
        with check.assertRaises(ValueError) { service.assistant_review(id, draft["id"], True, True); }
        state = service.replan_state(id);
        invalid = [change("foreign"), {**change(), "cost_cents": True}, {**change(), "cost_cents": 999999},
            {**change(), "date": "2027-01-05"}, {**change(), "time": "25:00"}, {**change(), "duration_minutes": 0}];
        for value in invalid {
            with check.assertRaises(ValueError) { check_plan(state, {}, result([value])["plans"][0]); }
        }
        with check.assertRaises(ValueError) { check_plan(state, {}, result([change(), change()])["plans"][0]); }
        item = service.save_item(id, "Fixed museum", "activity", "2027-01-01", "10:00", cost="20");
        service.replan_save_rules(id, item.id, 60, "", True);
        with check.assertRaises(ValueError) { check_plan(service.replan_state(id), {}, result([change(item.id)])["plans"][0]); }
        # A reserve is part of the checked total, even when no existing costs exist.
        with check.assertRaises(ValueError) { check_plan(state, {"reserve_minor": 49000}, result()["plans"][0]); }
    }
}

test "failure allows a new request, idempotency cannot be reused, and secrets stay out of context" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); item = service.save_item(id, "Hotel", "stay", "2027-01-02", "15:00", reference="PRIVATE-BOOKING", cost="100");
        request_id = str(uuid4()); check = unittest.TestCase();
        with patch.object(provider, "generate", side_effect=RuntimeError("Provider unavailable")) {
            with check.assertRaises(RuntimeError) { service.assistant_chat(id, "hello", "ask", True, request_id); }
        }
        assert service.assistant_state(id)["messages"] == [];
        with patch.object(provider, "generate", return_value={"answer": "Hello", "sources": [], "plans": []}) as model {
            state = service.assistant_chat(id, "hello", "ask", False, str(uuid4()));
            args = model.call_args[0];
            assert "PRIVATE-BOOKING" not in json.dumps(args[0]);
            assert args[3] == "ask" and args[4] is False;
        }
        assert len(state["messages"]) == 2 and len(service.list_items(id)) == 1;
        with check.assertRaises(ValueError) { service.assistant_chat(id, "different", "ask", True, request_id); }
        with check.assertRaises(ValueError) { service.assistant_chat(id, "hello", "ask", True, "bad-id"); }
        with check.assertRaises(ValueError) { service.assistant_chat(id, "hello", "ask", "false", str(uuid4())); }
    }
}

test "provider request uses web search then strict planning output and keeps source citations" {
    research = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "Museum research",
        "annotations": [{"type": "url_citation", "url": "https://example.com", "title": "Museum"},
            {"type": "url_citation", "url": "javascript:bad", "title": "Unsafe"}]}]}]};
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    with patch.object(provider, "request", side_effect=[research, structured]) as transport {
        reply = provider.generate({"trip": {"destination": "Boston"}}, [], "Plan museums", "plan", True);
        assert len(reply["plans"]) == 1 and len(reply["sources"]) == 1;
        assert transport.call_args_list[0][0][0]["tools"] == [{"type": "web_search", "search_context_size": "low"}];
        assert transport.call_args_list[0][0][0]["max_tool_calls"] == 3;
        assert transport.call_args_list[1][0][0]["text"]["format"]["strict"] is True;
        assert transport.call_args_list[0][0][0]["store"] is False;
    }
    with patch.object(provider, "request", return_value=research) as transport {
        reply = provider.generate({}, [], "Hello", "ask", False);
        assert transport.call_count == 1 and all(tool["type"] != "web_search" for tool in transport.call_args[0][0]["tools"]);
        assert reply["plans"] == [];
    }
}

test "traveler estimates unblock saving without GPT calls or premature itinerary writes" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); check = unittest.TestCase();
        draft = send(id, result([change(cost=None)]))["drafts"][0];
        assert not draft["can_apply"];
        for invalid in [{"0": "-1"}, {"0": "1.001"}, {"0": "NaN"}, {"0": True}, {"-1": "20"}, {"99": "20"}, {"0": "501"}] {
            with check.assertRaises(ValueError) { service.assistant_update_prices(id, draft["id"], invalid); }
            assert not service.assistant_state(id)["drafts"][0]["can_apply"];
        }
        updated = service.assistant_update_prices(id, draft["id"], {"0": "20.15"})["drafts"][0];
        assert updated["can_apply"] and updated["total_cents"] == 2015;
        assert "traveler" in updated["changes"][0]["after"]["notes"];
        assert service.list_items(id) == [];
        with check.assertRaises(ValueError) { service.assistant_update_prices(id, draft["id"], {"0": "25"}); }
        service.assistant_review(id, draft["id"], True, True);
        assert service.list_items(id)[0].cost_cents == 2015;
    }
}

test "missing prices cannot be edited across trips or after a saved-trip edit" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); other = trip(); check = unittest.TestCase();
        draft = send(id, result([change(cost=None)]))["drafts"][0];
        with check.assertRaises(ValueError) { service.assistant_update_prices(other, draft["id"], {"0": "0"}); }
        service.save_item(id, "Passport", "packing");
        with check.assertRaises(ValueError) { service.assistant_update_prices(id, draft["id"], {"0": "20"}); }
    }
}

test "invalid generated plans get one automatic correction before traveler review" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip();
        with patch.object(provider, "generate", return_value=result([change(cost=None)])), patch.object(provider, "repair", return_value=result()) as repair {
            state = service.assistant_chat(id, "Build a complete plan", "plan", False, str(uuid4()));
            assert repair.call_count == 1;
            assert state["drafts"][0]["can_apply"] and state["drafts"][0]["total_cents"] == 2000;
        }
        assert service.list_items(id) == [];
        schema = provider.plan_schema();
        assert schema["properties"]["plans"]["items"]["properties"]["changes"]["items"]["properties"]["cost_cents"]["type"] == "integer";
    }
}

test "trip-only AI edits require review and persist all supported fields without item changes" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); response = result([]);
        response["plans"][0]["trip_changes"] = {"title": "Tokyo spring", "destination": "Tokyo", "start_date": "2027-04-10", "end_date": "2027-04-14", "currency": "JPY", "budget_cents": 20000000, "notes": "Traveling with family", "departure_location": "Detroit (DTW)", "return_location": "Chicago (ORD)"};
        before = service.replan_state(id);
        draft = send(id, response)["drafts"][0];
        assert len(draft["trip_edits"]) == 9 and draft["changes"] == [] and draft["can_apply"];
        assert service.replan_state(id) == before;
        service.assistant_review(id, draft["id"], False, False);
        assert service.replan_state(id) == before;
        draft = send(id, response)["drafts"][0];
        service.assistant_review(id, draft["id"], True, True);
        saved = service.replan_state(id);
        for (key, value) in response["plans"][0]["trip_changes"].items() { assert saved["trip"][key] == value; }
        assert saved["version"] > before["version"] and saved["items"] == [];
        service.assistant_review(id, draft["id"], True, True);
        assert service.replan_state(id) == saved;
    }
}

test "date and item changes are validated and saved together with stable item IDs" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); item = service.save_item(id, "Museum", "activity", "2027-01-01", "10:00", cost="20");
        proposal = result([{**change(item.id), "date": "2027-02-01"}]);
        proposal["plans"][0]["trip_changes"] = {"start_date": "2027-02-01", "end_date": "2027-02-03", "budget_cents": 60000};
        state = service.replan_state(id); check = unittest.TestCase();
        incomplete = deepcopy(proposal["plans"][0]); incomplete["changes"] = [];
        with check.assertRaises(ValueError) { check_plan(state, {}, incomplete); }
        draft = send(id, proposal)["drafts"][0];
        assert service.replan_state(id) == state;
        service.assistant_review(id, draft["id"], True, True);
        saved = service.replan_state(id);
        assert saved["trip"]["start_date"] == "2027-02-01" and saved["trip"]["budget_cents"] == 60000;
        assert len(saved["items"]) == 1 and saved["items"][0]["id"] == item.id and saved["items"][0]["date"] == "2027-02-01";
    }
}

test "trip-edit validation rejects unsupported fields bad dates currencies and locked-item conflicts" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); state = service.replan_state(id); check = unittest.TestCase();
        for delta in [{"id": "foreign"}, {"title": ""}, {"start_date": "2027-02-30"}, {"end_date": "2026-01-01"},
            {"currency": "XYZ"}, {"budget_cents": True}, {"budget_cents": -1}, {"notes": "x" * 5001}] {
            proposal = result([])["plans"][0]; proposal["trip_changes"] = delta;
            with check.assertRaises(ValueError) { check_plan(state, {}, proposal); }
        }
        item = service.save_item(id, "Hotel", "stay", "2027-01-01", "10:00", cost="100");
        service.set_item_state(id, item.id, True, True);
        state = service.replan_state(id);
        for delta in [{"currency": "EUR"}, {"budget_cents": 5000}, {"start_date": "2027-02-01", "end_date": "2027-02-03"}] {
            proposal = result([])["plans"][0]; proposal["trip_changes"] = delta;
            with check.assertRaises(ValueError) { check_plan(state, {}, proposal); }
        }
        proposal = result([{**change(item.id), "category": "stay", "date": "2027-02-01"}])["plans"][0];
        proposal["trip_changes"] = {"start_date": "2027-02-01", "end_date": "2027-02-03"};
        with check.assertRaises(ValueError) { check_plan(state, {}, proposal); }
    }
}

test "ordinary chat can request a trip edit through a function tool without claiming saved changes" {
    tool_call = {"status": "completed", "output": [{"type": "function_call", "name": "prepare_trip_edit", "arguments": json.dumps({"title": "Summer adventure", "budget_cents": 80000})}]};
    proposal = result([]); proposal["plans"][0]["trip_changes"] = {"title": "Summer adventure", "budget_cents": 80000};
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(proposal)}]}]};
    with patch.object(provider, "request", side_effect=[tool_call, structured]) as transport {
        reply = provider.generate({"trip": {"title": "Old title"}}, [], "Rename my trip and increase the budget", "ask", False);
        assert reply["mode"] == "edit" and reply["plans"][0]["trip_changes"]["budget_cents"] == 80000;
        assert transport.call_args_list[0][0][0]["tools"][0]["name"] == "prepare_trip_edit";
        assert transport.call_count == 2;
    }
}

test "planning preferences persist per trip with strict validation and no itinerary changes" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); other = trip(); initial = service.assistant_state(id); check = unittest.TestCase();
        assert initial["preferences"] == {"pet_friendly": False, "pace": "balanced"};
        for (pet, pace, version) in [("true", "relax", initial["trip_version"]), (True, "unknown", initial["trip_version"]), (True, "relax", True)] {
            with check.assertRaises(ValueError) { service.assistant_save_preferences(id, pet, pace, version); }
        }
        same = service.assistant_save_preferences(id, False, "balanced", initial["trip_version"]);
        assert same["trip_version"] == initial["trip_version"];
        saved = service.assistant_save_preferences(id, True, "relax", initial["trip_version"]);
        assert saved["preferences"] == {"pet_friendly": True, "pace": "relax"} and saved["trip_version"] > initial["trip_version"];
        assert service.assistant_state(id)["preferences"] == saved["preferences"];
        assert service.assistant_state(other)["preferences"] == {"pet_friendly": False, "pace": "balanced"};
        assert service.list_items(id) == [];
        with check.assertRaises(ValueError) { service.assistant_save_preferences(id, False, "intense", initial["trip_version"]); }
    }
}

test "saved pet and pace controls reach GPT context and invalidate previously reviewed drafts" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); draft = send(id, result())["drafts"][0]; state = service.assistant_state(id);
        service.assistant_save_preferences(id, True, "intense", state["trip_version"]);
        assert service.assistant_state(id)["drafts"][0]["status"] == "stale";
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { service.assistant_review(id, draft["id"], True, True); }
        with patch.object(provider, "generate", return_value={"answer": "Ready", "plans": [], "sources": []}) as model {
            service.assistant_chat(id, "Plan my trip", "plan", False, str(uuid4()));
            assert model.call_args[0][0]["planning_preferences"] == {"pet_friendly": True, "pace": "intense"};
        }
    }
}

test "all model stages receive pet and pace instructions including automatic repair" {
    research = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "Research"}]}]};
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    context = {"planning_preferences": {"pet_friendly": True, "pace": "relax"}};
    with patch.object(provider, "request", side_effect=[research, structured, structured]) as transport {
        reply = provider.generate(context, [], "Plan", "plan", True);
        provider.repair(context, reply, ["Overlap"]);
        for call in transport.call_args_list {
            instructions = call[0][0]["instructions"];
            assert "Pet-friendly is ON" in instructions and "Relax:" in instructions and "1–2" in instructions;
            assert "Never assume a venue permits pets" in instructions;
        }
    }
    assert "4–6" in provider.preference_instructions({"planning_preferences": {"pet_friendly": False, "pace": "intense"}});
    assert "2–3" in provider.preference_instructions({});
}

test "planning without search and explicit trip edits skip the extra model round trip" {
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    context = {"planning_preferences": {"pet_friendly": True, "pace": "relax"}};
    for (mode, search) in [("plan", False), ("backup", False), ("replan", False), ("edit", False), ("edit", True)] {
        with patch.object(provider, "configuration", return_value={"chat_model": "gpt-6-luna", "planning_model": "gpt-6-luna"}), patch.object(provider, "request", return_value=structured) as transport {
            reply = provider.generate(context, [], "Prepare my changes", mode, search);
            assert transport.call_count == 1 and len(reply["plans"]) == 1;
            body = transport.call_args[0][0];
            assert body["text"]["format"]["strict"] is True and "tools" not in body;
            assert body["model"] == "gpt-6-luna" and body["reasoning"]["effort"] == "none";
            assert "Pet-friendly is ON" in body["instructions"] and "Relax:" in body["instructions"];
            assert "Never assume a venue permits pets" in body["instructions"];
            assert reply["sources"] == [] and reply["research"] == "";
        }
    }
}

test "planning preserves conversation text without resending historical research payloads" {
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    history = [{"role": "user", "text": "My dog weighs 12 kg.", "research": "OLD-RESEARCH-" * 1000,
        "sources": [{"url": "https://example.com/old"}], "issues": ["OLD-REVIEW-METADATA"]}];
    before = deepcopy(history);
    with patch.object(provider, "request", return_value=structured) as transport {
        provider.generate({}, history, "Plan with my dog", "plan", False);
        prompt = transport.call_args[0][0]["input"];
        assert "My dog weighs 12 kg." in prompt;
        assert "OLD-RESEARCH" not in prompt and "OLD-REVIEW-METADATA" not in prompt;
        assert "example.com/old" not in prompt;
    }
    assert history == before;
}

test "pet research is bounded and preserves uncertainty in the structured draft" {
    research = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "One policy found; other policies remain unverified.",
        "annotations": [{"type": "url_citation", "url": "https://example.com/pets", "title": "Pet policy"}]}]}]};
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    with patch.object(provider, "request", side_effect=[research, structured]) as transport {
        reply = provider.generate({"planning_preferences": {"pet_friendly": True, "pace": "balanced"}}, [], "Plan a pet-friendly trip", "plan", True);
        assert transport.call_count == 2;
        lookup = transport.call_args_list[0][0][0]; draft = transport.call_args_list[1][0][0];
        assert lookup["max_tool_calls"] == 3;
        assert "Do not write a full itinerary" in lookup["instructions"];
        assert "Mark remaining policies as unverified" in draft["instructions"];
        assert "other policies remain unverified" in draft["input"];
        assert reply["sources"] == [{"url": "https://example.com/pets", "title": "Pet policy"}];
    }
}

test "fast model effort reaches chat drafts and repair while Sol overrides stay compatible" {
    plain = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "Ready"}]}]};
    structured = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    for model in ["gpt-6-luna", "gpt-6.1-sol"] {
        with patch.object(provider, "configuration", return_value={"chat_model": model, "planning_model": model}), patch.object(provider, "request", side_effect=[plain, structured, structured]) as transport {
            provider.generate({}, [], "Hello", "ask", False);
            draft = provider.generate({}, [], "Plan", "plan", False);
            provider.repair({}, draft, ["Overlap"]);
            for (index, call) in enumerate(transport.call_args_list) {
                body = call[0][0];
                assert body["model"] == model;
                assert body["reasoning"]["effort"] == ("none" if model == "gpt-6-luna" else "low" if index == 0 else "medium");
            }
        }
    }
}

test "personal keys reach research structured drafts and repair without entering prompts" {
    key = "sk-test-personal-key";
    research = {"output": [{"type": "message", "content": [{"type": "output_text", "text": "Museum research"}]}]};
    structured = {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(result())}]}]};
    with patch.object(provider, "request", side_effect=[research, structured, structured]) as transport {
        draft = provider.generate({}, [], "Plan", "plan", True, key);
        provider.repair({}, draft, ["Overlap"], key);
        assert transport.call_count == 3;
        for call in transport.call_args_list {
            assert call.args[1] == key;
            assert key not in json.dumps(call.args[0]);
        }
    }
}

test "personal keys override server credentials per request without modifying the environment" {
    key = "sk-test-personal-key";
    with patch.object(provider, "setting", return_value="sk-test-server-key"), patch.object(provider.urllib.request, "urlopen") as transport {
        transport.return_value.__enter__.return_value.read.return_value = b'{"status":"completed"}';
        before = os.environ.get("OPENAI_API_KEY");
        provider.request({"input": "Hello"}, key);
        personal = transport.call_args.args[0];
        assert personal.get_header("Authorization") == "Bearer " + key;
        assert key not in personal.data.decode();
        provider.request({"input": "Hello"});
        assert transport.call_args.args[0].get_header("Authorization") == "Bearer sk-test-server-key";
        assert os.environ.get("OPENAI_API_KEY") == before;
    }
}

test "personal credentials are passed through the service but never saved" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip(); key = "sk-test-private-key";
        with patch.object(provider, "generate", return_value=result([change(cost=None)])) as model, patch.object(provider, "repair", return_value=result()) as repair {
            state = service.assistant_chat(id, "Plan", "plan", False, str(uuid4()), key);
            assert model.call_args.args[-1] == key and repair.call_args.args[-1] == key;
            assert key not in json.dumps(model.call_args.args[:-1]);
            assert key not in json.dumps(state);
        }
        with sqlite3.connect(os.path.join(directory, "trip.sqlite3")) as conn {
            assert key not in "\n".join(conn.iterdump());
        }
    }
}

test "invalid key input is rejected before a network request" {
    check = unittest.TestCase();
    with patch.object(provider.urllib.request, "urlopen") as transport {
        for key in ["wrong", "sk-key\nInjected: header", "sk-" + "x" * 512] {
            with check.assertRaises(ValueError) { provider.request({}, key); }
        }
        assert transport.call_count == 0;
    }
}


test "saved route endpoints reach the assistant and changing them makes drafts stale" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = trip();
        service.save_trip("AI test", "Boston", "2027-01-01", "2027-01-03", "USD", "500", trip_id=id,
            departure_location="Detroit", return_location="Chicago");
        with patch.object(provider, "generate", return_value=result()) as model {
            state = service.assistant_chat(id, "Plan a museum visit", "plan", False, str(uuid4()));
            supplied = model.call_args[0][0]["trip"];
            assert supplied["departure_location"] == "Detroit" and supplied["return_location"] == "Chicago";
        }
        service.save_trip("AI test", "Boston", "2027-01-01", "2027-01-03", "USD", "500", trip_id=id, return_location="Detroit");
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { service.assistant_review(id, state["drafts"][0]["id"], True, True); }
        assert service.list_items(id) == [];
    }
}
