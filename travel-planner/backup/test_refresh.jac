"""State transitions and freshness boundaries for the synthetic refresh adapter."""
import from copy { deepcopy }
import from dataclasses { replace }
import from datetime { datetime, timedelta, timezone }
import from backup.refresh { refresh_alternatives }
import from backup.validation_fixtures { run_fixture, build_fixture }

glob CLOCK = datetime(2026, 11, 10, 12, tzinfo=timezone.utc);
def sample(change: str = "unchanged", now: datetime = CLOCK, budget: str = "600") -> dict[str, any] {
    return run_fixture(now=now, budget=budget, inventory_change=change, sample_date="2026-11-17");
}

test "price increase rechecks full trip and original payment rather than reusing pass" {
    before = sample();
    after = sample("price_increase", CLOCK + timedelta(minutes=1));
    assert before["results"][0]["status"] == "passed_fixture_checks";
    assert after["results"][0]["status"] == "invalid";
    assert after["results"][0]["cost"]["projected_total_minor"] == 64000;
    assert after["results"][0]["cost"]["retained_original_payment_minor"] == 1500;
    assert after["results"][1]["status"] == "passed_fixture_checks";
    assert before["results"][0]["cost"]["projected_total_minor"] == 44000;
    assert before["refresh_id"] != after["refresh_id"];
    assert before["results"][0]["evidence_fingerprint"] != after["results"][0]["evidence_fingerprint"];
}

test "refresh snapshots are not cumulative and can recover" {
    sample("price_increase");
    sample("provider_failure");
    recovered = sample("unchanged", CLOCK + timedelta(minutes=3));
    assert recovered["summary"]["passed_fixture_checks"] == 2;
    assert recovered["results"][0]["cost"]["projected_total_minor"] == 44000;
}

test "sold out alternatives never retain a passing state" {
    single = sample("sold_out");
    assert single["summary"]["invalid"] == 1 and single["summary"]["passed_fixture_checks"] == 1;
    both = sample("all_sold_out");
    assert both["summary"]["invalid"] == 2;
    assert both["message"].startswith("No alternative");
    assert all(r["valid_until"] is None for r in both["results"]);
}

test "provider failure clears costs evidence and passes but keeps reasons" {
    result = sample("provider_failure");
    assert result["summary"]["needs_validation"] == 2;
    for option in result["results"] {
        assert option["refresh_state"] == "provider_error";
        assert option["cost"]["projected_total_minor"] is None;
        assert option["source"] == "" and option["valid_until"] is None;
        assert any(c["code"] == "provider_refresh" for c in option["checks"]);
        replacement = [i for i in option["proposed_items"] if i["id"] == "activity"][0];
        assert replacement["cost_minor"] is None and replacement["evidence"] is None;
        assert replacement["availability"] == "unknown";
    }
}

test "failure of one candidate does not suppress another provider response" {
    r = sample("partial_failure");
    assert r["results"][0]["status"] == "needs_validation";
    assert r["results"][1]["status"] == "passed_fixture_checks";
    assert r["results"][1]["cost"]["projected_total_minor"] == 47000;
}

test "returned expired evidence is not timestamped as fresh" {
    r = sample("expired_evidence");
    assert r["results"][0]["status"] == "needs_validation";
    assert r["results"][0]["evidence_expires_at"] == CLOCK.isoformat();
    assert r["results"][0]["valid_until"] is None;
    assert r["results"][1]["status"] == "passed_fixture_checks";
}

test "successful refresh renews expired candidate evidence" {
    r = run_fixture("stale_evidence", now=CLOCK, inventory_change="unchanged");
    assert r["summary"]["passed_fixture_checks"] == 2;
}

test "successful response cannot invent missing mandatory facts" {
    r = run_fixture("missing_evidence", now=CLOCK, inventory_change="unchanged");
    assert r["results"][0]["status"] == "needs_validation";
    assert r["results"][0]["cost"]["projected_total_minor"] is None;
    for scenario in ["fixed_item", "eligibility_conflict", "schedule_conflict"] {
        r = run_fixture(scenario, now=CLOCK, inventory_change="unchanged");
        assert r["results"][0]["status"] == "invalid";
    }
}

test "candidate refresh cannot renew old trip or risk evidence" {
    (trip, risk, candidates) = build_fixture("rain", "family", CLOCK);
    r = refresh_alternatives(trip, risk, candidates, "unchanged", CLOCK + timedelta(minutes=15));
    assert r["summary"]["needs_validation"] == 2;
    assert all(option["valid_until"] is None for option in r["results"]);
    assert any(c["code"] == "risk_evidence" and c["status"] == "unknown" for c in r["results"][0]["checks"]);
}

test "earliest retained evidence expiry limits the new result lifetime" {
    (trip, risk, candidates) = build_fixture("rain", "family", CLOCK);
    expiry = CLOCK + timedelta(minutes=2);
    risk = replace(risk, evidence=replace(risk.evidence, expires_at=expiry.isoformat()));
    r = refresh_alternatives(trip, risk, candidates, "unchanged", CLOCK + timedelta(minutes=1));
    assert r["expires_at"] == expiry.isoformat();
    assert all(option["valid_until"] == expiry.isoformat() for option in r["results"]);
}

test "same sample date is preserved across UTC midnight" {
    a = sample();
    b = sample("unchanged", CLOCK + timedelta(days=1));
    assert a["trip_date"] == b["trip_date"];
    assert a["results"][0]["proposed_items"][0]["start"] == b["results"][0]["proposed_items"][0]["start"];
}

test "input changes cause fresh validation and fingerprints" {
    original = sample();
    low = sample(budget="400");
    assert low["summary"]["invalid"] == 2;
    assert original["results"][0]["base_snapshot"] != low["results"][0]["base_snapshot"];
    solo = run_fixture("eligibility_conflict", "solo", now=CLOCK, inventory_change="unchanged");
    family = run_fixture("eligibility_conflict", "family", now=CLOCK, inventory_change="unchanged");
    assert solo["results"][0]["status"] == "passed_fixture_checks";
    assert family["results"][0]["status"] == "invalid";
    assert solo["results"][0]["evidence_fingerprint"] != family["results"][0]["evidence_fingerprint"];
}

test "refresh is pure and result mutation cannot affect input or another refresh" {
    (trip, risk, candidates) = build_fixture("rain", "family", CLOCK);
    original = deepcopy((trip, risk, candidates));
    r = refresh_alternatives(trip, risk, candidates, "sold_out", CLOCK);
    r["results"][0]["proposed_items"][0]["title"] = "modified result";
    assert (trip, risk, candidates) == original;
    r2 = refresh_alternatives(trip, risk, candidates, "unchanged", CLOCK);
    assert r2["summary"]["passed_fixture_checks"] == 2;
    assert r2["results"][0]["proposed_items"][0]["title"] != "modified result";
}

test "empty inventory gives explicit no alternative reason" {
    (trip, risk, candidates) = build_fixture("rain", "family", CLOCK);
    r = refresh_alternatives(trip, risk, (), "unchanged", CLOCK);
    assert r["results"] == [] and r["message"].startswith("No alternative");
}

test "invalid refresh inputs fail explicitly" {
    for change in ["bogus", "fresh-ish"] {
        caught = False;
        try { sample(change); } except ValueError { caught = True; }
        assert caught;
    }
    for day in ["bad", "2026-02-30", "20261117"] {
        caught = False;
        try { run_fixture(now=CLOCK, inventory_change="unchanged", sample_date=day); }
        except ValueError { caught = True; }
        assert caught;
    }
    (trip, risk, candidates) = build_fixture("rain", "family", CLOCK);
    caught = False;
    try { refresh_alternatives(trip, risk, candidates, "unchanged", CLOCK.replace(tzinfo=None)); }
    except ValueError { caught = True; }
    assert caught;
}
