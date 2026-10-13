"""Travel endpoint tests use isolated temporary databases, never saved trip data."""
import os;
import tempfile;
import sqlite3;
import from jaclang.testing.testing { JacTestClient }
import replan.agent as replan_agent;
import from jaclang.byllm.lib { MockLLM }
import from replan.agent { ReplanSelection }

glob SERVER: str = os.path.join(os.path.dirname(__file__), "main.jac");

test "trip lifecycle, editing, exact currency amounts, state and cascade deletion" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
        try {
            trip = client.post("/function/save_trip", json={"title": "Kyoto week", "destination": "Kyoto, Japan", "start_date": "2026-11-01", "end_date": "2026-11-07", "budget": "2500.10"}).data["result"];
            assert trip["budget_cents"] == 250010;
            booking = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Hotel", "category": "stay", "date": "2026-11-01", "reference": "ABC123", "cost": "900.99"}).data["result"];
            assert booking["cost_cents"] == 90099;
            updated = client.post("/function/set_item_state", json={"trip_id": trip["id"], "item_id": booking["id"], "done": True, "paid": True}).data["result"];
            assert updated["done"] and updated["paid"];
            edited = client.post("/function/save_item", json={"trip_id": trip["id"], "item_id": booking["id"], "title": "Hotel, updated", "category": "stay", "date": "2026-11-02", "cost": "950.50"}).data["result"];
            assert edited["id"] == booking["id"] and edited["cost_cents"] == 95050;
            assert edited["done"] and edited["paid"];
            cleared = client.post("/function/save_item", json={"trip_id": trip["id"], "item_id": booking["id"], "title": "Hotel, free", "category": "stay", "cost": "0"}).data["result"];
            assert cleared["paid"] is False;
            packed = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Passport", "category": "packing"}).data["result"];
            assert packed["cost_cents"] == 0;
            assert client.post("/function/delete_item", json={"trip_id": trip["id"], "item_id": packed["id"]}).data["result"] is True;
            assert client.post("/function/delete_item", json={"trip_id": trip["id"], "item_id": packed["id"]}).data["result"] is False;
            assert client.post("/function/delete_trip", json={"trip_id": trip["id"]}).data["result"] is True;
            assert client.post("/function/list_trips", json={}).data["result"] == [];
            conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
            try { assert conn.execute("SELECT count(*) FROM items").fetchone()[0] == 0; }
            finally { conn.close(); }
        } finally { client.close(); }
    }
}

test "validation rejects invalid dates amounts trip bounds and foreign item IDs" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
        try {
            base = {"title": "Autumn trip", "destination": "Boston", "start_date": "2026-10-10", "end_date": "2026-10-15"};
            for invalid in [
                {"title": " "}, {"start_date": "2026-02-30"}, {"end_date": "2026-10-01"},
                {"budget": "-1"}, {"budget": "1.234"}, {"budget": "NaN"}, {"currency": "XYZ"}
            ] {
                body = base.copy(); body.update(invalid);
                response = client.post("/function/save_trip", json=body);
                assert not response.ok, str(body);
            }
            trip = client.post("/function/save_trip", json=base).data["result"];
            second = client.post("/function/save_trip", json=base).data["result"];
            for invalid_item in [
                {"date": "2026-10-16"}, {"date": "2026-10-09"}, {"time": "09:00"},
                {"date": "2026-10-10", "time": "24:00"}, {"cost": "-1"},
                {"category": "packing", "cost": "10"}, {"category": "packing", "date": "2026-10-10"},
                {"category": "unknown"}, {"title": " "}, {"trip_id": "missing"}
            ] {
                body = {"trip_id": trip["id"], "title": "An item"}; body.update(invalid_item);
                assert not client.post("/function/save_item", json=body).ok, str(body);
            }
            item = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Museum", "date": "2026-10-14", "cost": "0.10"}).data["result"];
            assert not client.post("/function/set_item_state", json={"trip_id": second["id"], "item_id": item["id"], "done": True, "paid": True}).ok;
            assert not client.post("/function/save_item", json={"trip_id": second["id"], "item_id": item["id"], "title": "Moved"}).ok;
            edit_trip = base.copy(); edit_trip.update({"trip_id": trip["id"], "end_date": "2026-10-12"});
            assert not client.post("/function/save_trip", json=edit_trip).ok;
            edit_trip["end_date"] = "2026-10-15"; edit_trip["currency"] = "EUR";
            assert not client.post("/function/save_trip", json=edit_trip).ok;
            assert client.post("/function/delete_item", json={"trip_id": second["id"], "item_id": item["id"]}).data["result"] is False;
            assert len(client.post("/function/list_items", json={"trip_id": trip["id"]}).data["result"]) == 1;
        } finally { client.close(); }
    }
}

test "independent server sessions preserve data and itinerary ordering" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        first = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "first"));
        try {
            trip = first.post("/function/save_trip", json={"title": "Weekend", "destination": "Chicago", "start_date": "2026-12-01", "end_date": "2026-12-03", "notes": "Remember the train tickets"}).data["result"];
            for (title, date, time) in [("Undated idea", "", ""), ("Flexible", "2026-12-02", ""), ("Morning", "2026-12-02", "09:00"), ("Earlier", "2026-12-01", "18:00")] {
                first.post("/function/save_item", json={"trip_id": trip["id"], "title": title, "date": date, "time": time});
            }
        } finally { first.close(); }
        second = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "second"));
        try {
            assert second.post("/function/list_trips", json={}).data["result"][0]["notes"] == "Remember the train tickets";
            items = second.post("/function/list_items", json={"trip_id": trip["id"]}).data["result"];
            assert [item["title"] for item in items] == ["Earlier", "Morning", "Flexible", "Undated idea"];
        } finally { second.close(); }
    }
}

# Direct service tests use temporary SQLite databases and no external providers.

# These exercise the same public functions used by the web app, without HTTP auth storage.
test "delay combines backups and acceptance preserves fixed items and boundaries" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"];
        before = replan_state(trip);
        disrupted = [i for i in before["items"] if i["title"] == "Flight arrival"][0];
        fixed = [i for i in before["items"] if i["fixed"]][0];
        result = propose_replan(trip, disrupted["id"], "delayed", 180);
        assert len(result["proposals"]) == 3;
        assert replan_state(trip)["version"] == before["version"];
        assert replan_state(trip)["items"] == before["items"];
        first = result["proposals"][0];
        assert len([c for c in first["changes"] if c["backup_id"]]) == 2;
        assert fixed["id"] not in [c["item_id"] for c in first["changes"]];
        assert review_replan(trip, first["id"], True)["status"] == "accepted";
        after = replan_state(trip);
        assert after["version"] > before["version"];
        assert [i for i in after["items"] if i["id"] == fixed["id"]][0] == fixed;
        assert sum([i["cost_cents"] for i in after["items"]]) == first["projected_total_cents"];
        caught = False;
        try { review_replan(trip, first["id"], True); } except ValueError { caught = True; }
        assert caught;
    }
}

test "reject and manual combination never mutate the active itinerary until acceptance" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"]; before = replan_state(trip);
        disrupted = [i for i in before["items"] if i["category"] == "food"][0];
        result = propose_replan(trip, disrupted["id"], "interrupted");
        assert len(result["proposals"]) == 3;
        assert review_replan(trip, result["proposals"][0]["id"], False)["status"] == "rejected";
        assert replan_state(trip)["items"] == before["items"];
        selected = result["backups"][0];
        custom = combine_replan(trip, result["event_id"], {disrupted["id"]: selected["id"]});
        assert custom["mode"] == "custom";
        assert custom["proposals"][0]["changes"][0]["backup_id"] == selected["id"];
        assert replan_state(trip)["version"] == before["version"];
        caught = False;
        try { combine_replan(trip, result["event_id"], {disrupted["id"]: "invented-backup"}); } except ValueError { caught = True; }
        assert caught;
        assert review_replan(trip, custom["proposals"][0]["id"], True)["status"] == "accepted";
    }
}

test "manual edits invalidate patches and duplicate event IDs cannot apply twice" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"]; state = replan_state(trip);
        disrupted = [i for i in state["items"] if i["title"] == "Flight arrival"][0];
        old = propose_replan(trip, disrupted["id"], "delayed", 180, "event-one");
        set_item_state(trip, disrupted["id"], False, True);
        caught = False;
        try { review_replan(trip, old["proposals"][0]["id"], True); } except ValueError { caught = True; }
        assert caught;
        fresh = propose_replan(trip, disrupted["id"], "delayed", 180, "event-one");
        assert fresh["event_id"] == old["event_id"];
        assert review_replan(trip, fresh["proposals"][0]["id"], True)["status"] == "accepted";
        caught = False;
        try { propose_replan(trip, disrupted["id"], "delayed", 180, "event-one"); } except ValueError { caught = True; }
        assert caught;
    }
}

test "fixed conflicts, cycles, invalid inputs and unknown timestamps are rejected" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"]; state = replan_state(trip);
        disrupted = [i for i in state["items"] if i["title"] == "Flight arrival"][0];
        car = [i for i in state["items"] if i["title"] == "Rental-car pickup"][0];
        replan_save_rules(trip, car["id"], 30, "2026-11-01T17:00", True);
        conflict = propose_replan(trip, disrupted["id"], "delayed", 180);
        assert conflict["proposals"] == [];
        assert "Fixed or completed" in conflict["warnings"][0];
        caught = False;
        try { replan_save_dependency(trip, car["id"], disrupted["id"], 0); } except ValueError { caught = True; }
        assert caught;
        assert len(replan_state(trip)["dependencies"]) == 4;
        undated = save_item(trip, "Unscheduled idea");
        caught = False;
        try { propose_replan(trip, undated.id, "delayed", 10); } except ValueError { caught = True; }
        assert caught;
        caught = False;
        try { propose_replan(trip, disrupted["id"], "delayed", -10); } except ValueError { caught = True; }
        assert caught;
    }
}

test "paid interrupted items retain prior payments and do not invent refunds" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"]; state = replan_state(trip);
        dinner = [i for i in state["items"] if i["category"] == "food"][0];
        set_item_state(trip, dinner["id"], False, True);
        result = propose_replan(trip, dinner["id"], "interrupted");
        proposal = result["proposals"][0];
        assert proposal["retained_paid_cents"] == dinner["cost_cents"];
        review_replan(trip, proposal["id"], True);
        after = replan_state(trip);
        expenses = [i for i in after["items"] if i["category"] == "expense"];
        assert len(expenses) == 1 and expenses[0]["paid"];
        assert sum([i["cost_cents"] for i in after["items"]]) == proposal["projected_total_cents"];
        assert not [i for i in after["items"] if i["id"] == dinner["id"]][0]["paid"];
    }
}

test "Jac by llm selects supplied combinations and rejects hallucinated IDs" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"];
        dinner = [i for i in replan_state(trip)["items"] if i["category"] == "food"][0];
        original_model = replan_agent.replan_model;
        try {
            replan_agent.replan_model = MockLLM(outputs=[ReplanSelection(combination_ids=["combination-1", "combination-3"], explanation="Two supplied mock backup combinations.")]);
            result = propose_replan(trip, dinner["id"], "interrupted", use_llm=True);
            assert result["mode"] == "llm", str(result["warnings"]);
            assert len(result["proposals"]) == 2;
            replan_agent.replan_model = MockLLM(outputs=[ReplanSelection(combination_ids=["invented"], explanation="Unsupported")]);
            fallback = propose_replan(trip, dinner["id"], "interrupted", use_llm=True);
            assert fallback["mode"] == "mock";
            assert "LLM selection unavailable or invalid" in fallback["warnings"][-1];
        } finally { replan_agent.replan_model = original_model; }
    }
}

test "budget violations and independent fixed timing boundaries block repairs" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"]; state = replan_state(trip);
        dinner = [i for i in state["items"] if i["category"] == "food"][0];
        conn = _connect();
        try { conn.execute("UPDATE trips SET budget_cents=1 WHERE id=?", (trip,)); conn.commit(); }
        finally { conn.close(); }
        impossible = propose_replan(trip, dinner["id"], "interrupted");
        assert impossible["proposals"] == [];
        assert "Repair exceeds the trip budget" in impossible["warnings"];
        conn = _connect();
        try { conn.execute("UPDATE trips SET budget_cents=150000 WHERE id=?", (trip,)); conn.commit(); }
        finally { conn.close(); }
        # This item has no dependency edge: full-trip validation must still catch the overlap.
        boundary = save_item(trip, "Independent fixed show", "activity", "2026-11-01", "20:00");
        replan_save_rules(trip, boundary.id, 60, "2026-11-01T20:00", True);
        flight = [i for i in state["items"] if i["title"] == "Flight arrival"][0];
        revised = propose_replan(trip, flight["id"], "delayed", 180);
        for proposal in revised["proposals"] {
            assert boundary.id not in [c["item_id"] for c in proposal["changes"]];
        }
        assert any(["Schedule overlap" in warning for warning in revised["warnings"]]);
    }
}

test "failed application rolls back changes retained payments and event status" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        trip = replan_demo()["trip_id"];
        dinner = [i for i in replan_state(trip)["items"] if i["category"] == "food"][0];
        set_item_state(trip, dinner["id"], False, True);
        before = replan_state(trip);
        proposal = propose_replan(trip, dinner["id"], "interrupted")["proposals"][0];
        conn = _connect();
        try {
            conn.execute("CREATE TRIGGER fail_simulated_write BEFORE UPDATE ON items BEGIN SELECT RAISE(ABORT, 'test failure'); END");
            conn.commit();
        } finally { conn.close(); }
        caught = False;
        try { review_replan(trip, proposal["id"], True); } except sqlite3.IntegrityError { caught = True; }
        assert caught;
        assert replan_state(trip)["items"] == before["items"];
        assert replan_state(trip)["version"] == before["version"];
        conn = _connect();
        try { conn.execute("DROP TRIGGER fail_simulated_write"); conn.commit(); }
        finally { conn.close(); }
        assert review_replan(trip, proposal["id"], True)["status"] == "accepted";
    }
}
