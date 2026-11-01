"""Deterministic checks for the budget ledger, including agreement with Roam's budget page."""
import copy;
import from budget.models { BudgetLedger, LEDGER_CONTRACT_VERSION }
import from budget.fixtures { ledger_trip, ledger_items, over_budget_trip, no_budget_trip }
import from budget.ledger { build_ledger }

def rejected(trip: dict[str, any], items: list[dict[str, any]], contingency_cents: any = 0) -> bool {
    try { build_ledger(trip, items, contingency_cents); }
    except ValueError { return True; }
    return False;
}

test "ledger totals match the formulas on Roam's budget page" {
    for trip in [ledger_trip(), over_budget_trip(), no_budget_trip()] {
        items = ledger_items();
        ledger = build_ledger(trip, items);
        # The same sums frontend.jac and cli/main.jac compute.
        roam_planned = 0;
        roam_paid = 0;
        for item in items {
            roam_planned += item["cost_cents"];
            if item["paid"] { roam_paid += item["cost_cents"]; }
        }
        assert ledger.planned_cents == roam_planned;
        assert ledger.paid_cents == roam_paid;
        assert ledger.unpaid_cents == roam_planned - roam_paid;
        if trip["budget_cents"] {
            assert ledger.remaining_cents == trip["budget_cents"] - roam_planned;
            assert ledger.over_budget_cents == max(0, roam_planned - trip["budget_cents"]);
        }
    }
}

test "ledger lists each costed item once with exact totals" {
    ledger = build_ledger(ledger_trip(), ledger_items());
    assert ledger.contract_version == LEDGER_CONTRACT_VERSION;
    assert ledger.trip_id == "ledger-trip" and ledger.currency == "USD";
    assert ledger.budget_cents == 200000;
    assert ledger.planned_cents == 156000;
    assert ledger.paid_cents == 57500 and ledger.unpaid_cents == 98500;
    assert ledger.committed_cents == 147500 and ledger.estimated_cents == 8500;
    assert ledger.contingency_cents == 0;
    assert ledger.remaining_cents == 44000 and ledger.over_budget_cents == 0;
    assert [line.item_id for line in ledger.lines] == ["hotel", "flight", "museum", "dinner", "insurance"];
}

test "committed means paid or a confirmed transport or stay booking" {
    lines = {};
    for line in build_ledger(ledger_trip(), ledger_items()).lines {
        lines[line.item_id] = line;
    }
    assert lines["hotel"].committed and not lines["hotel"].paid;
    assert lines["flight"].committed and lines["museum"].committed;
    assert not lines["dinner"].committed;

    items = ledger_items();
    items[0]["done"] = False;      # hotel no longer confirmed
    items[3]["done"] = True;       # a completed dinner is not a booking
    ledger = build_ledger(ledger_trip(), items);
    assert ledger.committed_cents == 147500 - 90000;
    assert ledger.estimated_cents == 90000 + 8500;
}

test "overspending is reported explicitly" {
    ledger = build_ledger(over_budget_trip(), ledger_items());
    assert ledger.remaining_cents == -6000;
    assert ledger.over_budget_cents == 6000;
}

test "contingency reduces what remains and can push a trip over budget" {
    ledger = build_ledger(ledger_trip(), ledger_items(), 20000);
    assert ledger.contingency_cents == 20000;
    assert ledger.remaining_cents == 24000 and ledger.over_budget_cents == 0;
    assert ledger.planned_cents == 156000;

    ledger = build_ledger(ledger_trip(), ledger_items(), 50000);
    assert ledger.remaining_cents == -6000 and ledger.over_budget_cents == 6000;
}

test "no budget stays unknown instead of zero" {
    ledger = build_ledger(no_budget_trip(), ledger_items(), 20000);
    assert ledger.budget_cents is None;
    assert ledger.remaining_cents is None;
    assert ledger.over_budget_cents == 0;
    assert ledger.planned_cents == 156000;
}

test "a trip with no items has zero totals" {
    ledger = build_ledger(ledger_trip(), []);
    assert ledger.planned_cents == 0 and ledger.lines == [];
    assert ledger.remaining_cents == 200000;
}

test "bad trips and contingencies are rejected" {
    trip = ledger_trip(); trip["id"] = " ";
    assert rejected(trip, []);
    trip = ledger_trip(); trip["currency"] = "";
    assert rejected(trip, []);
    trip = ledger_trip(); trip["budget_cents"] = -1;
    assert rejected(trip, []);
    trip = ledger_trip(); trip["budget_cents"] = True;
    assert rejected(trip, []);
    trip = ledger_trip(); trip["budget_cents"] = 100.5;
    assert rejected(trip, []);
    assert rejected(ledger_trip(), [], -1);
    assert rejected(ledger_trip(), [], True);
}

test "bad items are rejected so nothing is miscounted" {
    items = ledger_items(); items[0]["trip_id"] = "another-trip";
    assert rejected(ledger_trip(), items);

    items = ledger_items(); items.append(ledger_items()[0]);
    assert rejected(ledger_trip(), items);

    items = ledger_items(); items[1]["cost_cents"] = -100;
    assert rejected(ledger_trip(), items);

    items = ledger_items(); items[1]["cost_cents"] = True;
    assert rejected(ledger_trip(), items);

    items = ledger_items(); items[1]["id"] = "";
    assert rejected(ledger_trip(), items);

    items = ledger_items(); items[1]["currency"] = "EUR";
    assert rejected(ledger_trip(), items);
    items = ledger_items(); items[1]["currency"] = "USD";
    assert not rejected(ledger_trip(), items);
}

test "building a ledger is repeatable and does not change its inputs" {
    trip = ledger_trip();
    items = ledger_items();
    trip_before = copy.deepcopy(trip);
    items_before = copy.deepcopy(items);
    first = build_ledger(trip, items, 20000);
    second = build_ledger(trip, items, 20000);
    assert trip == trip_before and items == items_before;
    assert first.planned_cents == second.planned_cents and first.remaining_cents == second.remaining_cents;
    assert [line.item_id for line in first.lines] == [line.item_id for line in second.lines];
}
