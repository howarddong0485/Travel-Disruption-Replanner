import from copy { deepcopy }
import from datetime { datetime, timezone, timedelta }
import from planning.fixtures { sample_state }
import from planning.context { build_context, check_payload }
import from planning.profile_io { profile_from_data }
import from backup.validation { validate_replacement }
import from backup.validation_models { RiskContext, Replacement }
import from dataclasses { replace }
import from tools.alternatives.details { materialize }
import from tools.alternatives.mock { search }

glob CONTEXT_CLOCK = datetime(2026, 10, 30, 12, tzinfo=timezone.utc);

test "shared context keeps P4 version P1 profile budget and evidenced P2 risks" {
    (state, facts) = sample_state(CONTEXT_CLOCK);
    before = deepcopy((state, facts));
    data = build_context(state, check_payload(facts, state), CONTEXT_CLOCK);
    assert data["trip_version"] == state["version"] and data["bundle"].itinerary.version == state["version"];
    assert data["trip"].traveler_profile["requirements"][1]["code"] == "dog";
    assert data["ledger"]["planned_cents"] == sum(i["cost_cents"] for i in state["items"]);
    weather = [r for r in data["risks"] if r["category"] == "weather"];
    assert weather and weather[0]["status"] == "flagged";
    assert (state, facts) == before;
}

test "missing or expired evidence never produces a supported risk or fabricated traveler" {
    (state, facts) = sample_state(CONTEXT_CLOCK);
    empty = build_context(state, {}, CONTEXT_CLOCK);
    assert empty["trip"].profile.adults is None;
    assert all(i.evidence is None and i.cost_minor is None for i in empty["trip"].items);
    assert all(r["status"] == "unresolved" for r in empty["risks"]);
    old = build_context(state, facts, CONTEXT_CLOCK + timedelta(minutes=15));
    assert all(r["status"] == "unresolved" for r in old["risks"]);
}

test "profile boundary rejects bool ages and unknown fields without dropping hard requirements" {
    (state, facts) = sample_state(CONTEXT_CLOCK);
    for field in ("adults", "child_ages") {
        profile = deepcopy(facts["profile"]); profile[field] = True if field == "adults" else [True];
        rejected = False;
        try { profile_from_data(profile); } except ValueError { rejected = True; }
        assert rejected;
    }
    bad = deepcopy(facts); bad["items"]["other-trip"] = {};
    rejected = False;
    try { check_payload(bad, state); } except ValueError { rejected = True; }
    assert rejected;
}

test "P1 mandatory filter is used for arbitrary hard requirements and species-specific evidence" {
    (state, facts) = sample_state(CONTEXT_CLOCK);
    facts["profile"]["requirements"].append({"id": "no-nuts", "category": "dietary", "code": "nut_free", "strength": "hard"});
    data = build_context(state, facts, CONTEXT_CLOCK); trip = data["trip"];
    risk = RiskContext("manual", trip.id, "dinner", "arrival_delay", "flagged", trip.items[0].evidence, trip.items[0].start);
    candidate = materialize(search("Boston", "food", CONTEXT_CLOCK)[0], trip, risk, CONTEXT_CLOCK);
    result = validate_replacement(trip, risk, candidate, CONTEXT_CLOCK);
    assert any(c["status"] == "unknown" and "dietary:nut_free" in c["message"] for c in result["checks"]);
    assert result["status"] != "passed_fixture_checks";
}
