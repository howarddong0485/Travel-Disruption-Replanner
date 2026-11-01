"""Synthetic Roam trips and items for ledger tests. No real bookings.

Shapes match Roam's TripView and ItemView. Each function returns new dicts.
"""

def _item(id: str, title: str, category: str, cost_cents: int, done: bool, paid: bool) -> dict[str, any] {
    return {"id": id, "trip_id": "ledger-trip", "title": title, "category": category,
        "date": "", "time": "", "location": "", "reference": "", "notes": "",
        "cost_cents": cost_cents, "done": done, "paid": paid};
}

"""A Boston trip with a USD 2,000.00 budget."""
def ledger_trip -> dict[str, any] {
    return {"id": "ledger-trip", "title": "Demo Boston trip", "destination": "Boston",
        "start_date": "2026-11-01", "end_date": "2026-11-05", "currency": "USD",
        "budget_cents": 200000, "notes": ""};
}

"""Six items: planned 1,560.00, paid 575.00, committed 1,475.00."""
def ledger_items -> list[dict[str, any]] {
    return [
        _item("hotel", "Demo hotel", "stay", 90000, True, False),            # confirmed, not paid: committed
        _item("flight", "Demo flight", "transport", 45000, True, True),      # paid: committed
        _item("museum", "Demo museum", "activity", 6000, False, True),       # paid: committed
        _item("dinner", "Demo dinner", "food", 8500, False, False),          # estimated
        _item("insurance", "Demo insurance", "expense", 6500, False, True),  # paid: committed
        _item("passport", "Passport", "packing", 0, False, False)            # no cost: not a ledger line
    ];
}

"""The same trip with a USD 1,500.00 budget, so the items overspend by 60.00."""
def over_budget_trip -> dict[str, any] {
    trip = ledger_trip();
    trip["budget_cents"] = 150000;
    return trip;
}

"""The same trip with no budget set (0 in Roam)."""
def no_budget_trip -> dict[str, any] {
    trip = ledger_trip();
    trip["budget_cents"] = 0;
    return trip;
}
