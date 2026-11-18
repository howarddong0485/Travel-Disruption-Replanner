"""Browser actions and ordered refreshes for Roam."""
impl app.resetItem -> None {
    editing_item = ""; item_title = ""; item_date = day; item_time = "";
    location = ""; reference = ""; item_notes = ""; cost = "";
    item_stop = ""; item_leg = ""; arrival_date = ""; arrival_time = ""; item_duration = "60";
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
    departure_location = trip.departure_location if trip else "";
    return_location = trip.return_location if trip else "";
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
    item_stop = item.journey.get("stop_id", ""); item_leg = item.journey.get("leg_id", "");
    arrival_date = item.journey.get("arrival_date", ""); arrival_time = item.journey.get("arrival_time", "");
    item_duration = str(item.duration_minutes);
    notice = "";
    window.requestAnimationFrame(lambda { focusItineraryControl("item-title"); });
}
impl app.refresh -> None {
    token = (requestRef.current or 0) + 1;
    requestRef.current = token;
    target = selected;
    loading = True;
    try {
        fresh_trips = await list_trips(workspace_key=await workspaceKey());
        if target not in [trip.id for trip in fresh_trips] {
            target = fresh_trips[0].id if not target and len(fresh_trips) > 0 else "";
        }
        fresh_items: list[ItemView] = [];
        fresh_journey: any = {};
        if target { fresh_items = await list_items(workspace_key=await workspaceKey(), trip_id=target); fresh_journey = await journey_state(workspace_key=await workspaceKey(), trip_id=target); }
        if requestRef.current == token {
            activateTrip(target); token = requestRef.current;
            trips = fresh_trips; loadedTrip = target; items = fresh_items; journeyData = fresh_journey; mapRevision += 1; error = "";
            aiReload += 1;
        }
    } except Exception as exc {
        if requestRef.current == token { error = str(exc); }
    } finally {
        if requestRef.current == token { loading = False; }
    }
}
impl app.activateTrip(trip_id: str) -> None {
    if selected == trip_id { return; }
    requestRef.current += 1;
    if selected and loadedTrip == selected {
        tripViews.current[selected] = {"items": items, "journey": journeyData, "ai": aiData, "day": day, "chat": mapChat};
    }
    views: any = tripViews.current; prior: any = views.get(trip_id, {});
    resetReview(); selected = trip_id; loadedTrip = trip_id if trip_id in views else "";
    items = prior.get("items", []); journeyData = prior.get("journey", {}); day = prior.get("day", "");
    aiData = prior.get("ai", {}); aiCompose = 0; aiText = ""; aiMode = "ask"; mapApiKey = ""; mapChat = prior.get("chat", False);
    revisionNotice = ""; notice = ""; error = ""; railView = "auto"; placeId = "";
    resetItem();
}
impl app.chooseTrip(trip_id: str) -> None {
    if busy or loading { return; }
    activateTrip(trip_id); tab = "itinerary"; trip_form = False;
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
        saved = await save_trip(workspace_key=await workspaceKey(), title=trip_title, destination=destination, start_date=start_date,
            end_date=end_date, currency=currency, budget=budget, notes=trip_notes, trip_id=editing_trip,
            departure_location=departure_location, return_location=return_location);
        if selected != saved.id { tab = "planner"; }
        resetReview(); activateTrip(saved.id); trip_form = False; day = ""; resetItem();
        await refresh(); notice = "Trip saved.";
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.submitItem(e: FormEvent) -> None {
    e.preventDefault(); if busy or not selected { return; } busy = True; notice = "";
    try {
        await save_item(workspace_key=await workspaceKey(), trip_id=selected, title=item_title, category=category,
            date="" if category == "packing" else item_date, time="" if category == "packing" else item_time,
            location="" if category == "packing" else location,
            reference=reference if category in ["transport", "stay"] else "",
            notes=item_notes, cost="0" if category == "packing" else cost, item_id=editing_item,
            journey={"stop_id": item_stop, "leg_id": item_leg, "arrival_date": arrival_date, "arrival_time": arrival_time} if journeyData.get("journey") and category not in ["packing", "expense"] else None,
            duration_minutes=int(item_duration or "60"));
        # Switch to the matching view so every saved item is immediately visible.
        tab = "packing" if category == "packing" else "budget" if category == "expense" else "bookings" if category in ["transport", "stay"] else "itinerary";
        day = ""; resetItem(); await refresh(); notice = "Saved to your trip.";
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.toggle(item: ItemView, payment: bool = False) -> None {
    if busy or loading { return; } busy = True; notice = "";
    try {
        await set_item_state(workspace_key=await workspaceKey(), trip_id=selected, item_id=item.id,
            done=item.done if payment else not item.done, paid=not item.paid if payment else item.paid);
        await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.togglePacking(title: str) -> None {
    if busy or loading or not selected { return; }
    busy = True; error = ""; notice = "";
    try {
        saved = [item for item in items if item.category == "packing" and item.title == title];
        packing_item = saved[0] if saved else await save_item(workspace_key=await workspaceKey(), trip_id=selected, title=title, category="packing", cost="0");
        await set_item_state(workspace_key=await workspaceKey(), trip_id=selected, item_id=packing_item.id, done=not packing_item.done, paid=packing_item.paid);
        await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.removeItem(item: ItemView) -> None {
    if busy or not window.confirm("Delete “" + item.title + "” from this trip?") { return; }
    busy = True; notice = "";
    try {
        await delete_item(workspace_key=await workspaceKey(), trip_id=selected, item_id=item.id);
        if editing_item == item.id { resetItem(); }
        await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}
impl app.removeTrip -> None {
    if busy or not window.confirm("Delete this trip and all its itinerary, booking, packing, and cost records?") { return; }
    busy = True; notice = "";
    try {
        deleted = selected; await delete_trip(workspace_key=await workspaceKey(), trip_id=deleted); activateTrip("");
        views: any = tripViews.current; views.pop(deleted, None);
        trip_form = False; resetItem(); await refresh();
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}

impl app.createDemo -> None {
    if busy or loading { return; } busy = True; error = "";
    try {
        demo = await replan_demo(workspace_key=await workspaceKey()); activateTrip(demo["trip_id"]);
        trip_form = False; tab = "demo"; resetItem(); await refresh();
        notice = "Demo trip created. Follow the three steps below.";
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}

impl app.createIntegratedDemo(scenario: str = "rain") -> None {
    if busy or loading { return; } busy = True; error = "";
    try {
        demo = await create_planning_demo(workspace_key=await workspaceKey(), scenario=scenario); activateTrip(demo["trip_id"]);
        if scenario == "map" { itineraryView = "map"; }
        trip_form = False; tab = "itinerary" if scenario == "map" else "backups"; resetItem(); await refresh();
        if scenario != "map" { notice = "Sample trip created. Select Find alternative plans to compare options."; }
    } except Exception as exc { error = str(exc); }
    finally { busy = False; }
}

impl app.backupApplied -> None {
    await refresh();
    notice = "Backup plan saved to your itinerary. Nothing was booked or paid.";
}
