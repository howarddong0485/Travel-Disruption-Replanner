"""Selection after full validation, including backfill and honest empty outcomes."""
import json;
import from copy { deepcopy }
import from dataclasses { replace }
import from datetime { datetime, timedelta, timezone }
import from unittest.mock { patch }
import from backup.validation_fixtures { build_fixture }
import from backup.workflow { run_workflow }
import from backup.selection { select_options }

glob SELECT_CLOCK = datetime(2026, 11, 10, 12, tzinfo=timezone.utc);

def selection_sample(change: str = "unchanged", scenario: str = "rain", budget: int = 60000) -> dict[str, any] {
    (trip, risk, _) = build_fixture(scenario, "family", SELECT_CLOCK);
    return run_workflow(replace(trip, budget_minor=budget), risk, "Boston", change, SELECT_CLOCK, scenario);
}

test "price increase and sold out inventory are replaced only by validated candidates" {
    for change in ["price_increase", "sold_out", "partial_failure", "expired_evidence"] {
        r = selection_sample(change);
        assert [o["provider_id"] for o in r["results"]] == ["science-hall", "covered-market"];
        assert [o["display_label"] for o in r["results"]] == ["Plan B", "Plan C"];
        assert r["summary"]["passed_fixture_checks"] == 2;
        assert r["pipeline"]["evaluated_count"] == 4 and r["pipeline"]["selected_count"] == 2;
        assert r["pipeline"]["searched_count"] == 6;
        original = r["evaluated_options"][0];
        assert original["provider_id"] == "indoor-gallery" and original["status"] != "passed_fixture_checks";
        assert any(d["provider_id"] == "quiet-library" and d["reason"] == "requirements_failed" for d in r["selection"]["decisions"]);
        assert r["results"][1]["changes"]["cost"]["proposed_total_minor"] == 42500;
        assert r["results"][1]["changes"]["cost"]["delta_minor"] == 1500;
    }
}

test "whole party eligibility wins over a cheaper search estimate" {
    r = selection_sample(budget=45000);
    assert [o["provider_id"] for o in r["results"]] == ["indoor-gallery", "covered-market"];
    cheap = next(o for o in r["evaluated_options"] if o["provider_id"] == "quiet-library");
    assert cheap["cost"]["projected_total_minor"] < 45000 and cheap["status"] == "invalid";
    assert any(c["code"] == "eligibility" and c["status"] == "fail" for c in cheap["checks"]);
}

test "one eligible dinner is shown without manufacturing a second option" {
    r = selection_sample(scenario="arrival_delay", budget=39000);
    assert len(r["results"]) == 1 and r["results"][0]["provider_id"] == "late-noodle-house";
    assert r["results"][0]["display_label"] == "Plan B";
    assert r["results"][0]["cost"]["projected_total_minor"] == 38900;
    assert "Only one" in r["selection"]["message"];
}

test "all sold out failed providers protected targets and budget failure have honest empty states" {
    for (change, scenario, budget, outcome, message) in [
        ("all_sold_out", "rain", 60000, "no_feasible_options", "sold out"),
        ("provider_failure", "rain", 60000, "provider_unavailable", "try again"),
        ("unchanged", "fixed_item", 60000, "no_feasible_options", "fixed or completed"),
        ("unchanged", "rain", 30000, "no_feasible_options", "budget")
    ] {
        r = selection_sample(change, scenario, budget);
        assert r["results"] == [] and len(r["evaluated_options"]) == 4;
        assert r["selection"]["outcome"] == outcome and message in r["selection"]["message"];
        assert r["summary"] == {"passed_fixture_checks": 0, "invalid": 0, "needs_validation": 0};
    }
}

test "successful response with missing original facts never becomes an eligible option" {
    (trip, risk, _) = build_fixture("rain", "family", SELECT_CLOCK);
    trip = replace(trip, profile=replace(trip.profile, complete=False));
    r = run_workflow(trip, risk, "Boston", "unchanged", SELECT_CLOCK);
    assert r["selection"]["outcome"] == "needs_confirmation";
    assert r["summary"]["passed_fixture_checks"] == 0 and r["summary"]["needs_validation"] == 2;
    assert all(o["valid_until"] is None for o in r["results"]);
}

test "selection is deterministic independent of price and does not mutate reports" {
    r = selection_sample();
    raw = dict(r); raw["results"] = r["evaluated_options"]; raw["summary"] = r["evaluated_summary"];
    before = deepcopy(raw);
    a = select_options(raw); b = select_options(raw);
    assert a == b and raw == before;
    assert [o["provider_id"] for o in a["results"]] == ["indoor-gallery", "science-hall"];
    assert a["results"][1]["cost"]["projected_total_minor"] > r["evaluated_options"][3]["cost"]["projected_total_minor"];
    encoded = json.loads(json.dumps(a));
    assert encoded["selection"] == a["selection"];
    assert [o["provider_id"] for o in encoded["results"]] == [o["provider_id"] for o in a["results"]];
}

test "passed alternatives precede provisional ones without promoting missing evidence" {
    r = selection_sample();
    raw = dict(r); raw["results"] = [deepcopy(r["evaluated_options"][0]), deepcopy(r["evaluated_options"][1])];
    raw["results"][0]["status"] = "needs_validation"; raw["results"][0]["valid_until"] = None;
    chosen = select_options(raw)["results"];
    assert chosen[0]["provider_id"] == "science-hall";
    assert chosen[1]["provider_id"] == "indoor-gallery" and chosen[1]["status"] == "needs_validation";
    assert chosen[1]["valid_until"] is None;
}

test "refresh failure never replaces a provider ID with invented reserve evidence" {
    with patch("backup.refresh.refresh_inventory", return_value=None) {
        r = selection_sample();
        assert r["results"] == [] and r["selection"]["outcome"] == "provider_unavailable";
        assert len({o["provider_id"] for o in r["evaluated_options"]}) == 4;
        assert all(o["source"] == "" and o["cost"]["projected_total_minor"] is None for o in r["evaluated_options"]);
    }
}

test "unsupported destination remains no inventory even with reserve candidates" {
    (trip, risk, _) = build_fixture("rain", "family", SELECT_CLOCK);
    r = run_workflow(trip, risk, "Kyoto", "unchanged", SELECT_CLOCK);
    assert r["selection"]["outcome"] == "no_inventory" and r["evaluated_options"] == [];
}

test "retained evidence still bounds a selected fallback lifetime" {
    (trip, risk, _) = build_fixture("rain", "family", SELECT_CLOCK);
    deadline = SELECT_CLOCK + timedelta(minutes=2);
    risk = replace(risk, evidence=replace(risk.evidence, expires_at=deadline.isoformat()));
    r = run_workflow(trip, risk, "Boston", "sold_out", SELECT_CLOCK);
    assert r["expires_at"] == deadline.isoformat();
    assert all(o["valid_until"] == deadline.isoformat() for o in r["results"]);
}
