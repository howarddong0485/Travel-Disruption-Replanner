"""HTTP proof of risk -> backups -> P1 validation -> P5 review -> P4 apply."""
import os;
import json;
import uuid;
import sqlite3;
import tempfile;
import from contextlib { contextmanager }
import from datetime { datetime, timezone, timedelta }
import from unittest.mock { patch }
import from dataclasses { replace }
import from jaclang.testing.testing { JacTestClient }
import from tools.alternatives.catalog { observe }

@contextmanager
def integrated_client -> any {
    old = os.environ.get("TRAVEL_DB_PATH");
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(os.path.join(os.path.dirname(__file__), "..", "server", "main.jac"), base_path=os.path.join(directory, "runtime"));
        try { yield client; }
        finally {
            client.close();
            if old is None { os.environ.pop("TRAVEL_DB_PATH", None); } else { os.environ["TRAVEL_DB_PATH"] = old; }
        }
    }
}

def api(client: any, name: str, **data: any) -> any {
    response = client.post("/function/" + name, json=data);
    assert response.ok, str(response.data);
    return response.data["result"];
}

def active_rows -> list[tuple[any, ...]] {
    conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
    try { return conn.execute("SELECT * FROM items ORDER BY id").fetchall(); } finally { conn.close(); }
}

def generate(client: any, state: dict[str, any], **kwargs: any) -> dict[str, any] {
    kwargs.setdefault("max_plans", 4);
    kwargs.setdefault("risk_ids", [risk["id"] for risk in state["risks"]]);
    return api(client, "generate_backup_plans", trip_id=state["trip_id"], expected_version=state["trip_version"], **kwargs);
}

test "both integrated scenarios generate compare reject and accept the actual P3 candidates" {
    with integrated_client() as client {
        for scenario in ("rain", "arrival_delay") {
            state = api(client, "create_planning_demo", scenario=scenario); before = active_rows();
            result = generate(client, state);
            assert result["plans"] and active_rows() == before;
            first = result["plans"][0];
            assert first["base_version"] == state["trip_version"] and first["comparison"]["projected_total_minor"] is not None;
            api(client, "review_backup_plan", trip_id=state["trip_id"], proposal_id=first["id"], accept=False);
            assert active_rows() == before;
            chosen = result["plans"][1];
            response = api(client, "review_backup_plan", trip_id=state["trip_id"], proposal_id=chosen["id"], accept=True);
            assert response["status"] == "accepted";
            updated = api(client, "list_items", trip_id=state["trip_id"]);
            for candidate in chosen["replacements"] {
                saved = next(item for item in updated if item["id"] == candidate["replaces_id"]);
                assert saved["title"] == candidate["item"]["title"] and saved["location"] == candidate["item"]["venue"];
                assert saved["time"] == candidate["item"]["start"]["local"][11:16];
            }
            assert sum(item["cost_cents"] for item in updated) + state["ledger"]["contingency_cents"] == chosen["comparison"]["projected_total_minor"];
            assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": chosen["id"], "accept": True}).ok;
        }
    }
}

test "context edits fixed rules and stale versions block old plan acceptance without itinerary changes" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); plans = generate(client, state)["plans"];
        facts = state["facts"]; facts["profile"]["requirements"].append({"id": "cat", "category": "pet", "code": "cat", "strength": "hard"});
        changed = api(client, "save_planning_context", trip_id=state["trip_id"], payload=facts, expected_version=state["trip_version"]);
        assert changed["trip_version"] > state["trip_version"];
        before = active_rows();
        assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": plans[0]["id"], "accept": True}).ok;
        assert active_rows() == before;
        unresolved = generate(client, changed)["plans"];
        assert unresolved and all(not p["selectable"] for p in unresolved);
        assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": unresolved[0]["id"], "accept": True}).ok;
        assert active_rows() == before;
    }
}

test "request retries preserve stored evidence and cannot publish a changed trip" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); request_id = str(uuid.uuid4());
        first = generate(client, state, request_id=request_id);
        retry = generate(client, state, request_id=request_id);
        assert retry["replayed"] and retry["plans"] == first["plans"];
        assert not client.post("/function/generate_backup_plans", json={"trip_id": state["trip_id"], "expected_version": state["trip_version"], "request_id": request_id, "max_plans": 2}).ok;
        facts = state["facts"]; facts["reserve_minor"] += 100;
        api(client, "save_planning_context", trip_id=state["trip_id"], payload=facts, expected_version=state["trip_version"]);
        old = generate(client, state, request_id=request_id);
        assert all(not p["selectable"] and p["stale"] for p in old["plans"]);
    }
}

test "refresh failure price changes expiry and nonboolean acceptance preserve the saved itinerary" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); plan = generate(client, state)["plans"][0]; before = active_rows();
        for value in ("yes", 1, None) {
            assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": plan["id"], "accept": value}).ok;
        }
        with patch("planning.application.observe", side_effect=TimeoutError("Synthetic timeout")) {
            assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": plan["id"], "accept": True}).ok;
        }
        def changed_price(*args: any, **kwargs: any) -> any {
            candidate = observe(*args, **kwargs);
            return replace(candidate, item=replace(candidate.item, cost_minor=candidate.item.cost_minor + 1));
        }
        with patch("planning.application.observe", side_effect=changed_price) {
            assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": plan["id"], "accept": True}).ok;
        }
        def changed_duration(*args: any, **kwargs: any) -> any {
            candidate = observe(*args, **kwargs);
            later = datetime.fromisoformat(candidate.item.end.local) + timedelta(minutes=1);
            return replace(candidate, item=replace(candidate.item, end=replace(candidate.item.end, local=later.isoformat(timespec="minutes"))));
        }
        with patch("planning.application.observe", side_effect=changed_duration) {
            assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": plan["id"], "accept": True}).ok;
        }
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try {
            payload = json.loads(conn.execute("SELECT payload FROM replan_proposals WHERE id=?", (plan["id"],)).fetchone()[0]);
            payload["expires_at"] = (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat();
            conn.execute("UPDATE replan_proposals SET payload=? WHERE id=?", (json.dumps(payload), plan["id"])); conn.commit();
        } finally { conn.close(); }
        assert not client.post("/function/review_backup_plan", json={"trip_id": state["trip_id"], "proposal_id": plan["id"], "accept": True}).ok;
        assert active_rows() == before;
    }
}

test "rejecting and requesting another plan excludes its stable identity while retries remain historical" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); request_id = str(uuid.uuid4());
        first = generate(client, state, request_id=request_id); rejected = first["plans"][0]; before = active_rows();
        api(client, "review_backup_plan", trip_id=state["trip_id"], proposal_id=rejected["id"], accept=False);
        replayed = generate(client, state, request_id=request_id);
        assert not replayed["plans"][0]["selectable"] and replayed["plans"][0]["review_status"] == "rejected";
        fresh = generate(client, state);
        assert fresh["plans"] and all(p["candidate_id"] != rejected["candidate_id"] for p in fresh["plans"]);
        assert active_rows() == before;
    }
}

test "paid originals become one retained expense and remain counted once in subsequent plans" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        target = next(item for item in api(client, "list_items", trip_id=trip_id) if item["category"] == "activity");
        api(client, "set_item_state", trip_id=trip_id, item_id=target["id"], done=False, paid=True);
        current = api(client, "planning_state", trip_id=trip_id);
        weather = [risk["id"] for risk in current["risks"] if risk["category"] == "weather"];
        selected = generate(client, current, risk_ids=weather)["plans"][0];
        api(client, "review_backup_plan", trip_id=trip_id, proposal_id=selected["id"], accept=True);
        saved = api(client, "list_items", trip_id=trip_id);
        expenses = [item for item in saved if item["category"] == "expense"];
        assert len(expenses) == 1 and expenses[0]["paid"] and expenses[0]["cost_cents"] == target["cost_cents"];
        after = api(client, "planning_state", trip_id=trip_id);
        assert after["ledger"]["paid_cents"] == target["cost_cents"];
        assert after["ledger"]["planned_cents"] + after["ledger"]["contingency_cents"] == selected["comparison"]["projected_total_minor"];
    }
}

test "editing the itinerary while inventory is searched prevents proposal publication" {
    import from importlib { import_module }
    import from planning.engine { generate_plans }
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); service = import_module("server.main");
        def intervening_edit(*args: any, **kwargs: any) -> dict[str, any] {
            result = generate_plans(*args, **kwargs);
            conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
            try { conn.execute("UPDATE trips SET budget_cents=budget_cents-1 WHERE id=?", (state["trip_id"],)); conn.commit(); }
            finally { conn.close(); }
            return result;
        }
        rejected = False;
        with patch("server.main.generate_plans", side_effect=intervening_edit) {
            try { service.generate_backup_plans(state["trip_id"], state["trip_version"], 4, [r["id"] for r in state["risks"]]); }
            except ValueError { rejected = True; }
        }
        assert rejected;
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try {
            assert conn.execute("SELECT COUNT(*) FROM planning_runs").fetchone()[0] == 0;
            assert conn.execute("SELECT COUNT(*) FROM replan_proposals").fetchone()[0] == 0;
        } finally { conn.close(); }
    }
}
