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

test "a saved-trip report makes versioned options without changing itinerary items" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        activity = next(i for i in state["items"] if i["category"] == "activity");
        before = active_rows();
        recorded = api(client, "report_itinerary_change", trip_id=trip_id, item_id=activity["id"],
            reason="weather", expected_version=state["trip_version"]);
        result = generate(client, {"trip_id": trip_id, "trip_version": recorded["trip_version"], "risks": []},
            risk_ids=[recorded["risk_id"]]);
        assert len(result["plans"]) >= 2 and active_rows() == before;
        options = [p for p in result["plans"] if p["selectable"]];
        assert len(options) >= 2;
        accepted = api(client, "review_backup_plan", trip_id=trip_id, proposal_id=options[1]["id"], accept=True);
        assert accepted["status"] == "accepted";
        for change in options[1]["replacements"] {
            saved = next(i for i in api(client, "list_items", trip_id=trip_id) if i["id"] == change["replaces_id"]);
            assert saved["title"] == change["item"]["title"] and saved["time"] == change["item"]["start"]["local"][11:16];
        }
        assert not client.post("/function/report_itinerary_change", json={"trip_id": trip_id, "item_id": activity["id"],
            "reason": "weather", "expected_version": state["trip_version"]}).ok;
    }
}

test "place photos and pins are address-bound and concurrent edits cannot overwrite them" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        item = next(i for i in state["items"] if i["category"] == "activity");
        before = active_rows();
        original = api(client, "get_place_details", trip_id=trip_id, item_id=item["id"]);
        assert original["revision"] == 0 and original["photo_url"] == "";
        payload = {"latitude": 42.36, "longitude": -71.05, "photo_url": "https://example.org/my-photo.jpg",
            "photo_source": "Traveler photo"};
        saved = api(client, "save_place_details", trip_id=trip_id, item_id=item["id"], location=item["location"],
            expected_revision=0, payload=payload);
        assert saved["revision"] == 1 and saved["latitude"] == 42.36 and active_rows() == before;
        assert api(client, "planning_state", trip_id=trip_id)["trip_version"] == state["trip_version"];
        assert not client.post("/function/save_place_details", json={"trip_id": trip_id, "item_id": item["id"],
            "location": item["location"], "expected_revision": 0, "payload": payload}).ok;
        for invalid in ({**payload, "latitude": 91}, {**payload, "longitude": None},
            {**payload, "photo_url": "javascript:alert(1)"}, {**payload, "photo_source": ""}) {
            assert not client.post("/function/save_place_details", json={"trip_id": trip_id, "item_id": item["id"],
                "location": item["location"], "expected_revision": 1, "payload": invalid}).ok;
        }
        other = api(client, "create_planning_demo");
        assert not client.post("/function/get_place_details", json={"trip_id": other["trip_id"], "item_id": item["id"]}).ok;
        api(client, "save_item", trip_id=trip_id, item_id=item["id"], title=item["title"], date=item["date"],
            time=item["time"], location="A different address", cost=str(item["cost_cents"] / 100));
        moved = api(client, "get_place_details", trip_id=trip_id, item_id=item["id"]);
        assert moved["photo_url"] == "" and moved["latitude"] is None and moved["revision"] == 1;
        assert not client.post("/function/save_place_details", json={"trip_id": trip_id, "item_id": item["id"],
            "location": item["location"], "expected_revision": 1, "payload": payload}).ok;
        api(client, "delete_item", trip_id=trip_id, item_id=item["id"]);
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try { assert conn.execute("SELECT count(*) FROM itinerary_place_details WHERE item_id=?", (item["id"],)).fetchone()[0] == 0; }
        finally { conn.close(); }
    }
}

test "a reported transport delay moves the existing arrangement and never offers a substitute vehicle" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        transport = next(i for i in state["items"] if i["category"] == "transport");
        api(client, "replan_save_rules", trip_id=trip_id, item_id=transport["id"], duration_minutes=60, latest_start="", fixed=False);
        current = api(client, "planning_state", trip_id=trip_id); before = active_rows();
        recorded = api(client, "report_itinerary_change", trip_id=trip_id, item_id=transport["id"],
            reason="timing", delay_minutes=20, expected_version=current["trip_version"]);
        assert recorded["not_before"]["local"].endswith("T09:20");
        result = generate(client, {"trip_id": trip_id, "trip_version": recorded["trip_version"], "risks": []},
            risk_ids=[recorded["risk_id"]]);
        considered = result["plans"] + [rejection["recorded_plan"] for rejection in result["rejections"]];
        assert considered and active_rows() == before;
        for plan in considered {
            change = next(c for c in plan["replacements"] if c["replaces_id"] == transport["id"]);
            assert change["action"] == "reschedule" and change["item"]["title"] == transport["title"];
        }
    }
}

test "supplemental connection evidence survives the HTTP generate reject and exact-accept lifecycle" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        arrival = next(i["id"] for i in state["items"] if i["category"] == "transport");
        activity = next(i["id"] for i in state["items"] if i["category"] == "activity");
        api(client, "replan_save_dependency", trip_id=trip_id, prerequisite_id=arrival, dependent_id=activity, buffer_minutes=0, remove=False);
        state = api(client, "planning_state", trip_id=trip_id); facts = state["facts"];
        clock = datetime.fromisoformat(state["checked_at"]);
        facts["evidence"].append({"id":"long-transfer", "source_ref":"fixture://connections/long-transfer", "excerpt":"150-minute connection", "retrieved_at":clock.isoformat(), "origin":"mock"});
        facts["evidence_deadlines"]["long-transfer"] = (clock + timedelta(minutes=5)).isoformat();
        facts["travel_estimates"] = [{"from_node_id":arrival, "to_node_id":activity, "minutes":150, "mode":"drive", "evidence_id":"long-transfer"}];
        current = api(client, "save_planning_context", trip_id=trip_id, payload=facts, expected_version=state["trip_version"]);
        risks = [r["id"] for r in current["risks"] if r["rule_id"] == "tight_connection" and r["node_ids"] == [arrival, activity]];
        assert risks;
        before = active_rows(); response = generate(client, current, risk_ids=risks, max_plans=5);
        chosen = next(p for p in response["plans"] if p["strategy"] == "reschedule" and p["selectable"]);
        change = next(c for c in chosen["replacements"] if c["replaces_id"] == activity);
        assert change["item"]["start"]["local"].endswith("T12:30");
        assert active_rows() == before;
        other = next(p for p in response["plans"] if p["id"] != chosen["id"]);
        api(client, "review_backup_plan", trip_id=trip_id, proposal_id=other["id"], accept=False);
        assert active_rows() == before;
        accepted = api(client, "review_backup_plan", trip_id=trip_id, proposal_id=chosen["id"], accept=True);
        assert accepted["status"] == "accepted";
        after = api(client, "planning_state", trip_id=trip_id);
        assert after["trip_version"] > current["trip_version"] and after["facts"]["travel_estimates"] == facts["travel_estimates"];
        assert next(i for i in after["items"] if i["id"] == activity)["time"] == "12:30";
        assert not any(r["rule_id"] == "tight_connection" and r["node_ids"] == [arrival, activity] and r["status"] == "flagged" for r in after["risks"]);
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

test "ordinary edits invalidate only affected evidence across API and direct transactional writes" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        target = next(i for i in api(client, "list_items", trip_id=trip_id) if i["category"] == "food");
        kwargs = {key:target[key] for key in ("title", "category", "date", "time", "location", "reference", "notes")};
        kwargs.update({"trip_id":trip_id, "item_id":target["id"], "cost":str(target["cost_cents"] / 100)});
        api(client, "save_item", **{**kwargs, "notes":"A harmless note"});
        unchanged = api(client, "planning_state", trip_id=trip_id);
        assert unchanged["facts"]["items"][target["id"]]["evidence"] is not None;
        api(client, "save_item", **{**kwargs, "location":"fixture:changed-dinner", "cost":"80.00"});
        changed = api(client, "planning_state", trip_id=trip_id);
        assert changed["facts"]["items"][target["id"]]["evidence"] is None;
        assert all(h["node_id"] != target["id"] for h in changed["facts"]["place_hours"]);
        assert all(f["evidence"] is not None for (key,f) in changed["facts"]["items"].items() if key != target["id"]);
        weather = [r["id"] for r in changed["risks"] if r["category"] == "weather"];
        plans = generate(client, changed, risk_ids=weather)["plans"];
        assert plans and all(not p["selectable"] for p in plans);
        facts = changed["facts"]; facts["items"][target["id"]]["evidence"] = state["facts"]["items"][target["id"]]["evidence"];
        confirmed = api(client, "save_planning_context", trip_id=trip_id, payload=facts, expected_version=changed["trip_version"]);
        assert confirmed["facts"]["items"][target["id"]]["evidence"] is not None;
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try {
            conn.execute("UPDATE items SET time='18:10' WHERE id=?", (target["id"],)); conn.rollback();
        } finally { conn.close(); }
        assert api(client,"planning_state",trip_id=trip_id)["facts"]["items"][target["id"]]["evidence"] is not None;
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try { conn.execute("UPDATE items SET time='18:15' WHERE id=?", (target["id"],)); conn.commit(); }
        finally { conn.close(); }
        assert api(client,"planning_state",trip_id=trip_id)["facts"]["items"][target["id"]]["evidence"] is None;
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try { conn.execute("DROP TABLE planning_fact_invalidations"); conn.commit(); }
        finally { conn.close(); }
        migrated = api(client,"planning_state",trip_id=trip_id);
        assert all(detail["evidence"] is None for detail in migrated["facts"]["items"].values());
    }
}

test "editing confirmed facts removes their unsupported hours and saves an unresolved context" {
    import from copy { deepcopy }
    with integrated_client() as client {
        state = api(client, "create_planning_demo");
        dinner = next(item["id"] for item in state["items"] if item["category"] == "food");
        facts = deepcopy(state["facts"]); proof = deepcopy(facts["items"][dinner]["evidence"]);
        for hours in facts["place_hours"] {
            if hours["node_id"] == dinner { hours["evidence_id"] = "item-facts:" + dinner; }
        }
        confirmed = api(client, "save_planning_context", trip_id=state["trip_id"], payload=facts, expected_version=state["trip_version"]);
        edited = deepcopy(confirmed["facts"]); edited["items"][dinner]["evidence"] = None;
        edited["items"][dinner]["eligibility"]["vegetarian"] = True;
        saved = api(client, "save_planning_context", trip_id=state["trip_id"], payload=edited, expected_version=confirmed["trip_version"]);
        assert saved["facts"]["items"][dinner]["evidence"] is None;
        assert not any(h["evidence_id"] == "item-facts:" + dinner for h in saved["facts"]["place_hours"]);
        weather = [r["id"] for r in saved["risks"] if r["category"] == "weather"];
        plans = generate(client, saved, risk_ids=weather)["plans"];
        assert plans and all(not p["selectable"] for p in plans);
        restored = deepcopy(confirmed["facts"]); restored["items"][dinner]["evidence"] = proof;
        current = api(client, "save_planning_context", trip_id=state["trip_id"], payload=restored, expected_version=saved["trip_version"]);
        assert all(p["selectable"] for p in generate(client, current, risk_ids=weather)["plans"]);
        invalid = deepcopy(current["facts"]); invalid["place_hours"][0]["evidence_id"] = "unknown-proof";
        assert not client.post("/function/save_planning_context", json={"trip_id":state["trip_id"], "payload":invalid, "expected_version":current["trip_version"]}).ok;
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

test "upgrading validation rules cannot replay older proposals as selectable" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); request_id = str(uuid.uuid4());
        first = generate(client, state, request_id=request_id); before = active_rows();
        conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
        try {
            old = first.copy();
            for plan in old["plans"] {
                plan["validator_version"] = "roam.planning-validator.old";
                conn.execute("UPDATE replan_proposals SET payload=? WHERE id=?", (json.dumps(plan), plan["id"]));
            }
            conn.execute("UPDATE planning_runs SET payload=? WHERE id=?", (json.dumps(old), request_id)); conn.commit();
        } finally { conn.close(); }
        replayed = generate(client, state, request_id=request_id);
        assert replayed["replayed"] and all(not p["selectable"] and p["stale"] for p in replayed["plans"]);
        current = api(client, "planning_state", trip_id=state["trip_id"]);
        assert current["trip_version"] == state["trip_version"];
        assert all(current["review_statuses"][p["id"]] == "incompatible" for p in first["plans"]);
        assert not client.post("/function/review_backup_plan", json={"trip_id":state["trip_id"], "proposal_id":first["plans"][0]["id"], "accept":True}).ok;
        assert active_rows() == before;
    }
}

test "a concurrently completed duplicate cannot restore a rejected proposal" {
    import from importlib { import_module }
    import from planning.engine { generate_plans }
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); request_id = str(uuid.uuid4()); before = active_rows();
        service = import_module("server.main"); completed = [];
        def finish_duplicate(*args: any, **kwargs: any) -> dict[str, any] {
            result = generate_plans(*args, **kwargs);
            with patch("server.main.generate_plans", generate_plans) {
                first = service.generate_backup_plans(state["trip_id"], state["trip_version"], 4, [r["id"] for r in state["risks"]], False, request_id, []);
            }
            completed.append(first["plans"][0]["id"]);
            service.review_backup_plan(state["trip_id"], completed[0], False);
            return result;
        }
        with patch("server.main.generate_plans", side_effect=finish_duplicate) {
            replayed = service.generate_backup_plans(state["trip_id"], state["trip_version"], 4, [r["id"] for r in state["risks"]], False, request_id, []);
        }
        assert completed;
        assert replayed["replayed"] and replayed["plans"][0]["id"] == completed[0];
        assert not replayed["plans"][0]["selectable"] and replayed["plans"][0]["review_status"] == "rejected";
        assert active_rows() == before;
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

test "requesting other plans advances stable candidates without rejecting or changing the trip" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo", scenario="arrival_delay"); before = active_rows();
        first = generate(client, state, max_plans=3); ids = [p["candidate_id"] for p in first["plans"]];
        assert len(ids) == 3;
        request_id = str(uuid.uuid4());
        other = generate(client, state, max_plans=3, exclude_candidate_ids=ids, request_id=request_id);
        assert other["plans"] and all(p["candidate_id"] not in ids for p in other["plans"]);
        retry = generate(client, state, max_plans=3, exclude_candidate_ids=ids, request_id=request_id);
        assert retry["replayed"] and retry["plans"] == other["plans"];
        assert not client.post("/function/generate_backup_plans", json={"trip_id":state["trip_id"], "expected_version":state["trip_version"], "risk_ids":[r["id"] for r in state["risks"]], "max_plans":3, "exclude_candidate_ids":[], "request_id":request_id}).ok;
        seen = ids + [p["candidate_id"] for p in other["plans"]];
        final = generate(client, state, max_plans=3, exclude_candidate_ids=seen);
        assert not final["plans"] and active_rows() == before;
        current = api(client, "planning_state", trip_id=state["trip_id"]);
        assert all(current["review_statuses"][p["id"]] == "proposed" for p in first["plans"] + other["plans"]);
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

test "deleting a connected demo item leaves planning load generation and facts repair usable" {
    with integrated_client() as client {
        state = api(client, "create_planning_demo"); trip_id = state["trip_id"];
        removed = next(i for i in state["items"] if i["category"] == "activity");
        api(client, "delete_item", trip_id=trip_id, item_id=removed["id"]);
        fresh = api(client, "planning_state", trip_id=trip_id);
        assert removed["id"] not in fresh["facts"]["items"];
        assert all(record["node_id"] != removed["id"] for record in fresh["facts"]["place_hours"]);
        generate(client, fresh);
        api(client, "save_planning_context", trip_id=trip_id, payload=fresh["facts"], expected_version=fresh["trip_version"]);
    }
}
