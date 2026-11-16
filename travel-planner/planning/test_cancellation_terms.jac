"""Cancellation terms shown beside each alternative keep free, fee-qualified,
no-refund and unknown terms distinct, and never turn missing terms into free."""
import from copy { deepcopy }
import from datetime { datetime, timezone, timedelta }
import from planning.fixtures { sample_state }
import from planning.context { build_context }
import from planning.engine { generate_plans }
import from schema.alternative { alternative_from_dict }

glob TERMS_CLOCK = datetime(2026, 10, 30, 12, tzinfo=timezone.utc);
glob SOURCE = "fixture://boston/garden-ticket-terms";

"""The garden visit's terms on the first plan that replaces it.

The sample keeps every item unpaid; `paid` marks the USD 45.00 tickets as paid in
full so refund amounts can be checked.
"""
def garden_terms(facts: dict[str, any] | None = None, paid: bool = True) -> dict[str, any] {
    (state, sample) = sample_state(TERMS_CLOCK);
    for item in state["items"] { if item["id"] == "activity" { item["paid"] = paid; } }
    plans = generate_plans(build_context(state, facts or sample, TERMS_CLOCK), TERMS_CLOCK, max_plans=5)["plans"];
    replacing = [p for p in plans if any(t["item_id"] == "activity" for t in p["comparison"]["cancellation"])];
    assert replacing, str([p["comparison"]["cancellation"] for p in plans]);
    return next(t for t in replacing[0]["comparison"]["cancellation"] if t["item_id"] == "activity");
}

def sample_facts -> dict[str, any] {
    (_, facts) = sample_state(TERMS_CLOCK);
    return deepcopy(facts);
}

test "free cancellation shows its deadline and the cited excerpt" {
    terms = garden_terms();
    assert terms["state"] == "free" and terms["current"];
    assert terms["paid_minor"] == 4500 and terms["refund_minor"] == 4500 and terms["fee_minor"] == 0;
    assert terms["refund_form"] == "cash" and terms["deadline_local"] and terms["zone"] == "America/New_York";
    assert terms["excerpts"][0]["source"] == SOURCE and "full refund" in terms["excerpts"][0]["text"];
    assert terms["unknowns"] == [];
}

test "after the free deadline a fee-qualified refund is not reported as free" {
    facts = sample_facts();
    facts["policies"][0]["tiers"][0]["hours_before_start"] = 24 * 30;
    terms = garden_terms(facts);
    assert terms["state"] == "fee";
    assert terms["refund_minor"] == 4000 and terms["fee_minor"] == 500;
}

test "an explicit no-refund term stays distinct from a fee" {
    facts = sample_facts();
    facts["policies"][0]["tiers"] = [{"evidence_id": "garden-ticket-terms", "refund_percent": 0, "refund_form": "none"}];
    terms = garden_terms(facts);
    assert terms["state"] == "no_refund" and terms["refund_minor"] == 0;
}

test "unknown refund terms stay open questions with no amount" {
    facts = sample_facts();
    facts["policies"][0]["tiers"] = [{"evidence_id": "garden-ticket-terms", "hours_before_start": 24}];
    terms = garden_terms(facts);
    assert terms["state"] == "unknown" and terms["refund_minor"] is None;
    assert "refund percentage" in terms["unknowns"];
}

test "a paid booking without terms is an open question, never free" {
    facts = sample_facts();
    facts["policies"] = [];
    facts["items"]["activity"].pop("policy_id");
    terms = garden_terms(facts);
    assert terms["state"] == "no_terms" and terms["refund_minor"] is None and terms["excerpts"] == [];
    assert terms["unknowns"] == ["cancellation terms"];
    unpaid = garden_terms(facts, paid=False);
    assert unpaid["state"] == "nothing_paid" and unpaid["unknowns"] == [];
}

test "an expired terms source is flagged instead of trusted" {
    facts = sample_facts();
    facts["evidence_deadlines"]["garden-ticket-terms"] = (TERMS_CLOCK - timedelta(minutes=1)).isoformat();
    terms = garden_terms(facts);
    assert not terms["current"] and "a current source for these terms" in terms["unknowns"];
}

test "the contract accepts the terms and rejects an unknown state" {
    (state, facts) = sample_state(TERMS_CLOCK);
    plan = generate_plans(build_context(state, facts, TERMS_CLOCK), TERMS_CLOCK, max_plans=5)["plans"][0];
    assert alternative_from_dict(plan).comparison.cancellation == plan["comparison"]["cancellation"];
    broken = deepcopy(plan);
    broken["comparison"]["cancellation"] = [{"state": "refundable", "paid_minor": 0}];
    try { alternative_from_dict(broken); assert False, "accepted an unknown state"; }
    except ValueError as exc { assert "cancellation state" in str(exc); }
}
