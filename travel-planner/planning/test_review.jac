"""Pre-merge review regressions with a fixed evidence clock."""
import json;
import from copy { deepcopy }
import from datetime { datetime, timezone, timedelta }
import from unittest.mock { Mock, patch }
import from planning.fixtures { sample_state }
import from planning.context { build_context }
import from planning.engine { generate_plans }
import from planning.application { apply_backup }

glob REVIEW_CLOCK = datetime(2026, 11, 1, 12, tzinfo=timezone.utc);

test "all selected risks on one item are enforced in either selection order" {
    (state, facts) = sample_state(REVIEW_CLOCK); day = state["trip"]["start_date"];
    facts["manual_risks"].append({"id": "delay", "category": "timing", "node_ids": ["activity"], "summary": "Noon earliest start",
        "evidence": facts["items"]["activity"]["evidence"], "not_before": {"local": day + "T12:00", "zone": "America/New_York"}});
    context = build_context(state, facts, REVIEW_CLOCK);
    weather = next(r["id"] for r in context["risks"] if r["category"] == "weather");
    for ids in ([weather, "delay"], ["delay", weather]) {
        plans = generate_plans(context, REVIEW_CLOCK, ids, max_plans=5)["plans"];
        assert plans and all(p["selectable"] for p in plans);
        assert all(set(p["risk_ids"]) == set(ids) for p in plans);
        assert all(c["item"]["start"]["local"] >= day + "T12:00" and c["item"]["eligibility"]["indoor"] for p in plans for c in p["replacements"]);
    }
}

test "removed or excluded scheduled nodes do not leave supplemental references" {
    for excluded in ("deleted", "packing") {
        (state, facts) = sample_state(REVIEW_CLOCK); original = deepcopy(facts);
        if excluded == "deleted" { state["items"] = [i for i in state["items"] if i["id"] != "activity"]; }
        else { next(i for i in state["items"] if i["id"] == "activity")["category"] = "packing"; }
        state["dependencies"] = [e for e in state["dependencies"] if "activity" not in (e["prerequisite_id"], e["dependent_id"])];
        context = build_context(state, facts, REVIEW_CLOCK);
        assert "activity" not in context["facts"]["items"];
        assert all(h["node_id"] != "activity" for h in context["facts"]["place_hours"]);
        generate_plans(context, REVIEW_CLOCK); assert facts == original;
    }
}

test "reschedules preserve saved policy kind tags and quote evidence" {
    (state, facts) = sample_state(REVIEW_CLOCK, "arrival_delay");
    facts["items"]["dinner"].update({"policy_id": "dinner-policy", "kind": "food", "tags": ["indoor", "saved-booking"]});
    facts["policies"] = [{"id": "dinner-policy", "booking_node_id": "dinner", "scope": "Saved dinner", "tz": "America/New_York", "currency": "USD", "retrieved_at": REVIEW_CLOCK.isoformat()}];
    context = build_context(state, facts, REVIEW_CLOCK);
    plan = next(p for p in generate_plans(context, REVIEW_CLOCK, ["reported-arrival-delay"], max_plans=5)["plans"] if p["strategy"] == "reschedule" and p["selectable"]);
    conn = Mock();
    with patch("planning.application.read_facts", return_value=facts) { apply_backup(conn, state, plan, REVIEW_CLOCK); }
    saved = json.loads(conn.execute.call_args_list[-1].args[1][0]);
    for key in ("policy_id", "kind", "tags", "evidence", "eligibility", "hours") {
        assert saved["items"]["dinner"][key] == facts["items"]["dinner"][key], key;
    }
}

test "derived long-drive activation remains timing during acceptance" {
    (state, facts) = sample_state(REVIEW_CLOCK);
    for item in state["items"] { if item["id"] == "arrival" { item["fixed"] = False; item["protected"] = False; } }
    state["dependencies"] = [{"prerequisite_id": "arrival", "dependent_id": "activity", "buffer_minutes": 20}];
    context = build_context(state, facts, REVIEW_CLOCK);
    context["risks"] = [{"id": "drive", "category": "long_drive", "node_ids": ["arrival"], "status": "flagged", "summary": "Long transfer", "evidence": facts["items"]["arrival"]["evidence"]}];
    plans = [p for p in generate_plans(context, REVIEW_CLOCK, ["drive"], max_plans=5)["plans"] if p["selectable"] and len(p["replacements"]) == 2];
    assert plans; conn = Mock();
    with patch("planning.application.build_context", return_value=context), patch("planning.application.read_facts", return_value=facts) {
        apply_backup(conn, state, plans[0], REVIEW_CLOCK);
    }
    assert conn.execute.call_count > 0;
}

test "refund-tier and policy-proof deadlines bound review expiry and acceptance" {
    for proof_minutes in (1, 10) {
        (state, facts) = sample_state(REVIEW_CLOCK);
        for item in state["items"] { if item["id"] == "activity" { item["paid"] = True; } }
        facts["items"]["activity"]["policy_id"] = "paid-policy";
        facts["evidence"].append({"id": "policy-proof", "source_ref": "fixture://policy", "excerpt": "Full refund before deadline", "retrieved_at": REVIEW_CLOCK.isoformat(), "origin": "mock"});
        proof_end = REVIEW_CLOCK + timedelta(minutes=proof_minutes); tier_end = REVIEW_CLOCK + timedelta(minutes=2);
        facts["evidence_deadlines"]["policy-proof"] = proof_end.isoformat();
        facts["policies"] = [{"id": "paid-policy", "booking_node_id": "activity", "scope": "Paid activity", "tz": "UTC", "currency": "USD", "retrieved_at": REVIEW_CLOCK.isoformat(), "tiers": [
            {"deadline_local": tier_end.replace(tzinfo=None).isoformat(timespec="minutes"), "refund_percent": 100, "fee_minor": 0, "refund_form": "cash", "evidence_id": "policy-proof"},
            {"refund_percent": 0, "fee_minor": 0, "refund_form": "none", "evidence_id": "policy-proof"}]}];
        context = build_context(state, facts, REVIEW_CLOCK);
        ids = [r["id"] for r in context["risks"] if r["category"] == "weather"];
        plans = generate_plans(context, REVIEW_CLOCK, ids)["plans"];
        assert plans and all(p["comparison"]["refund_loss_minor"] == 0 for p in plans);
        for plan in plans {
            assert datetime.fromisoformat(plan["expires_at"]) == min(proof_end, tier_end);
            assert plan["validation"]["expires_at"] == plan["expires_at"];
        }
        conn = Mock(); caught = False;
        try { apply_backup(conn, state, plans[0], min(proof_end, tier_end)); } except ValueError { caught = True; }
        assert caught and conn.execute.call_count == 0;
    }
}

test "new foreign supplemental facts are rejected instead of silently reconciled" {
    import from planning.context { check_payload }
    (state, facts) = sample_state(REVIEW_CLOCK);
    for extra in ({"place_hours": [{"node_id": "foreign"}]}, {"policies": [{"booking_node_id": "foreign"}]},
        {"travel_estimates": [{"from_node_id": "arrival", "to_node_id": "foreign"}]},
        {"manual_risks": [{"node_ids": ["foreign"]}]}) {
        rejected = False;
        try { check_payload({**facts, **extra}, state); } except ValueError { rejected = True; }
        assert rejected;
    }
}
