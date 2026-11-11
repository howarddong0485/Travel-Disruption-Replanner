import json;
import from copy { deepcopy }
import from datetime { datetime, timezone, timedelta }
import from unittest.mock { patch }
import from planning.fixtures { sample_state }
import from planning.context { build_context }
import from planning.engine { generate_plans, SUPPORTED_REASONS }
import from planning.serialization { replacement_from_data, risk_from_data }
import from planning.validation { validate_plan }

glob PLAN_CLOCK = datetime(2026, 10, 30, 12, tzinfo=timezone.utc);

def plan_sample(scenario: str = "rain") -> dict[str, any] {
    (state, facts) = sample_state(PLAN_CLOCK, scenario);
    return build_context(state, facts, PLAN_CLOCK);
}

test "weather search returns three different passing plans with P1 checks and P4 version" {
    data = plan_sample(); before = deepcopy(data["facts"]);
    generated = generate_plans(data, PLAN_CLOCK, max_plans=5);
    assert len(generated["plans"]) == 3, str(generated);
    assert len({p["replacements"][0]["provider_id"] for p in generated["plans"]}) == 3;
    assert all(p["selectable"] and p["base_version"] == data["trip_version"] for p in generated["plans"]);
    assert any("pet:dog" in c["message"] for c in generated["plans"][0]["validation"]["checks"]);
    assert generated["rejections"] and data["facts"] == before;
}

test "multiple risks produce complete connected-node plans with distinct inventory" {
    data = plan_sample(); facts = deepcopy(data["facts"]);
    facts["manual_risks"].append({"id": "dinner-closure", "category": "closure", "node_ids": ["dinner"],
        "summary": "Restaurant reported closed", "evidence": facts["items"]["dinner"]["evidence"]});
    context = build_context(data["state"], facts, PLAN_CLOCK);
    generated = generate_plans(context, PLAN_CLOCK, max_plans=5);
    assert len(generated["plans"]) == 5;
    assert all(len(p["replacements"]) == 2 and p["strategy"] == "replace_connected_items" for p in generated["plans"]);
    for plan in generated["plans"] {
        restored = json.loads(json.dumps(plan));
        check = validate_plan(context["trip"], tuple(risk_from_data(r) for r in restored["risks"]),
            tuple(replacement_from_data(c) for c in restored["replacements"]), PLAN_CLOCK);
        assert check["status"] == "valid" and check["projected_total_minor"] == plan["comparison"]["projected_total_minor"];
    }
}

test "timing and opening-hours risks can reschedule without charging the original item twice" {
    data = plan_sample("arrival_delay");
    generated = generate_plans(data, PLAN_CLOCK, max_plans=5);
    assert generated["plans"];
    shifted = [p for p in generated["plans"] if p["strategy"] == "reschedule"];
    assert shifted;
    for plan in shifted {
        assert plan["comparison"]["new_purchase_quotes_minor"] == 0;
        assert plan["comparison"]["retained_paid_minor"] == 0;
    }
    assert "long_drive" in SUPPORTED_REASONS and "booking_terms" in SUPPORTED_REASONS and "closure" in SUPPORTED_REASONS;
}

test "missing evidence fixed nodes unknown requirements and providers cannot become selectable" {
    data = plan_sample();
    for change in ("provider_failure", "all_sold_out") {
        data["facts"]["inventory_change"] = change;
        assert generate_plans(data, PLAN_CLOCK)["plans"] == [];
    }
    data = plan_sample(); data["facts"]["profile"]["requirements"].append({"id": "cat", "category": "pet", "code": "cat", "strength": "hard"});
    data = build_context(data["state"], data["facts"], PLAN_CLOCK);
    unresolved = generate_plans(data, PLAN_CLOCK);
    assert unresolved["plans"] and all(not p["selectable"] for p in unresolved["plans"]);
    data["state"]["items"][1]["fixed"] = True;
    fixed = build_context(data["state"], data["facts"], PLAN_CLOCK);
    assert generate_plans(fixed, PLAN_CLOCK)["plans"] == [];
}

test "expiry and budget boundaries survive expanded search and no refunds are counted as cash" {
    data = plan_sample();
    expired = generate_plans(data, PLAN_CLOCK + timedelta(minutes=15));
    assert all(not p["selectable"] for p in expired["plans"]);
    data["state"]["trip"]["budget_cents"] = 10000;
    limited = build_context(data["state"], data["facts"], PLAN_CLOCK);
    assert generate_plans(limited, PLAN_CLOCK)["plans"] == [];
    normal = generate_plans(plan_sample(), PLAN_CLOCK)["plans"][0];
    assert normal["comparison"]["confirmed_refund_minor"] == 0 and normal["comparison"]["cash_needed_now_minor"] is None;
}

test "invalid model IDs fall back to the validated deterministic plan set" {
    class Choice {
        has plan_ids: list[str] = ["invented"];
        has explanation: str = "Unsupported";
    }
    with patch("planning.engine.select_backup_plans", return_value=Choice()) {
        generated = generate_plans(plan_sample(), PLAN_CLOCK, use_llm=True);
        assert generated["mode"] == "deterministic" and generated["plans"];
        assert all(p["selectable"] for p in generated["plans"]);
    }
}
