"""P3 consumes the same evidenced connections that activate P2 timing risks."""
import json;
import from copy { deepcopy }
import from datetime { datetime, timezone, timedelta }
import from unittest.mock { Mock, patch }
import from planning.context { build_context, check_payload }
import from planning.fixtures { sample_state }
import from planning.engine { generate_plans }
import from planning.application { apply_backup }

glob CONNECTION_CLOCK = datetime(2026, 11, 1, 12, tzinfo=timezone.utc);

def connection_fixture(minutes: int = 90) -> tuple[dict[str, any], dict[str, any]] {
    (state, facts) = sample_state(CONNECTION_CLOCK); day = state["trip"]["start_date"];
    for item in state["items"] { if item["id"] == "activity" { item["time"] = "10:10"; } }
    facts["items"]["activity"]["end"]["local"] = day + "T11:10";
    state["dependencies"] = [{"prerequisite_id":"arrival", "dependent_id":"activity", "buffer_minutes":0}];
    facts["evidence"].append({"id":"connection-proof", "source_ref":"fixture://connections/arrival-activity", "excerpt":"Door-to-door estimate", "retrieved_at":CONNECTION_CLOCK.isoformat(), "origin":"mock"});
    facts["evidence_deadlines"]["connection-proof"] = (CONNECTION_CLOCK + timedelta(minutes=5)).isoformat();
    facts["travel_estimates"] = [{"from_node_id":"arrival", "to_node_id":"activity", "minutes":minutes, "mode":"drive", "evidence_id":"connection-proof"}];
    return (state, facts);
}

def timing_plans(state: dict[str, any], facts: dict[str, any]) -> list[dict[str, any]] {
    context = build_context(state, facts, CONNECTION_CLOCK);
    ids = [risk["id"] for risk in context["risks"] if risk["rule_id"] == "tight_connection" and risk["node_ids"] == ["arrival", "activity"]];
    assert ids;
    return generate_plans(context, CONNECTION_CLOCK, ids, max_plans=5)["plans"];
}

test "same-venue reschedules resolve the evidenced connection instead of a shorter catalog route" {
    (state, facts) = connection_fixture(); day = state["trip"]["start_date"];
    plans = timing_plans(state, facts);
    moved = [p for p in plans if p["strategy"] == "reschedule" and p["selectable"]];
    assert moved;
    assert all(p["replacements"][0]["item"]["start"]["local"] >= day + "T11:30" for p in moved);
    assert all(next(t for t in p["validation"]["transfers"] if t["from_id"] == "arrival" and t["to_id"] == "activity")["minutes"] >= 90 for p in moved);
    assert all(datetime.fromisoformat(p["expires_at"]) <= CONNECTION_CLOCK + timedelta(minutes=5) for p in moved);
}

test "acceptance rejects an insufficient same-venue connection before any write" {
    (state, facts) = connection_fixture(); day = state["trip"]["start_date"];
    plan = deepcopy(next(p for p in timing_plans(state, facts) if p["strategy"] == "reschedule" and p["selectable"]));
    plan["replacements"][0]["item"]["start"]["local"] = day + "T10:40";
    plan["replacements"][0]["item"]["end"]["local"] = day + "T11:40";
    conn = Mock(); rejected = False;
    with patch("planning.application.read_facts", return_value=facts) {
        try { apply_backup(conn, state, plan, CONNECTION_CLOCK); }
        except ValueError as exc { rejected = "no longer passes" in str(exc); }
    }
    assert rejected and conn.execute.call_count == 0;
}

test "all applicable estimates and the longer supplied transfer remain binding" {
    for duration in (20, 150) {
        (state, facts) = connection_fixture(120); day = state["trip"]["start_date"];
        facts["travel_estimates"].append({**facts["travel_estimates"][0], "minutes":90, "mode":"rail"});
        for route in facts["transfers"] { if route["from_id"] == "arrival" and route["to_id"] == "activity" { route["minutes"] = duration; } }
        moved = [p for p in timing_plans(state, facts) if p["strategy"] == "reschedule" and p["selectable"]];
        assert moved;
        earliest = day + ("T12:30" if duration == 150 else "T12:00");
        assert all(p["replacements"][0]["item"]["start"]["local"] >= earliest for p in moved);
    }
}

test "nonadjacent connection evidence expires and cannot become a synthetic route" {
    for mode in ("fresh", "expired", "missing_deadline", "future") {
        (state, facts) = connection_fixture();
        state["dependencies"] = [];
        facts["travel_estimates"][0]["to_node_id"] = "dinner";
        if mode == "expired" { facts["evidence_deadlines"]["connection-proof"] = CONNECTION_CLOCK.isoformat(); }
        if mode == "missing_deadline" { facts["evidence_deadlines"].pop("connection-proof"); }
        if mode == "future" { facts["evidence"][-1]["retrieved_at"] = (CONNECTION_CLOCK + timedelta(minutes=1)).isoformat(); }
        context = build_context(state, facts, CONNECTION_CLOCK);
        weather = [r["id"] for r in context["risks"] if r["category"] == "weather"];
        plans = generate_plans(context, CONNECTION_CLOCK, weather)["plans"];
        assert plans;
        if mode == "fresh" {
            assert all(p["selectable"] and datetime.fromisoformat(p["expires_at"]) <= CONNECTION_CLOCK + timedelta(minutes=5) for p in plans);
        } else {
            assert all(not p["selectable"] and any(c["code"] == "transfer_evidence" and c["status"] == "unknown" for c in p["validation"]["checks"]) for p in plans);
        }
    }
}

test "a nonadjacent unchanged connection cannot be dropped from whole-trip validation" {
    (state, facts) = connection_fixture(700); state["dependencies"] = [];
    facts["travel_estimates"][0]["to_node_id"] = "hotel";
    context = build_context(state, facts, CONNECTION_CLOCK);
    weather = [r["id"] for r in context["risks"] if r["category"] == "weather"];
    result = generate_plans(context, CONNECTION_CLOCK, weather);
    assert not result["plans"];
    assert any(c["code"] == "transfer" and c["item_ids"] == ["arrival", "hotel"] for row in result["rejections"] for c in row["checks"]);
}

test "replacement routes use the new venue and do not rebind the old estimate after acceptance" {
    (state, facts) = connection_fixture();
    plans = timing_plans(state, facts);
    for strategy in ("replace_item", "reschedule") {
        chosen = next(p for p in plans if p["strategy"] == strategy and p["selectable"]);
        conn = Mock();
        with patch("planning.application.read_facts", return_value=facts) { apply_backup(conn, state, chosen, CONNECTION_CLOCK); }
        saved = json.loads(conn.execute.call_args_list[-1].args[1][0]);
        if strategy == "replace_item" {
            assert saved["travel_estimates"] == [];
            assert next(t for t in saved["transfers"] if t["from_id"] == "arrival" and t["to_id"] == "activity")["minutes"] == 20;
        } else { assert saved["travel_estimates"] == facts["travel_estimates"]; }
    }
}

test "supplemental duration inputs require nonnegative integer minutes" {
    for minutes in (True, -1, 1.5, "90", None) {
        (state, facts) = connection_fixture(); facts["travel_estimates"][0]["minutes"] = minutes; rejected = False;
        try { check_payload(facts, state); } except ValueError { rejected = True; }
        assert rejected;
    }
}
