"""Build a budget ledger from a Roam trip and its items.

Pure function: the trip and items are plain dicts in Roam's TripView and
ItemView shape. They are read, never changed. Bad input raises ValueError.
"""
import from budget.models { BudgetLedger, LedgerLine, LEDGER_CONTRACT_VERSION, COMMITTED_BOOKING_CATEGORIES }

"""True only for a real whole number. True and False are rejected even though Python treats them as 1 and 0."""
def _is_whole_number(value: any) -> bool {
    if isinstance(value, bool) {
        return False;
    }
    return isinstance(value, int);
}

def _require_cents(value: any, label: str) -> int {
    if not _is_whole_number(value) or value < 0 {
        raise ValueError(label + " must be a whole, non-negative number of cents");
    }
    return value;
}

def _is_committed(item: dict[str, any]) -> bool {
    if item["paid"] {
        return True;
    }
    return item["category"] in COMMITTED_BOOKING_CATEGORIES and item["done"];
}

def _check_trip(trip: dict[str, any]) -> None {
    if not str(trip.get("id", "")).strip() {
        raise ValueError("The trip needs an id");
    }
    if not str(trip.get("currency", "")).strip() {
        raise ValueError("The trip needs a currency");
    }
    _require_cents(trip.get("budget_cents"), "The trip budget");
}

def _check_item(item: dict[str, any], trip: dict[str, any], seen_ids: list[str]) -> None {
    item_id = str(item.get("id", ""));
    if not item_id.strip() {
        raise ValueError("Each item needs an id");
    }
    if item.get("trip_id") != trip["id"] {
        raise ValueError("Item " + item_id + " belongs to a different trip");
    }
    if item_id in seen_ids {
        raise ValueError("Item " + item_id + " is listed more than once; each cost is counted once");
    }
    _require_cents(item.get("cost_cents"), "The cost of item " + item_id);
    # Roam items carry no currency of their own. If one does, it must match the trip.
    if "currency" in item and item["currency"] != trip["currency"] {
        raise ValueError("Item " + item_id + " is in " + str(item["currency"]) + " but the trip is in "
            + str(trip["currency"]) + "; mixing currencies needs an exchange-rate record");
    }
}

"""Total a trip's costs.

`contingency_cents` is money set aside for surprises. It is not an item; it
only reduces what is remaining. A budget of 0 means no budget is set, as in Roam.
"""
def build_ledger(trip: dict[str, any], items: list[dict[str, any]], contingency_cents: int = 0) -> BudgetLedger {
    _check_trip(trip);
    _require_cents(contingency_cents, "The contingency");

    seen_ids: list[str] = [];
    lines: list[LedgerLine] = [];
    planned = 0;
    paid = 0;
    committed = 0;
    for item in items {
        _check_item(item, trip, seen_ids);
        seen_ids.append(item["id"]);
        cost = item["cost_cents"];
        if cost == 0 {
            continue;    # packing and free items add nothing
        }
        is_committed = _is_committed(item);
        lines.append(LedgerLine(item_id=item["id"], title=item["title"], category=item["category"],
            cost_cents=cost, paid=bool(item["paid"]), committed=is_committed));
        planned += cost;
        if item["paid"] {
            paid += cost;
        }
        if is_committed {
            committed += cost;
        }
    }

    budget: int | None = None;
    remaining: int | None = None;
    over_budget = 0;
    if trip["budget_cents"] > 0 {
        budget = trip["budget_cents"];
        remaining = budget - planned - contingency_cents;
        if remaining < 0 {
            over_budget = -remaining;
        }
    }
    return BudgetLedger(contract_version=LEDGER_CONTRACT_VERSION, trip_id=trip["id"],
        currency=trip["currency"], budget_cents=budget, planned_cents=planned, paid_cents=paid,
        unpaid_cents=planned - paid, committed_cents=committed, estimated_cents=planned - committed,
        contingency_cents=contingency_cents, remaining_cents=remaining, over_budget_cents=over_budget,
        lines=lines);
}
