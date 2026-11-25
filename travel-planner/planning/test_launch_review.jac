"""Launch-guide acceptance: policy conclusions, evidence, recovery and protection."""
import from tests.workspace_fixture { TEST_WORKSPACE }
import os;
import tempfile;
import unittest;
import from copy { deepcopy }
import from datetime { datetime, timedelta, timezone }
import from unittest.mock { patch }
import from uuid { uuid4 }
import from planning.fixtures { sample_state }
import from planning.context { build_context, public_context }
import from planning.engine { generate_plans }
import from policy.review { saved_policy_reviews }
import assistant.provider as provider;
import server.main as service;

glob REVIEW_NOW = datetime(2026, 11, 1, 12, tzinfo=timezone.utc);

def policy_fixture -> tuple[dict[str, any], dict[str, any]] {
    (state, facts) = sample_state(REVIEW_NOW);
    for item in state["items"] { if item["id"] == "activity" { item["paid"] = True; item["cost_cents"] = 10000; } }
    facts["items"]["activity"]["policy_id"] = "policy";
    facts["evidence"].append({"id":"terms", "source_ref":"https://example.com/booking/terms", "excerpt":"Full refund less a $10 cancellation fee before November 2, 2026 at 18:00.", "retrieved_at":REVIEW_NOW.isoformat(), "origin":"user"});
    facts["evidence_deadlines"]["terms"] = (REVIEW_NOW + timedelta(minutes=10)).isoformat();
    facts["policies"] = [{"id":"policy", "booking_node_id":"activity", "scope":"Rate-specific terms", "tz":"America/New_York", "currency":"USD", "retrieved_at":REVIEW_NOW.isoformat(),
        "tiers":[{"evidence_id":"terms", "refund_percent":100, "fee_minor":1000, "refund_form":"cash", "deadline_local":"2026-11-02T18:00"}]}];
    return (state, facts);
}

test "candidate cards receive the applicable fee deadline excerpt and source without deducting refunds" {
    (state, facts) = policy_fixture(); context = build_context(state, facts, REVIEW_NOW);
    weather = [r["id"] for r in context["risks"] if r["category"] == "weather"];
    plans = generate_plans(context, REVIEW_NOW, weather)["plans"]; assert plans;
    for plan in plans {
        row = plan["comparison"]["policy_reviews"][0];
        assert row["state"] == "partial_refund" and row["fee"] == "10.00 USD" and row["refund"] == "90.00 USD";
        assert row["deadline"].startswith("2026-11-02T18:00") and row["sources"][0]["excerpt"] == facts["evidence"][-1]["excerpt"];
        assert row["sources"][0]["source"] == "https://example.com/booking/terms";
        assert plan["comparison"]["confirmed_refund_minor"] == 0;
        assert plan["comparison"]["projected_total_minor"] == plan["validation"]["projected_total_minor"];
    }
    public = public_context(context);
    assert any(r["sources"] for r in public["risks"] if r["rule_id"] == "booking_terms");
}

test "free cancellation exclusions and incomplete or expired policies stay distinct" {
    for mode in ("free", "excluded", "missing_fee", "expired", "no_timezone", "currency", "missing_policy") {
        (state, facts) = policy_fixture(); tier = facts["policies"][0]["tiers"][0];
        if mode == "free" { tier["fee_minor"] = 0; }
        if mode == "excluded" { tier.update({"fee_minor":0, "refund_percent":0, "refund_form":"none"}); }
        if mode == "missing_fee" { tier["fee_minor"] = None; }
        if mode == "expired" { facts["evidence_deadlines"]["terms"] = REVIEW_NOW.isoformat(); }
        if mode == "no_timezone" { facts["zone"] = ""; facts["items"]["activity"]["zone"] = ""; }
        if mode == "currency" { facts["policies"][0]["currency"] = "JPY"; }
        if mode == "missing_policy" { facts["policies"] = []; facts["items"]["activity"].pop("policy_id"); }
        row = next(r for r in saved_policy_reviews(state, facts, REVIEW_NOW) if r["item_id"] == "activity");
        if mode == "free" { assert row["state"] == "free_cancel_open" and row["fee"] == "0.00 USD"; }
        elif mode == "excluded" { assert row["state"] == "no_refund" and row["refund"] == "0.00 USD"; }
        else { assert row["requires_confirmation"] and row["state"] == "unknown" and row["refund"] == "Unknown"; }
    }
}

test "saving exact policy terms is versioned evidence-only and invalidates waiting drafts" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        trip = service.save_trip(TEST_WORKSPACE, "Launch review", "Boston", "2027-01-01", "2027-01-02", "USD", "500");
        item = service.save_item(TEST_WORKSPACE, trip.id, "Museum", "activity", "2027-01-01", "10:00", "Boston", cost="100");
        raw = {"item_id":item.id, "title":item.title, "category":"activity", "date":item.date, "time":"11:00", "duration_minutes":60, "location":item.location, "cost_cents":10000, "notes":"Estimate"};
        response = {"answer":"Draft", "plans":[{"title":"Later museum", "summary":"Move", "changes":[raw]}]};
        with patch.object(provider, "generate", return_value=response) { draft = service.assistant_chat(TEST_WORKSPACE, trip.id, "Move my museum visit", "replan", False, str(uuid4()))["drafts"][0]; }
        before = [(i.id,i.time,i.cost_cents) for i in service.list_items(TEST_WORKSPACE, trip.id)];
        version = service.planning_state(TEST_WORKSPACE, trip.id)["trip_version"];
        terms = "Full refund less a $10 cancellation fee up to 2 days before check-in. No-shows are charged the full stay.";
        result = service.save_policy_terms(TEST_WORKSPACE, trip.id, item.id, terms, "https://example.com/terms", "America/New_York", (datetime.now(timezone.utc)+timedelta(hours=1)).isoformat(), version);
        assert result["trip_version"] > version;
        assert result["policy_reviews"][0]["sources"][0]["excerpt"] in terms;
        assert service.assistant_state(TEST_WORKSPACE, trip.id)["drafts"][0]["status"] == "stale";
        check = unittest.TestCase();
        with check.assertRaises(ValueError) { service.assistant_review(TEST_WORKSPACE, trip.id, draft["id"], True, True); }
        assert [(i.id,i.time,i.cost_cents) for i in service.list_items(TEST_WORKSPACE, trip.id)] == before;
        with check.assertRaises(ValueError) { service.save_policy_terms(TEST_WORKSPACE, trip.id, item.id, terms, "reference", "America/New_York", "2000-01-01T00:00:00Z", result["trip_version"]); }
        with check.assertRaises(ValueError) { service.save_policy_terms(TEST_WORKSPACE, trip.id, "foreign", terms, "reference", "America/New_York", (datetime.now(timezone.utc)+timedelta(hours=1)).isoformat(), result["trip_version"]); }
    }
}

test "pre-deadline refunds do not depend on whether no-show terms are stated" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH":os.path.join(directory, "trip.sqlite3")}) {
        trip = service.save_trip(TEST_WORKSPACE, "No-show review", "Boston", "2031-01-01", "2031-01-03", "USD", "500");
        item = service.save_item(TEST_WORKSPACE, trip.id, "Hotel", "stay", "2031-01-01", "15:00", "Boston", cost="180");
        service.set_item_state(TEST_WORKSPACE, trip.id, item.id, False, True);
        clause = ("Full refund to the original payment method until 6:00 PM local time on December 30, 2030. "
            + "Cancellations after that time are charged $50.00; the remainder is refunded to the original payment method.");
        expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat();
        rows: list[dict[str, any]] = [];
        for terms in (clause, clause + " No-shows are charged the full stay.") {
            version = service.planning_state(TEST_WORKSPACE, trip.id)["trip_version"];
            result = service.save_policy_terms(TEST_WORKSPACE, trip.id, item.id, terms, "https://example.com/terms", "America/New_York", expires, version);
            rows.append(next(r for r in result["policy_reviews"] if r["item_id"] == item.id));
        }
        (missing, stated) = rows;
        for row in rows {
            assert row["state"] == "free_cancel_open" and not row["requires_confirmation"];
            assert row["fee"] == "0.00 USD" and row["refund"] == "180.00 USD" and row["refund_form"] == "cash";
            assert row["deadline"].startswith("2030-12-30T18:00") and row["unknowns"] == [];
        }
        assert missing["later_unknowns"] and "no-show" in missing["later_unknowns"][0].lower();
        assert stated["later_unknowns"] == [];
    }
}
