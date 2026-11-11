"""Roam adapter tests using records shaped like server/main.jac ItemView JSON."""

glob TRIP: dict[str, any] = {"id": "t1", "title": "Kyoto week", "destination": "Kyoto, Japan", "currency": "JPY"};

def item(category: str, extra: dict[str, any] = {}) -> dict[str, any] {
    base = {"id": "i-" + category, "trip_id": "t1", "title": category.title(), "category": category,
        "date": "", "time": "", "location": "", "reference": "", "notes": "",
        "cost_cents": 0, "done": False, "paid": False};
    return {**base, **extra};
}

test "Roam items map to nodes, keeping unknowns unknown" {
    items = [
        item("stay", {"date": "2026-11-01", "time": "15:00", "cost_cents": 90000, "done": True, "paid": True}),
        item("activity", {"date": "2026-11-02", "cost_cents": 1250}),
        item("packing"),
        item("expense", {"cost_cents": 6500})
    ];
    g = graph_from_roam(TRIP, items, "Asia/Tokyo");
    assert [n.id for n in g.nodes] == ["i-stay", "i-activity"];
    assert g.edges == [];
    stay = g.nodes[0];
    assert stay.kind == NodeKind.STAY and stay.booking_status == BookingStatus.BOOKED;
    assert stay.start_local == "2026-11-01T15:00" and stay.end_local == "";
    assert stay.paid_minor == 90000 and stay.currency == "JPY" and stay.area == "Kyoto, Japan";
    activity = g.nodes[1];
    assert activity.start_local == "" and activity.paid_minor == 0 and activity.price_minor == 1250;
}

test "a done activity is completed and a zero cost is unknown" {
    g = graph_from_roam(TRIP, [item("activity", {"done": True})]);
    assert g.nodes[0].booking_status == BookingStatus.COMPLETED;
    assert g.nodes[0].price_minor is None and g.nodes[0].paid_minor is None;
    assert g.nodes[0].tz == "";
}
