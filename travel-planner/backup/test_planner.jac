"""Deterministic mock search, freshness, rejection and no-mutation checks."""
import copy;
import datetime;
import from backup.fixtures { demo_trip, demo_items }
import from backup.planner { prepare, screen }
import from tools.alternatives.mock { search, refresh }

def clock -> datetime.datetime { return datetime.datetime.fromisoformat("2026-10-06T12:00:00+00:00"); }

test "rain and arrival delay produce linked deterministic Plan B and C drafts" {
    for (item_id, trigger) in [("outdoor-walk", "rain"), ("dinner", "arrival_delay")] {
        first = prepare(demo_trip(), demo_items(), item_id, trigger, clock());
        second = prepare(demo_trip(), demo_items(), item_id, trigger, clock());
        assert [option.label for option in first.options] == ["Plan B", "Plan C"];
        assert [option.id for option in first.options] == [option.id for option in second.options];
        assert first.mode == "mock" and first.status == "needs_validation";
        for option in first.options {
            assert option.replaced_item_id == item_id;
            assert option.validation_status == "needs_validation" and len(option.validation_notes) == 4;
            assert option.candidate.source_ref.startswith("mock://");
        }
        if trigger == "rain" { assert len(first.exclusions) == 2; }
    }
}

test "prepare preserves inputs and fingerprint changes with trip edits" {
    trip = demo_trip(); items = demo_items();
    original_trip = copy.deepcopy(trip); original_items = copy.deepcopy(items);
    first = prepare(trip, items, "outdoor-walk", "rain", clock());
    assert trip == original_trip and items == original_items;
    trip["budget_cents"] = 190000;
    assert prepare(trip, items, "outdoor-walk", "rain", clock()).base_snapshot != first.base_snapshot;
    trip = original_trip; items[1]["title"] = "Changed dinner";
    assert prepare(trip, items, "outdoor-walk", "rain", clock()).base_snapshot != first.base_snapshot;
}

test "unsupported location and mixed currency have explicit empty results" {
    trip = demo_trip(); trip["destination"] = "Kyoto";
    result = prepare(trip, demo_items(), "outdoor-walk", "rain", clock());
    assert result.options == [] and result.status == "no_candidates";
    trip = demo_trip(); trip["currency"] = "EUR";
    result = prepare(trip, demo_items(), "outdoor-walk", "rain", clock());
    assert result.options == [] and len(result.exclusions) == 4;
}

test "wrong target trigger completed and undated inputs are rejected" {
    for (item_id, trigger) in [("missing", "rain"), ("dinner", "rain"), ("outdoor-walk", "arrival_delay"), ("outdoor-walk", "snow")] {
        rejected = False;
        try { prepare(demo_trip(), demo_items(), item_id, trigger, clock()); }
        except ValueError { rejected = True; }
        assert rejected;
    }
    for change in [{"done": True}, {"date": ""}] {
        items = demo_items(); items[0].update(change); rejected = False;
        try { prepare(demo_trip(), items, "outdoor-walk", "rain", clock()); }
        except ValueError { rejected = True; }
        assert rejected;
    }
}

test "unknown and unavailable inventory is never eligible" {
    candidates = search("Boston", "activity", clock());
    assert screen(candidates[2], "USD", clock()) == "Inventory unavailable";
    assert screen(candidates[3], "USD", clock()) == "Inventory unknown";
}

test "freshness rejects expiry boundary future malformed and timezone free evidence" {
    candidate = search("Boston", "activity", clock())[0];
    assert screen(candidate, "USD", clock()) == "";
    assert screen(candidate, "USD", clock() + datetime.timedelta(minutes=15)) != "";
    for timestamp in ["garbage", "2026-10-06T12:00:00", "2026-10-06T13:00:00+00:00"] {
        candidate = search("Boston", "activity", clock())[0]; candidate.checked_at = timestamp;
        assert screen(candidate, "USD", clock()) != "";
    }
    candidate = search("Boston", "activity", clock())[0]; candidate.expires_at = candidate.checked_at;
    assert screen(candidate, "USD", clock()) != "";
}

test "missing provenance negative prices and currency mismatch are rejected" {
    candidate = search("Boston", "activity", clock())[0];
    assert screen(candidate, "JPY", clock()) != "";
    candidate.estimated_cost_minor = -1;
    assert screen(candidate, "USD", clock()) != "";
    candidate.estimated_cost_minor = 1800; candidate.source_ref = "";
    assert screen(candidate, "USD", clock()) != "";
}

test "refresh returns fresh evidence without mutating an earlier candidate" {
    old = refresh("indoor-gallery", clock());
    fresh = refresh("indoor-gallery", clock() + datetime.timedelta(minutes=20));
    assert old is not None and fresh is not None;
    assert old.id == fresh.id and old.checked_at != fresh.checked_at;
    assert screen(old, "USD", clock() + datetime.timedelta(minutes=20)) != "";
    assert screen(fresh, "USD", clock() + datetime.timedelta(minutes=20)) == "";
    assert refresh("does-not-exist", clock()) is None;
}
