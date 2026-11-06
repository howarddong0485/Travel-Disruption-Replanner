"""Provider-backed hotel drafts obey existing itinerary constraints without writes."""
import unittest;
import from copy { deepcopy }
import from unittest.mock { patch }
import replan.expedia as planner;

def state_fixture -> dict[str, any] {
    hotel = {"id": "hotel", "trip_id": "trip", "title": "Original hotel", "category": "stay",
        "date": "2027-01-01", "time": "17:00", "location": "Original address", "reference": "private-ref",
        "notes": "", "cost_cents": 20000, "paid": True, "done": True,
        "duration_minutes": 30, "latest_start": "2027-01-01T18:00", "fixed": False, "protected": False};
    dinner = {**hotel, "id": "dinner", "category": "food", "title": "Dinner", "time": "18:00",
        "latest_start": "2027-01-01T23:00", "cost_cents": 3000, "paid": False, "done": False};
    return {"trip": {"id": "trip", "start_date": "2027-01-01", "end_date": "2027-01-03", "currency": "USD", "budget_cents": 100000},
        "items": [hotel, dinner], "dependencies": [{"prerequisite_id": "hotel", "dependent_id": "dinner", "buffer_minutes": 30}], "version": 7};
}

def shopping_fixture -> dict[str, any] {
    return {"mode": "test", "exclusions": [], "offers": [{"id": "expedia:19248:room:rate", "property_id": "19248",
        "title": "Synthetic replacement hotel", "cost_cents": 15000, "source": "Expedia Rapid"}]};
}

test "backup retains prior payment and leaves snapshot untouched" {
    state = state_fixture(); original = deepcopy(state);
    with patch.object(planner, "search_hotels", return_value=shopping_fixture()) {
        result = planner.plans(state, "hotel", "2027-01-03", ["19248"]);
    }
    proposal = result["proposals"][0];
    assert proposal["replacement_cash_cents"] == 15000;
    assert proposal["retained_paid_cents"] == 20000;
    assert proposal["projected_total_cents"] == 38000;
    assert proposal["base_version"] == 7 and proposal["status"] == "needs_validation";
    assert proposal["changes"][0]["after"]["reference"] == "";
    assert proposal["changes"][0]["after"]["location"] == "Synthetic replacement hotel";
    assert state == original;
}

test "delayed hotel arrival shifts downstream dinner" {
    with patch.object(planner, "search_hotels", return_value=shopping_fixture()) {
        result = planner.plans(state_fixture(), "hotel", "2027-01-03", ["19248"], mode="replan", kind="delayed", delay_minutes=120);
    }
    changes = {c["item_id"]: c["after"] for c in result["proposals"][0]["changes"]};
    assert changes["hotel"]["time"] == "19:00";
    assert changes["dinner"]["time"] == "20:00";
}

test "over budget and missing downstream replacements yield no mock fallback" {
    state = state_fixture(); state["trip"]["budget_cents"] = 30000;
    with patch.object(planner, "search_hotels", return_value=shopping_fixture()) {
        result = planner.plans(state, "hotel", "2027-01-03", ["19248"]);
        assert not result["proposals"];
        assert `any("budget" in w for w in result["warnings"]);
        state["trip"]["budget_cents"] = 100000;
        state["items"][1]["latest_start"] = "2027-01-01T18:00";
        result = planner.plans(state, "hotel", "2027-01-03", ["19248"], mode="replan", kind="delayed", delay_minutes=120);
        assert not result["proposals"];
    }
}

test "fixed hotels foreign IDs and invalid stay dates fail before search" {
    check = unittest.TestCase(); state = state_fixture();
    with patch.object(planner, "search_hotels") as search {
        with check.assertRaises(ValueError) { planner.plans(state, "foreign", "2027-01-03", ["19248"]); }
        with check.assertRaises(ValueError) { planner.plans(state, "hotel", "2027-01-01", ["19248"]); }
        state["items"][0]["protected"] = True;
        with check.assertRaises(ValueError) { planner.plans(state, "hotel", "2027-01-03", ["19248"]); }
        search.assert_not_called();
    }
}
