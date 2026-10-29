"""Accounting, elapsed-time and freshness boundaries for backup change explanations."""
import json;
import from copy { deepcopy }
import from dataclasses { replace }
import from datetime { datetime, timedelta, timezone }
import from backup.changes { describe_changes }
import from backup.refresh { refresh_alternatives }
import from backup.validation { validate_replacement }
import from backup.validation_models { Moment }
import from backup.validation_fixtures { build_fixture, run_fixture }

glob CHANGE_CLOCK = datetime(2026, 11, 10, 12, tzinfo=timezone.utc);

test "rain changes include retained payments once and explain Plan C timing" {
    result_data = run_fixture(now=CHANGE_CLOCK, inventory_change="unchanged");
    b = result_data["results"][0]["changes"]; c = result_data["results"][1]["changes"];
    assert b["cost"]["original_total_minor"] == 41000;
    assert b["cost"]["proposed_total_minor"] == 44000;
    assert b["cost"]["delta_minor"] == 3000;
    assert b["cost"]["original_quote_minor"] == 4500;
    assert b["cost"]["replacement_quote_minor"] == 6000;
    assert b["cost"]["budget_remaining_minor"] == 16000;
    assert c["cost"]["delta_minor"] == 6000;
    assert c["schedule"]["start_shift_minutes"] == 15;
    assert c["schedule"]["end_shift_minutes"] == 30;
    assert c["schedule"]["duration_delta_minutes"] == 15;
    assert b["unchanged_item_count"] == 3 and b["item_id"] == "activity";
    assert b["unknown_reasons"] == [] and json.loads(json.dumps(b)) == b;
}

test "late dinner can lower planned cost without implying cash refund or ranking" {
    r = run_fixture("arrival_delay", now=CHANGE_CLOCK, inventory_change="unchanged");
    b = r["results"][0]["changes"];
    assert b["cost"]["delta_minor"] == -1500;
    assert b["schedule"]["start_shift_minutes"] == 60;
    assert b["schedule"]["duration_delta_minutes"] == 0;
    assert "not an amount due now" in b["notice"] and "no refund assumed" in b["notice"];
    assert [o["candidate_id"] for o in r["results"]] == ["plan-b", "plan-c"];
}

test "retained itinerary payments are already included in their quotes" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    items = tuple(replace(i, paid_minor=i.cost_minor) if i.id != "activity" else i for i in trip.items);
    r = refresh_alternatives(replace(trip, items=items), risk, candidates, "unchanged", CHANGE_CLOCK);
    assert r["results"][0]["changes"]["cost"]["delta_minor"] == 3000;
    assert r["results"][0]["cost"]["projected_total_minor"] == 44000;
}

test "price increase explains negative budget remaining and keeps rejection" {
    r = run_fixture(now=CHANGE_CLOCK, inventory_change="price_increase");
    b = r["results"][0];
    assert b["status"] == "invalid";
    assert b["changes"]["cost"]["delta_minor"] == 23000;
    assert b["changes"]["cost"]["budget_remaining_minor"] == -4000;
    assert r["results"][1]["status"] == "passed_fixture_checks";
    sold = run_fixture("arrival_delay", now=CHANGE_CLOCK, inventory_change="sold_out");
    assert (sold["results"][0]["changes"]["cost"]["delta_minor"] < 0);
    assert sold["results"][0]["status"] == "invalid";
}

test "provider failure and expired evidence cannot supply price or timing changes" {
    for change in ["provider_failure", "expired_evidence"] {
        r = run_fixture(now=CHANGE_CLOCK, inventory_change=change);
        b = r["results"][0]["changes"];
        assert b["cost"]["original_total_minor"] == 41000;
        assert b["cost"]["proposed_total_minor"] is None;
        assert b["cost"]["delta_minor"] is None and b["cost"]["replacement_quote_minor"] is None;
        assert b["schedule"]["start_shift_minutes"] is None;
        assert any("Timing change unknown" in s for s in b["unknown_reasons"]);
    }
    recovered = run_fixture(now=CHANGE_CLOCK, inventory_change="unchanged");
    assert recovered["results"][0]["changes"]["cost"]["delta_minor"] == 3000;
}

test "missing original quotes or payment evidence leaves the baseline unknown" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    for fields in [{"cost_minor": None}, {"cost_minor": True}, {"party_size": True},
        {"currency": "EUR"}, {"fees_included": None}, {"paid_minor": None},
        {"evidence": None}] {
        changed = replace(trip, items=tuple(replace(i, **fields) if i.id == "activity" else i for i in trip.items));
        r = refresh_alternatives(changed, risk, candidates, "unchanged", CHANGE_CLOCK);
        b = r["results"][0]["changes"];
        assert b["cost"]["original_total_minor"] is None, str(fields);
        assert b["cost"]["delta_minor"] is None;
        assert any("Original planned total unknown" in reason for reason in b["unknown_reasons"]);
    }
    unknown_budget = run_fixture(budget="", now=CHANGE_CLOCK, inventory_change="unchanged");
    b = unknown_budget["results"][0]["changes"];
    assert b["cost"]["delta_minor"] == 3000 and b["cost"]["budget_remaining_minor"] is None;
}

test "earliest original target evidence also limits the current comparison lifetime" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    expiry = CHANGE_CLOCK + timedelta(minutes=2);
    trip = replace(trip, items=tuple(replace(i, evidence=replace(i.evidence, expires_at=expiry.isoformat()))
        if i.id == "activity" else i for i in trip.items));
    current = refresh_alternatives(trip, risk, candidates, "unchanged", CHANGE_CLOCK);
    assert current["expires_at"] == expiry.isoformat();
    assert current["results"][0]["valid_until"] != current["expires_at"];
    expired = refresh_alternatives(trip, risk, candidates, "unchanged", expiry);
    assert expired["results"][0]["changes"]["cost"]["delta_minor"] is None;
    assert expired["results"][0]["changes"]["schedule"]["start_shift_minutes"] is None;
}

test "cross midnight and cross timezone timing uses elapsed UTC minutes" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    old = replace(trip.items[1], start=Moment("2026-11-17T23:30", "America/New_York"),
        end=Moment("2026-11-18T00:30", "America/New_York"));
    trip = replace(trip, items=tuple(old if i.id == old.id else i for i in trip.items));
    candidate = replace(candidates[0], item=replace(candidates[0].item,
        start=Moment("2026-11-18T05:00", "UTC"), end=Moment("2026-11-18T06:30", "UTC")));
    c = describe_changes(trip, candidate, validate_replacement(trip, risk, candidate, CHANGE_CLOCK), CHANGE_CLOCK);
    assert c["schedule"]["start_shift_minutes"] == 30;
    assert c["schedule"]["end_shift_minutes"] == 60;
    assert c["schedule"]["duration_delta_minutes"] == 30;
}

test "DST folds are explicit and ambiguous timing never gets a guessed difference" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    old = replace(trip.items[1], start=Moment("2026-11-01T01:00", "America/New_York", 0),
        end=Moment("2026-11-01T01:30", "America/New_York", 0));
    trip = replace(trip, items=tuple(old if i.id == old.id else i for i in trip.items));
    candidate = replace(candidates[0], item=replace(candidates[0].item,
        start=replace(old.start, fold=1), end=replace(old.end, fold=1)));
    r = validate_replacement(trip, risk, candidate, CHANGE_CLOCK);
    c = describe_changes(trip, candidate, r, CHANGE_CLOCK);
    assert c["schedule"]["start_shift_minutes"] == 60 and c["schedule"]["duration_delta_minutes"] == 0;
    ambiguous = replace(candidate, item=replace(candidate.item, start=replace(candidate.item.start, fold=None)));
    c = describe_changes(trip, ambiguous, r, CHANGE_CLOCK);
    assert c["schedule"]["start_shift_minutes"] is None;
    assert any("Ambiguous DST" in s for s in c["unknown_reasons"]);
}

test "nonpositive duration and nonexistent DST times remain unknown metrics" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    for start in [candidates[0].item.end, Moment("2026-03-08T02:30", "America/New_York")] {
        candidate = replace(candidates[0], item=replace(candidates[0].item, start=start));
        r = validate_replacement(trip, risk, candidate, CHANGE_CLOCK);
        c = describe_changes(trip, candidate, r, CHANGE_CLOCK);
        assert c["schedule"]["start_shift_minutes"] is None;
        assert c["schedule"]["duration_delta_minutes"] is None;
    }
}

test "metrics are pure and malformed replacement scope has no explanation" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    r = validate_replacement(trip, risk, candidates[0], CHANGE_CLOCK);
    before = deepcopy((trip, candidates, r));
    c = describe_changes(trip, candidates[0], r, CHANGE_CLOCK);
    c["schedule"]["original_start"]["local"] = "changed";
    assert (trip, candidates, r) == before;
    assert describe_changes(trip, replace(candidates[0], replaces_id="missing"), r, CHANGE_CLOCK) is None;
}

test "zero totals and exact budget equality are known values" {
    (trip, risk, candidates) = build_fixture("rain", "family", CHANGE_CLOCK);
    trip = replace(trip, reserve_minor=0, budget_minor=0,
        items=tuple(replace(i, cost_minor=0, paid_minor=0) for i in trip.items));
    candidates = tuple(replace(c, item=replace(c.item, cost_minor=0)) for c in candidates);
    r = refresh_alternatives(trip, risk, candidates, "unchanged", CHANGE_CLOCK);
    b = r["results"][0]["changes"];
    assert b["cost"]["original_total_minor"] == 0 and b["cost"]["proposed_total_minor"] == 0;
    assert b["cost"]["delta_minor"] == 0 and b["cost"]["budget_remaining_minor"] == 0;
}
