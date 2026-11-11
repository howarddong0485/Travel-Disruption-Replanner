"""Browser actions and ordered refreshes for Roam."""
impl app.resetItem -> None {
    editing_item = ""; item_title = ""; item_date = day; item_time = "";
    location = ""; reference = ""; item_notes = ""; cost = "";
    category = "packing" if tab == "packing" else "transport" if tab == "bookings" else "expense" if tab == "budget" else "activity";
}
impl app.chooseTab(value: str) -> None {
    if busy { return; }
    resetReview(); tab = value; day = ""; railView = "auto"; placeId = ""; resetItem();
}
impl app.openTrip(trip: TripView | None = None) -> None {
    if busy { return; }
    editing_trip = trip.id if trip else "";
    trip_title = trip.title if trip else "";
    destination = trip.destination if trip else "";
    start_date = trip.start_date if trip else today();
    end_date = trip.end_date if trip else today();
    currency = trip.currency if trip else "USD";
    budget = str(trip.budget_cents / 100) if trip else "";
    trip_notes = trip.notes if trip else "";
    trip_form = True; trip_review = False; error = ""; notice = "";
    window.scrollTo({"top": 0, "behavior": "smooth"});
}
impl app.editItem(item: ItemView) -> None {
    resetReview(); railView = "editor";
    editing_item = item.id; item_title = item.title; category = item.category;
    item_date = item.date; item_time = item.time; location = item.location;
    reference = item.reference; item_notes = item.notes; cost = str(item.cost_cents / 100);
    notice = "";
    window.requestAnimationFrame(lambda { focusItineraryControl("item-title"); });
}
impl app.refresh -> None {
    token = (requestRef.current or 0) + 1;
    requestRef.current = token;
    target = selected;
    loading = True;
    try {
        fresh_trips = await list_trips();
        if target not in [trip.id for trip in fresh_trips] {
            target = fresh_trips[0].id if fresh_trips else "";
        }
        fresh_items: list[ItemView] = [];
        if target { fresh_items = await list_items(trip_id=target); }
        if requestRef.current == token {
            trips = fresh_trips; selected = target; items = fresh_items; error = "";
        }
    } except Exception as exc {
        if requestRef.current == token { error = str(exc); }
    } finally {
        if requestRef.current == token { loading = False; }
    }
}
impl app.chooseTrip(trip_id: str) -> None {
    if busy or loading { return; }
    resetReview(); selected = trip_id; items = []; day = ""; tab = "itinerary";
    railView = "auto"; placeId = "";
    trip_form = False; notice = ""; revisionNotice = ""; resetItem();
    await refresh();
}
impl app.submitTrip(e: FormEvent) -> None {
    e.preventDefault(); if busy { return; }
    if not editing_trip and not trip_review {
        trip_review = True; error = "";
        window.requestAnimationFrame(lambda { focusItineraryControl("trip-brief-summary"); });
        return;
    }
    busy = True; notice = "";
    try {
        saved = await save_trip(title=trip_title, destination=destination, start_date=start_date,
            end_date=end_date, currency=currency, budget=budget, notes=trip_notes, trip_id=editing_trip);
        if not editing_trip { tab = "itinerary"; }
        resetReview(); selected = saved.id; trip_form = False; day = ""; resetItem();
        await refresh(); notice = "Trip saved. Let the planning begin.";
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.submitItem(e: FormEvent) -> None {
    e.preventDefault(); if busy or not selected { return; } busy = True; notice = "";
    try {
        await save_item(trip_id=selected, title=item_title, category=category,
            date="" if category == "packing" else item_date, time="" if category == "packing" else item_time,
            location="" if category == "packing" else location,
            reference=reference if category in ["transport", "stay"] else "",
            notes=item_notes, cost="0" if category == "packing" else cost, item_id=editing_item);
        # Switch to the matching view so every saved item is immediately visible.
        tab = "packing" if category == "packing" else "budget" if category == "expense" else "bookings" if category in ["transport", "stay"] else "itinerary";
        day = ""; resetItem(); await refresh(); notice = "Saved to your trip.";
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.toggle(item: ItemView, payment: bool = False) -> None {
    if busy or loading { return; } busy = True; notice = "";
    try {
        await set_item_state(trip_id=selected, item_id=item.id,
            done=item.done if payment else not item.done, paid=not item.paid if payment else item.paid);
        await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.removeItem(item: ItemView) -> None {
    if busy or not window.confirm("Delete “" + item.title + "” from this trip?") { return; }
    busy = True; notice = "";
    try {
        await delete_item(trip_id=selected, item_id=item.id);
        if editing_item == item.id { resetItem(); }
        await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.removeTrip -> None {
    if busy or not window.confirm("Delete this trip and all its itinerary, booking, packing, and cost records?") { return; }
    busy = True; notice = "";
    try {
        await delete_trip(trip_id=selected); resetReview(); selected = ""; items = []; day = "";
        trip_form = False; resetItem(); await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}

impl app.createDemo -> None {
    if busy or loading { return; } busy = True; error = "";
    try {
        demo = await replan_demo(); resetReview(); selected = demo["trip_id"]; day = "";
        trip_form = False; tab = "demo"; resetItem(); await refresh();
        notice = "Demo ready. Generate backup plans, simulate a flight delay, then accept a revised itinerary.";
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}

impl app.createIntegratedDemo(scenario: str = "rain") -> None {
    if busy or loading { return; } busy = True; error = "";
    try {
        demo = await create_planning_demo(scenario=scenario); resetReview(); selected = demo["trip_id"]; day = "";
        trip_form = False; tab = "itinerary" if scenario == "map" else "backups"; resetItem(); await refresh();
        if scenario != "map" { notice = "Sample ready. Find different plans, compare the changes, then keep or accept one."; }
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}

impl app.backupApplied -> None {
    await refresh();
    notice = "Your selected backup plan is saved. No real bookings or payments were made.";
}
