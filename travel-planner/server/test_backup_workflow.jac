"""Saved-trip pipeline HTTP lifecycle, staleness and database isolation."""
import os;
import uuid;
import sqlite3;
import tempfile;
import from contextlib { contextmanager }
import from unittest.mock { patch }
import from jaclang.testing.testing { JacTestClient }
import from backup.workflow { run_workflow }
import from importlib { import_module }

@contextmanager
def workflow_client -> any {
    names = ["TRAVEL_DB_PATH", "BACKUP_HISTORY_DB_PATH"];
    previous = {name: os.environ.get(name) for name in names};
    with tempfile.TemporaryDirectory() as directory {
        os.environ[names[0]] = os.path.join(directory, "travel.sqlite3");
        os.environ[names[1]] = os.path.join(directory, "history.sqlite3");
        client = JacTestClient.from_file(os.path.join(os.path.dirname(__file__), "main.jac"), base_path=os.path.join(directory, "runtime"));
        try { yield client; }
        finally {
            client.close();
            for name in names {
                if previous[name] is None { os.environ.pop(name, None); }
                else { os.environ[name] = previous[name]; }
            }
        }
    }
}

def call(client: any, name: str, data: dict[str, any]) -> any {
    response = client.post("/function/" + name, json=data);
    assert response.ok, str(response.data);
    return response.data["result"];
}

def setup_trip(client: any, destination: str = "Boston") -> tuple[dict[str, any], dict[str, any], dict[str, any]] {
    trip = call(client, "save_trip", {"title": "Pipeline check", "destination": destination,
        "start_date": "2026-11-15", "end_date": "2026-11-20", "budget": "600"});
    activity = call(client, "save_item", {"trip_id": trip["id"], "title": "Outdoor walk", "date": "2026-11-17", "cost": "15"});
    dinner = call(client, "save_item", {"trip_id": trip["id"], "title": "Dinner", "category": "food", "date": "2026-11-17", "time": "18:00", "cost": "25"});
    return (trip, activity, dinner);
}

def dump_travel -> str {
    conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
    try { return "\n".join(conn.iterdump()); } finally { conn.close(); }
}

def request_for(client: any, session: str, trip: dict[str, any], item: dict[str, any]) -> dict[str, any] {
    state = call(client, "load_trip_backup_history", {"session_id": session, "trip_id": trip["id"]});
    return {"session_id": session, "trip_id": trip["id"], "item_id": item["id"], "request_id": str(uuid.uuid4()),
        "expected_revision": state["revision"], "expected_base_snapshot": state["base_snapshot"],
        "trigger": "arrival_delay" if item["category"] == "food" else "rain", "inventory_change": "unchanged"};
}

test "saved trip searches checks refreshes and persists the same inventory without inventing facts" {
    with workflow_client() as client {
        (trip, activity, dinner) = setup_trip(client); before = dump_travel(); session = str(uuid.uuid4());
        for (item, ids) in [(activity, ["indoor-gallery", "science-hall"]), (dinner, ["late-bistro", "evening-cafe"])] {
            response = call(client, "save_trip_backup_refresh", request_for(client, session, trip, item));
            r = response["report"];
            assert r["scope"] == "saved_trip_mock" and r["summary"]["passed_fixture_checks"] == 0;
            assert r["summary"]["needs_validation"] == 2;
            assert r["pipeline"]["provider_ids"] == ids;
            assert [x["provider_id"] for x in r["results"]] == ids;
            assert r["input_snapshot"]["trip"]["profile"]["adults"] is None;
            assert all(x["cost"]["projected_total_minor"] is None for x in r["results"]);
            assert all(x["observed_candidate"]["item"]["start"]["local"].startswith(item["date"]) for x in r["results"]);
            assert all(edge["minutes"] is None for x in r["input_snapshot"]["candidates"] for edge in x["transfers"]);
            assert response["history"]["entries"][0]["pipeline"]["provider_ids"] == ids;
            assert dump_travel() == before;
        }
        restored = call(client, "load_trip_backup_history", {"session_id": session, "trip_id": trip["id"]});
        assert restored["revision"] == 2 and "report" not in restored;
        assert restored["entries"][1]["recorded_options"][0]["provider_id"] == "indoor-gallery";
    }
}

test "saved backup retries concurrent revisions sessions and sample history stay isolated" {
    with workflow_client() as client {
        (trip, activity, _) = setup_trip(client); (other, other_item, _) = setup_trip(client);
        session = str(uuid.uuid4()); payload = request_for(client, session, trip, activity);
        first = call(client, "save_trip_backup_refresh", payload);
        retry = call(client, "save_trip_backup_refresh", payload);
        assert retry["replayed"] and retry["report"] == first["report"];
        payload["request_id"] = str(uuid.uuid4());
        conflict = call(client, "save_trip_backup_refresh", payload);
        assert conflict["outcome"] == "conflict" and conflict["report"] is None;
        assert call(client, "load_trip_backup_history", {"session_id": session, "trip_id": other["id"]})["revision"] == 0;
        assert call(client, "load_trip_backup_history", {"session_id": str(uuid.uuid4()), "trip_id": trip["id"]})["revision"] == 0;
        assert call(client, "load_backup_history", {"session_id": session})["revision"] == 0;
        wrong = request_for(client, session, other, other_item); wrong["item_id"] = activity["id"];
        assert not client.post("/function/save_trip_backup_refresh", json=wrong).ok;
        for value in [True, 1.0, "1", None, -1] {
            invalid = dict(payload); invalid["expected_revision"] = value;
            assert not client.post("/function/save_trip_backup_refresh", json=invalid).ok;
        }
    }
}

test "trip edits invalidate history and stale generation requests without saving a new observation" {
    with workflow_client() as client {
        (trip, activity, _) = setup_trip(client); session = str(uuid.uuid4());
        initial = request_for(client, session, trip, activity); call(client, "save_trip_backup_refresh", initial);
        stale = request_for(client, session, trip, activity);
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try { conn.execute("UPDATE trips SET budget_cents=40000 WHERE id=?", (trip["id"],)); conn.commit(); }
        finally { conn.close(); }
        before = dump_travel();
        blocked = call(client, "save_trip_backup_refresh", stale);
        assert blocked["outcome"] == "trip_changed" and blocked["report"] is None;
        assert blocked["history"]["revision"] == 1;
        assert "trip_changed" in blocked["history"]["entries"][0]["reasons"];
        fresh = call(client, "save_trip_backup_refresh", request_for(client, session, trip, activity));
        assert fresh["revision"] == 2 and fresh["report"]["base_snapshot"] != initial["expected_base_snapshot"];
        assert fresh["report"]["input_snapshot"]["trip"]["budget_minor"] == 40000;
        assert dump_travel() == before;
    }
}

test "editing the trip while the workflow runs prevents publication and storage" {
    with workflow_client() as client {
        backup_service = import_module("server.main");
        (trip, activity, _) = setup_trip(client); session = str(uuid.uuid4()); payload = request_for(client, session, trip, activity);
        def edited(*args: any, **kwargs: any) -> dict[str, any] {
            r = run_workflow(*args, **kwargs);
            conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
            try { conn.execute("UPDATE items SET title='Edited during generation' WHERE id=?", (activity["id"],)); conn.commit(); }
            finally { conn.close(); }
            return r;
        }
        with patch("server.main.run_workflow", side_effect=edited) {
            blocked = backup_service.save_trip_backup_refresh(**payload);
            assert blocked["outcome"] == "trip_changed" and blocked["report"] is None;
            assert blocked["history"]["revision"] == 0;
        }
    }
}

test "empty inventory and provider failure are saved as explicit nonpassing observations" {
    with workflow_client() as client {
        (trip, activity, _) = setup_trip(client, "Kyoto"); session = str(uuid.uuid4()); before = dump_travel();
        empty = call(client, "save_trip_backup_refresh", request_for(client, session, trip, activity));
        assert empty["report"]["results"] == [] and empty["history"]["revision"] == 1;
        assert empty["report"]["message"].startswith("No matching");
        assert dump_travel() == before;
        (trip, activity, _) = setup_trip(client); before = dump_travel();
        payload = request_for(client, session, trip, activity); payload["inventory_change"] = "provider_failure";
        failed = call(client, "save_trip_backup_refresh", payload);
        assert all(r["refresh_state"] == "provider_error" and r["source"] == "" for r in failed["report"]["results"]);
        assert dump_travel() == before;
    }
}

test "wrong triggers completed undated and removed saved targets fail without history writes" {
    with workflow_client() as client {
        (trip, activity, dinner) = setup_trip(client); session = str(uuid.uuid4());
        for changes in [{"trigger": "snow"}, {"trigger": "arrival_delay"}, {"item_id": "missing"}, {"inventory_change": "bad"}] {
            payload = request_for(client, session, trip, activity); payload.update(changes);
            before = dump_travel();
            assert not client.post("/function/save_trip_backup_refresh", json=payload).ok;
            assert dump_travel() == before;
        }
        call(client, "set_item_state", {"trip_id": trip["id"], "item_id": activity["id"], "done": True, "paid": False});
        payload = request_for(client, session, trip, activity);
        assert not client.post("/function/save_trip_backup_refresh", json=payload).ok;
        undated = call(client, "save_item", {"trip_id": trip["id"], "title": "Undated", "category": "activity"});
        assert not client.post("/function/save_trip_backup_refresh", json=request_for(client, session, trip, undated)).ok;
        call(client, "delete_item", {"trip_id": trip["id"], "item_id": dinner["id"]});
        assert not client.post("/function/save_trip_backup_refresh", json=request_for(client, session, trip, dinner)).ok;
        assert call(client, "load_trip_backup_history", {"session_id": session, "trip_id": trip["id"]})["revision"] == 0;
    }
}
