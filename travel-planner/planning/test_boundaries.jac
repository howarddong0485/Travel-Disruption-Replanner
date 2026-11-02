"""Integration boundaries that must survive combining owners' contracts."""
import json;
import from copy { deepcopy }
import from datetime { datetime, timezone, timedelta }
import from dataclasses { replace, asdict }
import from planning.fixtures { sample_state }
import from planning.context { build_context }
import from planning.engine { generate_plans }
import from planning.profile_io { profile_from_data }

glob BOUNDARY_CLOCK = datetime(2026, 10, 30, 12, tzinfo=timezone.utc);

def boundary_context -> dict[str, any] {
    (state, facts) = sample_state(BOUNDARY_CLOCK);
    return build_context(state, facts, BOUNDARY_CLOCK);
}

test "P4 latest-start constraints apply even when a provider's opening hours permit later visits" {
    context = boundary_context();
    for item in context["state"]["items"] {
        if item["id"] == "activity" { item["latest_start"] = item["date"] + "T11:00"; }
    }
    context = build_context(context["state"], context["facts"], BOUNDARY_CLOCK);
    result = generate_plans(context, BOUNDARY_CLOCK, max_plans=5);
    assert all(p["replacements"][0]["provider_id"] != "science-hall" for p in result["plans"]);
    assert any(c["code"] == "latest_start" for rejection in result["rejections"] for c in rejection["checks"]);
}

test "connected flexible arrangements move while fixed downstream boundaries remain protected" {
    (state, facts) = sample_state(BOUNDARY_CLOCK, "arrival_delay");
    for item in state["items"] {
        if item["id"] == "hotel" { item["fixed"] = False; item["protected"] = False; }
    }
    facts["manual_risks"][0]["not_before"]["local"] = state["trip"]["start_date"] + "T20:30";
    context = build_context(state, facts, BOUNDARY_CLOCK);
    generated = generate_plans(context, BOUNDARY_CLOCK, max_plans=5);
    assert generated["plans"] and all(len(p["replacements"]) == 2 for p in generated["plans"]);
    assert all(p["selectable"] for p in generated["plans"]);
    for item in state["items"] {
        if item["id"] == "hotel" { item["fixed"] = True; item["protected"] = True; }
    }
    assert generate_plans(build_context(state, facts, BOUNDARY_CLOCK), BOUNDARY_CLOCK)["plans"] == [];
}

test "refund cash and credit stay separate and neither reduces the projected total" {
    context = boundary_context(); state = context["state"]; facts = context["facts"];
    for item in state["items"] {
        if item["id"] == "activity" { item["paid"] = True; }
    }
    facts["items"]["activity"]["policy_id"] = "policy-original";
    facts["evidence"].append({"id": "policy-evidence", "source_ref": "fixture://cancel-policy", "excerpt": "Synthetic full refund",
        "retrieved_at": BOUNDARY_CLOCK.isoformat(), "origin": "mock"});
    facts["evidence_deadlines"]["policy-evidence"] = (BOUNDARY_CLOCK + timedelta(minutes=15)).isoformat();
    facts["policies"] = [{"id": "policy-original", "booking_node_id": "activity", "scope": "Original synthetic booking", "tz": "America/New_York",
        "currency": "USD", "retrieved_at": BOUNDARY_CLOCK.isoformat(), "tiers": [{"evidence_id": "policy-evidence", "refund_percent": 100, "fee_minor": 0, "refund_form": "cash"}]}];
    records = [];
    for form in ("cash", "credit") {
        facts["policies"][0]["tiers"][0]["refund_form"] = form;
        data = build_context(state, facts, BOUNDARY_CLOCK);
        weather_ids = [r["id"] for r in data["risks"] if r["category"] == "weather"];
        plan = generate_plans(data, BOUNDARY_CLOCK, weather_ids)["plans"][0];
        records.append(plan["comparison"]);
    }
    assert records[0]["eligible_cash_refund_minor"] == 4500 and records[0]["eligible_credit_minor"] == 0;
    assert records[1]["eligible_cash_refund_minor"] == 0 and records[1]["eligible_credit_minor"] == 4500;
    assert records[0]["projected_total_minor"] == records[1]["projected_total_minor"];
    assert all(record["confirmed_refund_minor"] == 0 and record["cash_needed_now_minor"] is None for record in records);
}

test "implicit traveling pets remain mandatory and shared profile inputs are not mutated" {
    context = boundary_context(); source = deepcopy(context["facts"]["profile"]);
    source["pets"].append({"species": "cat", "size": "small"});
    before = deepcopy(source); parsed = profile_from_data(source);
    assert any(r.category == "pet" and r.code == "cat" and r.strength == "hard" for r in parsed.requirements);
    assert source == before;
}

test "an unpaid confirmed booking cannot silently disappear from the budget" {
    context = boundary_context(); state = context["state"]; facts = context["facts"];
    for item in state["items"] {
        if item["id"] == "hotel" { item["fixed"] = False; item["protected"] = False; item["done"] = True; }
    }
    facts["manual_risks"] = [{"id": "hotel-closure", "category": "closure", "node_ids": ["hotel"], "summary": "Reported hotel closure", "evidence": facts["items"]["hotel"]["evidence"]}];
    data = build_context(state, facts, BOUNDARY_CLOCK);
    generated = generate_plans(data, BOUNDARY_CLOCK, ["hotel-closure"]);
    assert generated["plans"] and all(not p["selectable"] for p in generated["plans"]);
    assert any(c["code"] == "unpaid_commitment" for c in generated["plans"][0]["validation"]["checks"]);
}

test "original comparison evidence bounds expiry and rejected plan identities can be excluded" {
    context = boundary_context();
    context["facts"]["items"]["activity"]["evidence"]["expires_at"] = (BOUNDARY_CLOCK + timedelta(minutes=1)).isoformat();
    data = build_context(context["state"], context["facts"], BOUNDARY_CLOCK);
    first = generate_plans(data, BOUNDARY_CLOCK);
    assert all(datetime.fromisoformat(p["expires_at"]) == BOUNDARY_CLOCK + timedelta(minutes=1) for p in first["plans"]);
    excluded = first["plans"][0]["id"];
    other = generate_plans(data, BOUNDARY_CLOCK, excluded_ids={excluded});
    assert len(other["plans"]) == 2 and all(p["id"] != excluded for p in other["plans"]);
}

test "reported delays need an earliest time and long-drive alternatives must be shorter" {
    context = boundary_context(); state = context["state"]; facts = context["facts"];
    facts["manual_risks"] = [{"id": "reported-delay", "category": "timing", "node_ids": ["dinner"], "summary": "Reported delay", "evidence": facts["items"]["dinner"]["evidence"]}];
    data = build_context(state, facts, BOUNDARY_CLOCK);
    missing = generate_plans(data, BOUNDARY_CLOCK, ["reported-delay"]);
    assert missing["plans"] and all(not p["selectable"] for p in missing["plans"]);
    for item in state["items"] {
        if item["id"] == "arrival" { item["fixed"] = False; item["protected"] = False; }
    }
    facts["manual_risks"] = [{"id": "long-drive", "category": "long_drive", "node_ids": ["arrival"], "summary": "Long drive", "evidence": facts["items"]["arrival"]["evidence"]}];
    data = build_context(state, facts, BOUNDARY_CLOCK);
    result = generate_plans(data, BOUNDARY_CLOCK, ["long-drive"]);
    assert result["plans"] and all(p["replacements"][0]["provider_id"] != "rail" for p in result["plans"]);
}
