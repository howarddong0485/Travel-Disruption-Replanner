"""Jacplan's responsive trip workspace."""
import from server.main { TripView, ItemView, list_trips, save_trip, delete_trip,
    list_items, save_item, set_item_state, delete_item, replan_demo, create_planning_demo }
import from backup.frontend { BackupPanel }
import from replan.frontend { ReplanPanel }
import from demo.frontend { GuidedDemo }
import from itinerary.actions { ItemActions, focusItineraryControl }
import from itinerary.places { ItineraryDays, ItineraryPlaces, itineraryMapLink }
import from itinerary.review { ItineraryReview }
import from itinerary.motion { animateTimeline }
import from itinerary.presentation { shiftLabel }
import from itinerary.place_popover { PlacePopover }
import from itinerary.trip_map { TripMap }
import from journey.frontend { RouteEditor, journeyLabel, legLabel }
import from server.main { journey_state }
import from assistant.frontend { ChatSidebar, AIPlanner }
import from server.main { assistant_review, assistant_update_prices, assistant_save_preferences }

def:pub app -> JsxElement {
    has trips: list[TripView] = [], items: list[ItemView] = [], selected: str = "",
        tab: str = "planner", aiData: dict[str, any] = {}, aiReload: int = 0, aiCompose: int = 0,
        aiMode: str = "ask", aiText: str = "", day: str = "", loading: bool = True, busy: bool = False,
        error: str = "", notice: str = "", requestRef: Ref[int] = Ref(0),
        trip_form: bool = False, trip_review: bool = False, editing_trip: str = "", trip_title: str = "",
        departure_location: str = "", return_location: str = "",
        destination: str = "", start_date: str = "", end_date: str = "",
        currency: str = "USD", budget: str = "", trip_notes: str = "",
        editing_item: str = "", item_title: str = "", category: str = "activity",
        item_date: str = "", item_time: str = "", location: str = "",
        reference: str = "", item_notes: str = "", cost: str = "",
        reviewRequest: any = None, itineraryPreview: any = None, reviewKey: Ref[int] = Ref(0),
        revisionNotice: str = "", revisionTimer: Ref[int] = Ref(0),
        railView: str = "auto", placeId: str = "", timelinePositions: Ref[any] = Ref({}),
        mapRevision: int = 0, itineraryView: str = "map", journeyData: any = {},
        item_stop: str = "", item_leg: str = "", arrival_date: str = "", arrival_time: str = "", item_duration: str = "60";

    browser: any = window;
    def money(cents: int, unit: str) -> str {
        value = abs(cents);
        minor = value % 100;
        return unit + " " + ("-" if cents < 0 else "") + str(value // 100) + "." + ("0" if minor < 10 else "") + str(minor);
    }
    def prettyDate(value: str) -> str {
        return new(Date, value + "T12:00:00").toLocaleDateString("en-US", {"month": "short", "day": "numeric", "year": "numeric"});
    }
    def today -> str {
        d = new(Date);
        month = d.getMonth() + 1;
        date = d.getDate();
        return str(d.getFullYear()) + "-" + ("0" if month < 10 else "") + str(month) + "-" + ("0" if date < 10 else "") + str(date);
    }
    def status(trip: TripView) -> str {
        if trip.end_date < today() { return "Past trip"; }
        if trip.start_date > today() { return "Upcoming"; }
        return "On the road";
    }
    def icon(kind: str) -> str {
        if kind == "transport" { return "↗"; }
        if kind == "stay" { return "⌂"; }
        if kind == "food" { return "♧"; }
        if kind == "packing" { return "✓"; }
        if kind == "expense" { return "$"; }
        return "◎";
    }
    def stateLabel(item: ItemView) -> str {
        if item.category == "packing" { return "Packed" if item.done else "Pack"; }
        if item.category in ["transport", "stay"] { return "Confirmed" if item.done else "Confirm"; }
        return "Done" if item.done else "Complete";
    }
    def previewDate(item: ItemView) -> str {
        return itineraryPreview["changes"][item.id]["start"]["local"][:10]
            if itineraryPreview and item.id in itineraryPreview["changes"] else item.date;
    }
    def previewTime(item: ItemView) -> str {
        return itineraryPreview["changes"][item.id]["start"]["local"][11:16]
            if itineraryPreview and item.id in itineraryPreview["changes"] else item.time;
    }
    def resetReview -> None {
        reviewKey.current += 1; reviewRequest = None; itineraryPreview = None;
    }
    def showPlace(id: str) -> None {
        placeId = id; railView = "places";
        window.requestAnimationFrame(lambda { focusItineraryControl("itinerary-places-heading"); });
    }
    def showItemEditor -> None {
        railView = "editor";
        if not editing_item and not item_date { item_date = day; }
        window.requestAnimationFrame(lambda { focusItineraryControl("item-title"); });
    }
    def openReview(item_id: str, reason: str, control: str, delay: str = "") -> None {
        if busy or loading { return; }
        if tab != "itinerary" { chooseTab("itinerary"); }
        else {
            resetReview();
            if control == "trip-actions-launch" { day = ""; }
        }
        reviewRequest = {"item": item_id, "reason": reason, "control": control, "delay": delay};
    }
    def closeReview -> None {
        control = reviewRequest["control"];
        resetReview();
        window.requestAnimationFrame(lambda {
            focusItineraryControl(control if document.getElementById(control) else "itinerary-view-" + itineraryView);
        });
    }
    def openMapReview(item_id: str, risks: any, options: any, option: str, control: str) -> None {
        if busy or loading { return; }
        resetReview(); day = "";
        reviewRequest = {"item": item_id, "reason": "", "control": control, "risks": risks,
            "options": options, "option": option};
    }
    def jumpTimeline -> None {
        window.requestAnimationFrame(lambda { focusItineraryControl("itinerary-timeline"); });
    }
    def showItineraryControls -> None {
        toolbar: any = document.getElementById("itinerary-view-toolbar");
        if toolbar { toolbar.scrollIntoView({"block": "start"}); }
    }
    def chooseItineraryView(value: str) -> None {
        if itineraryView == value { return; }
        itineraryView = value;
        try { browser.localStorage.setItem("roam.itinerary-view", value); } except Exception {}
        window.requestAnimationFrame(lambda { showItineraryControls(); });
    }
    def jumpStop(id: str) -> None {
        day = "";
        window.requestAnimationFrame(lambda {
            control: any = document.getElementById("place-details-" + id);
            if control { control.focus(); control.click(); }
            else { focusItineraryControl("itinerary-stop-" + id); }
        });
    }
    def showReviewFacts(section: str = "backups") -> None {
        chooseTab(section);
    }
    async def revisionApplied(message: str) -> None {
        token = reviewKey.current;
        await refresh();
        if token == reviewKey.current {
            closeReview(); revisionNotice = message;
            if revisionTimer.current { window.clearTimeout(revisionTimer.current); }
            revisionTimer.current = window.setTimeout(lambda { revisionNotice = ""; }, 8000);
        }
    }
    def resetItem -> None;
    def openTrip(trip: TripView | None = None) -> None;
    def editItem(item: ItemView) -> None;
    def chooseTab(value: str) -> None;
    async def refresh -> None;
    async def chooseTrip(trip_id: str) -> None;
    async def submitTrip(e: FormEvent) -> None;
    async def submitItem(e: FormEvent) -> None;
    async def toggle(item: ItemView, payment: bool = False) -> None;
    async def togglePacking(title: str) -> None;
    def packingChecked(title: str) -> bool {
        saved = [item for item in items if item.category == "packing" and item.title == title];
        return saved[0].done if saved else False;
    }
    async def removeItem(item: ItemView) -> None;
    async def removeTrip -> None;
    async def createDemo -> None;
    async def createIntegratedDemo(scenario: str = "rain") -> None;
    async def backupApplied -> None;
    def composeAI(mode: str, text: str) -> None {
        aiMode = mode; aiText = text; aiCompose += 1; tab = "planner";
    }
    def receiveAI(data: dict[str, any], generated: bool) -> None {
        aiData = data;
        if generated { tab = "planner"; }
    }
    async def routeSaved(data: any) -> None { journeyData = data; await refresh(); }
    async def reviewAI(draft_id: str, accept: bool, acknowledged: bool) -> None {
        if busy { return; } busy = True; error = ""; notice = "";
        try {
            aiData = await assistant_review(trip_id=selected, draft_id=draft_id, accept=accept, acknowledged=acknowledged);
            if accept { await refresh(); }
            aiReload += 1;
            notice = "Plan saved to your itinerary. No bookings or payments were made." if accept else "Your current itinerary is unchanged.";
        } except Exception as exc { error = str(exc); aiReload += 1; }
        finally { busy = False; }
    }
    async def priceAI(draft_id: str, prices: dict[str, any]) -> str {
        if busy { return "A review is already running. Please wait."; } busy = True; error = ""; notice = "";
        try {
            aiData = await assistant_update_prices(trip_id=selected, draft_id=draft_id, prices=prices);
            aiReload += 1;
            notice = "Estimates checked. Review the total, then select the checkbox to save your plan.";
            return "";
        } except Exception as exc { error = str(exc); return str(exc); }
        finally { busy = False; }
    }
    async def savePreferences(pet: bool, pace: str) -> None {
        if busy or not aiData.get("trip_version", 0) { return; }
        busy = True; error = ""; notice = "";
        try {
            aiData = await assistant_save_preferences(trip_id=selected, pet_friendly=pet, pace=pace, expected_version=aiData["trip_version"]);
            aiReload += 1;
            notice = "Planning preferences saved. Your next AI request will use them.";
        } except Exception as exc { error = str(exc); aiReload += 1; }
        finally { busy = False; }
    }
    async can with entry {
        document.title = "Jacplan";
        try {
            if browser.localStorage.getItem("roam.itinerary-view") == "list" { itineraryView = "list"; }
            saved_workspace: any = browser.JSON.parse(browser.localStorage.getItem("roam.workspace") or "null");
            if saved_workspace and saved_workspace["tab"] in ["planner", "journey", "itinerary", "backups", "replan", "bookings", "packing", "budget"] {
                selected = saved_workspace["trip_id"]; tab = saved_workspace["tab"];
            }
        } except Exception {}
        await refresh();
    }
    can with [selected, tab, loading] entry {
        if selected and not loading {
            try { browser.localStorage.setItem("roam.workspace", browser.JSON.stringify({"trip_id": selected, "tab": tab})); }
            except Exception {}
        }
    }
    can with [itineraryPreview, items, selected, day, tab] entry {
        timelinePositions.current = animateTimeline(timelinePositions.current, bool(itineraryPreview and itineraryPreview["choice"]));
    }
    can with [reviewRequest] entry {
        if reviewRequest and window.innerWidth > 1000 { showItineraryControls(); }
    }

    mapVisible = tab == "itinerary" and itineraryView == "map";
    matching = [trip for trip in trips if trip.id == selected];
    current: TripView | None = matching[0] if matching else None;
    total = sum([item.cost_cents for item in items]);
    paid = sum([item.cost_cents for item in items if item.paid]);
    packing = ["Passport / ID", "Wallet", "Phone & Charger", "Clothing"];
    packed = len([title for title in packing if packingChecked(title)]);
    bookings = [item for item in items if item.category in ["transport", "stay"]];
    itineraryItems = [item for item in items if item.category in ["activity", "food", "transport", "stay"]];
    shown = [item for item in items if (
        item.cost_cents > 0 if tab == "budget" else
        item.category == "packing" if tab == "packing" else
        item.category in ["transport", "stay"] if tab == "bookings" else
        item.category in ["activity", "food", "transport", "stay"]
    ) and (not day or tab in ["packing", "budget"] or previewDate(item) == day)];
    if tab == "itinerary" {
        shown = sorted(shown, key=lambda (item: ItemView) -> str {
            return (previewDate(item) or "9999") + "T" + (previewTime(item) or "99:99");
        });
    }
    places = [item for item in shown if item.location];
    selectedPlaces = [item for item in places if item.id == placeId];
    currentPlace = selectedPlaces[0] if selectedPlaces else places[0] if places else None;
    placesOpen = tab == "itinerary" and (railView == "places" or (railView == "auto" and bool(places)));

    <div className={"app-shell" + (" with-assistant" if current else "")} data-reviewing={bool(reviewRequest)}>
        <aside className="sidebar">
            <a className="brand" href="#"><span className="brand-icon">↗</span>Jacplan</a>
            <p className="brand-caption">Travel planning workspace.</p>
            <div className="sidebar-heading"><span>YOUR TRIPS</span><span>{str(len(trips))}</span></div>
            <div className="trip-list">{[
                <button type="button" key={trip.id} className="trip-card" data-active={trip.id == selected}
                    disabled={busy or loading} onClick={lambda { chooseTrip(trip.id); }}>
                    <span className="trip-card-icon">◎</span><span><strong>{trip.title}</strong>
                    <small>{trip.destination}</small><small>{prettyDate(trip.start_date)}</small></span>
                    <span className="trip-card-arrow">›</span>
                </button> for trip in trips
            ]}</div>
            <button type="button" className="new-trip" onClick={lambda { openTrip(); }} disabled={busy or loading}>＋ Plan a new trip</button>
            <button type="button" className="text-button demo-trip" onClick={lambda { createIntegratedDemo("map"); }} disabled={busy or loading}>Explore a sample trip map ↗</button>
            <button type="button" className="text-button demo-trip" onClick={createDemo} disabled={busy or loading}>Start backup & replan demo ↗</button>
            <button type="button" className="text-button demo-trip" onClick={lambda { createIntegratedDemo("rain"); }} disabled={busy or loading}>Try connected backup plans ↗</button>
            <button type="button" className="text-button demo-trip" onClick={lambda { chooseTab("planner"); }} disabled={busy or loading or not selected}>✦ Open AI planner</button>
            <div className="sidebar-bottom"><p>Organized travel.</p><small>Your plans, all in one place.</small></div>
        </aside>
        <main className="workspace">
            <header className="topbar"><span>TRAVEL MANAGEMENT WORKSPACE</span><div className="topbar-actions">
                <button type="button" className="text-button" onClick={refresh} disabled={busy or loading}>{"Refreshing…" if loading else "↻ Refresh"}</button>
                <span className="avatar" title="Personal travel workspace">ZL</span></div></header>
            {(<div className="alert error" role="alert">{error}<button type="button" aria-label="Dismiss error" onClick={lambda { error = ""; }}>×</button></div>) if error else None}
            {(<div className="alert success" role="status">{notice}</div>) if notice else None}
            {(<section className="trip-editor card">
                <div className="section-heading"><div><p className="eyebrow">TRIP DETAILS</p><h2>{"Edit your trip" if editing_trip else "Review your trip brief" if trip_review else "Where are you headed?"}</h2></div>
                    <button type="button" className="text-button" onClick={lambda { trip_form = False; }} disabled={busy}>Cancel</button></div>
                <form onSubmit={submitTrip}>
                    <div hidden={trip_review}>
                    <div className="trip-fields">
                        <div><label htmlFor="trip-name">Trip name</label><input id="trip-name" value={trip_title} maxLength={160} placeholder="A week in Kyoto" required={True} onChange={lambda (e: ChangeEvent) { trip_title = e.target.value; }}/></div>
                        <div><label htmlFor="destination">Destination</label><input id="destination" value={destination} maxLength={160} placeholder="Kyoto, Japan" required={True} onChange={lambda (e: ChangeEvent) { destination = e.target.value; }}/></div>
                        <div><label htmlFor="departure-location">Departing from</label><input id="departure-location" value={departure_location} maxLength={160} placeholder="Detroit, MI or DTW" onChange={lambda (e: ChangeEvent) { departure_location = e.target.value; }}/></div>
                        <div><label htmlFor="return-location">Return to</label><input id="return-location" value={return_location} maxLength={160} placeholder="City or airport after the trip" onChange={lambda (e: ChangeEvent) { return_location = e.target.value; }}/></div>
                        <div><label htmlFor="departure">Departure date</label><input id="departure" type="date" value={start_date} required={True} onChange={lambda (e: ChangeEvent) { start_date = e.target.value; }}/></div>
                        <div><label htmlFor="return">Return date</label><input id="return" type="date" value={end_date} min={start_date} required={True} onChange={lambda (e: ChangeEvent) { end_date = e.target.value; }}/></div>
                        <div><label htmlFor="currency">Currency</label><select id="currency" value={currency} onChange={lambda (e: ChangeEvent) { currency = e.target.value; }}>{[<option key={unit} value={unit}>{unit}</option> for unit in ["USD", "EUR", "GBP", "CAD", "JPY", "CNY", "AUD", "CHF", "KRW", "INR"]]}</select></div>
                        <div><label htmlFor="budget">Trip budget</label><input id="budget" type="number" min="0" max="100000000" step="0.01" value={budget} placeholder="0.00" onChange={lambda (e: ChangeEvent) { budget = e.target.value; }}/></div>
                    </div>
                    <label htmlFor="trip-notes">{"Trip notes" if editing_trip else "Short trip brief"}</label>
                    <textarea id="trip-notes" value={trip_notes} maxLength={5000} placeholder="What would make this a good trip?" onChange={lambda (e: ChangeEvent) { trip_notes = e.target.value; }}/>
                    </div>
                    {(<div className="trip-brief-preview">
                        <h3 id="trip-brief-summary" tabIndex={-1}>{trip_title}</h3>
                        <p>{destination + " · " + prettyDate(start_date) + " – " + prettyDate(end_date)}</p>
                        <p>{"Budget " + currency + " " + budget if budget else "Budget to be decided"}</p>
                        <p className="section-caption">Set your travel party and requirements in Backup plans after creating the trip.</p>
                        {(<p className="brief-note">{trip_notes}</p>) if trip_notes else None}
                        <button type="button" className="text-button" disabled={busy} onClick={lambda {
                            trip_review = False; window.requestAnimationFrame(lambda { focusItineraryControl("trip-name"); });
                        }}>Edit brief</button>
                    </div>) if trip_review else None}
                    <button className="primary" type="submit" disabled={busy}>{"Saving…" if busy else "Save changes" if editing_trip else "Confirm and create trip" if trip_review else "Review trip brief ↗"}</button>
                </form>
            </section>) if trip_form else None}
            {(<section className="welcome card"><div className="welcome-art" aria-hidden="true">↗</div><p className="eyebrow">YOUR TRAVEL WORKSPACE</p>
                <h1>{"Loading your trips…" if loading else "Plan your travel with confidence."}</h1>
                <p>Keep your itinerary, reservations, packing list, and budget together. Add your first trip to get started.</p>
                <button type="button" className="primary" onClick={lambda { openTrip(); }} disabled={busy or loading}>Plan my first trip ↗</button>
            </section>) if not current else (
            <div>
                {(<section className="map-trip-header">
                    <div><p className="map-trip-dates">{(journeyLabel(journeyData.get("journey")) or current.destination) + " · " + prettyDate(current.start_date) + (" – " + prettyDate(current.end_date) if current.end_date != current.start_date else "")}</p>
                        <h1>{current.title}</h1></div>
                    <button type="button" className="itinerary-chip" onClick={lambda { openTrip(current); }} disabled={busy or loading}>Edit trip</button>
                </section>) if mapVisible else (<div>
                <section className="hero" data-itinerary={tab == "itinerary"}>

                    <div className="hero-content"><span className="status-pill">{status(current)}</span><p className="eyebrow">TRIP OVERVIEW</p>
                        <h1>{current.title}</h1><p className="destination">◎ {current.destination}</p>
                        <p className="trip-route">{"Departing from: " + (current.departure_location or "Not set") + " · Return to: " + (current.return_location or "Not set")}</p>
                        <p className="trip-dates">{prettyDate(current.start_date) + " — " + prettyDate(current.end_date)}</p>
                        <button type="button" className="hero-edit" onClick={lambda { openTrip(current); }} disabled={busy or loading}>Edit trip ↗</button>
                    </div>
                </section>
                <section className="stats" aria-label="Trip summary">
                    <div><span className="stat-icon">↗</span><p><strong>{str(len(bookings))}</strong><small>reservations</small></p></div>
                    <div><span className="stat-icon">✓</span><p><strong>{str(packed) + " / " + str(len(packing))}</strong><small>essentials packed</small></p></div>
                    <div><span className="stat-icon">$</span><p><strong>{money(total, current.currency)}</strong><small>planned cost</small></p></div>
                    <div><span className="stat-icon">◎</span><p><strong>{money(current.budget_cents - total, current.currency) if current.budget_cents else "No budget yet"}</strong><small>{"budget remaining" if current.budget_cents else "set one in Edit trip"}</small></p></div>
                </section>
                <nav className="trip-workflow ai-workflow" aria-label="Planning workflow">
                    <button type="button" data-active={tab == "planner"} disabled={busy or loading} onClick={lambda { chooseTab("planner"); }}>
                        <span className="workflow-number">✦</span><span><strong>Plan, prepare & adapt</strong><small>One assistant for every change</small></span>
                    </button>
                    <button type="button" data-active={tab == "itinerary"} disabled={busy or loading} onClick={lambda { chooseTab("itinerary"); }}>
                        <span className="workflow-number">◎</span><span><strong>Your saved itinerary</strong><small>Review and manage your arrangements</small></span>
                    </button>
                </nav></div>)}
                <datalist id="journey-zones">{[<option key={zone} value={zone}/> for zone in ["America/Detroit", "America/New_York", "America/Chicago", "America/Los_Angeles", "Europe/London", "Europe/Paris", "Asia/Tokyo", "Asia/Shanghai", "Asia/Seoul", "Asia/Singapore", "Australia/Sydney", "Pacific/Honolulu"]]}</datalist>
                <nav className="tabs" aria-label="Travel sections">{[
                    <button type="button" key={value} data-active={tab == value} onClick={lambda { chooseTab(value); }} disabled={busy or loading}>
                        {"AI planner" if value == "planner" else "Itinerary" if value == "itinerary" else "Route" if value == "journey" else "Backup plans" if value == "backups" else "Replan" if value == "replan" else "Bookings" if value == "bookings" else "Packing list" if value == "packing" else "Budget"}
                    </button> for value in ["planner", "journey", "itinerary", "backups", "replan", "bookings", "packing", "budget"]
                ]}</nav>
                {(<RouteEditor key={selected} trip={current} data={journeyData} onSaved={routeSaved} onPlan={composeAI} disabled={busy or loading}/>) if tab in ["planner", "journey"] else None}
                <div id="itinerary-view-toolbar" className={"itinerary-view-toolbar" if tab == "itinerary" else ""}>
                    {(<div className="itinerary-view-controls" role="group" aria-label="Itinerary view">
                        <button type="button" id="itinerary-view-map" aria-pressed={itineraryView == "map"}
                            onClick={lambda { chooseItineraryView("map"); }}>Map</button>
                        <button type="button" id="itinerary-view-list" aria-pressed={itineraryView == "list"}
                            onClick={lambda { chooseItineraryView("list"); }}>List</button>
                    </div>) if tab == "itinerary" else None}
                    {(<button id="trip-actions-launch" type="button" className={"itinerary-chip" if mapVisible else "trip-actions-launch"}
                        disabled={busy or loading} onClick={lambda { openReview("", "", "trip-actions-launch"); }}>
                        <span aria-hidden="true">↗</span> Review a change
                    </button>) if not reviewRequest and tab != "journey" else None}
                </div>
                {(<section className="backup-workspace" aria-label="Backup plans">
                    <div className="card workflow-intro"><p className="eyebrow">PREPARE ALTERNATIVES</p><h2>Backup plans</h2>
                        <p>Prepare alternatives for detected risks or a change you report. Compare the complete plans and explicitly accept a revision.</p>
                        <div className="planning-demo-actions"><button type="button" className="secondary" disabled={busy} onClick={lambda { createIntegratedDemo("rain"); }}>Try weather sample</button>
                            <button type="button" className="secondary" disabled={busy} onClick={lambda { createIntegratedDemo("arrival_delay"); }}>Try arrival-delay sample</button></div>
                        <button type="button" className="text-button" onClick={lambda { chooseTab("replan"); }}>Replan after a disruption →</button>
                    </div>
                    <BackupPanel key={selected} trip={current} items={items} onApplied={backupApplied}/>
                </section>) if not loading and tab == "backups" else None}
                {(<AIPlanner data={aiData} currency={current.currency} onCompose={composeAI} onReview={reviewAI} onPrices={priceAI} onPreferences={savePreferences} busy={busy}/>) if tab == "planner" else None}
                {(<section className="budget-overview card"><div><p className="eyebrow">EVERY LITTLE THING ADDS UP</p><h2>Your trip, in numbers.</h2>
                    <p>Costs are counted once, in {current.currency}. Mark each cost paid as you go.</p></div><div className="budget-numbers">
                    <p><span>Budget</span><strong>{money(current.budget_cents, current.currency) if current.budget_cents else "Not set"}</strong></p>
                    <p><span>Planned</span><strong>{money(total, current.currency)}</strong></p><p><span>Paid</span><strong>{money(paid, current.currency)}</strong></p>
                    <p><span>Still to pay</span><strong>{money(total - paid, current.currency)}</strong></p>
                    {(<p className="over-budget">{"Over budget by " + money(total - current.budget_cents, current.currency)}</p>) if current.budget_cents and total > current.budget_cents else None}
                </div></section>) if tab == "budget" else None}
                {(<ReplanPanel key={selected} trip_id={selected} currency={current.currency} onApplied={refresh}/>) if tab == "replan" else None}
                {(<GuidedDemo key={selected} trip={current} items={items} onRefresh={refresh}
                    onViewItinerary={lambda { chooseTab("itinerary"); }}/>) if tab == "demo" else None}
                <div className="detail-grid" data-view={itineraryView if tab == "itinerary" else ""}
                    data-reviewing={bool(reviewRequest)} hidden={tab in ["planner", "journey", "backups", "replan", "demo"]}>
                    {(<div className="map-workspace">
                        <TripMap key={selected} trip={current} items={itineraryItems} revision={mapRevision}
                            preview={itineraryPreview} disabled={busy or loading}
                            onReview={openReview} onPlanB={openMapReview} onStop={jumpStop} onTimeline={jumpTimeline}
                            onSample={lambda { createIntegratedDemo("map"); }}/>
                    </div>) if mapVisible else None}
                    <div className="itinerary-main">
                        <section className="card plan-card">
                            <div className="section-heading"><div><p className="eyebrow">{"SMALL THINGS, BIG DIFFERENCE" if tab == "packing" else "KEEP THE DETAILS HANDY" if tab == "bookings" else "MAKE IT ALL ADD UP" if tab == "budget" else "LEAVE A LITTLE ROOM TO WANDER"}</p>
                                <h2 id="itinerary-timeline" tabIndex={-1}>{"Your packing list" if tab == "packing" else "Reservations & transport" if tab == "bookings" else "Trip costs" if tab == "budget" else "The itinerary"}</h2></div><span className="count-pill">{str(len(shown)) + (" item" if len(shown) == 1 else " items")}</span></div>
                            {(<ItineraryDays items={itineraryItems} day={day} start_date={current.start_date} end_date={current.end_date}
                                onChange={lambda (value: str) { day = value; }}/>) if tab == "itinerary" else None}
                            {(<div className="day-filter"><label htmlFor="day-filter">Show date</label><input id="day-filter" type="date" min={current.start_date} max={current.end_date} value={day} onChange={lambda (e: ChangeEvent) { day = e.target.value; }}/><button type="button" className="text-button" onClick={lambda { day = ""; }}>All dates</button></div>) if tab == "bookings" else None}
                            <p className="section-caption">{"Transport and stays also appear in your itinerary." if tab == "bookings" else "Check off the essentials before you head out." if tab == "packing" else "Update an existing item's cost instead of adding it twice." if tab == "budget" else "Explore a place or use Actions to review a change."}</p>
                            {(<p className="itinerary-preview-banner" role="status">{"Preview · Your saved itinerary is unchanged" if itineraryPreview["choice"] else "Impact preview · Stops to check are highlighted"}</p>) if itineraryPreview and len(itineraryPreview["affected"]) > 0 else None}
                            {(<div className="empty-state"><span>{"…" if loading else icon(category)}</span><h3>{"Loading your plan…" if loading else "A little space for something good."}</h3><p>{"Your details will appear shortly." if loading else "Add an item using the form, or choose another date."}</p></div>) if loading or not shown else (
                            <div className="item-list">{[
                                <div className="itinerary-row" key={item.id}>
                                {(<h3 className="itinerary-day">{prettyDate(previewDate(item)) if previewDate(item) else "Flexible dates"}</h3>) if tab == "itinerary" and (index == 0 or previewDate(shown[index - 1]) != previewDate(item)) else None}
                                <article className="travel-item" id={"itinerary-stop-" + item.id} tabIndex={-1} data-done={item.done}
                                    data-place-selected={bool(placesOpen and not reviewRequest and currentPlace and currentPlace.id == item.id)}
                                    data-affected={bool(itineraryPreview and item.id in itineraryPreview["affected"])}
                                    data-proposed={bool(itineraryPreview and item.id in itineraryPreview["changes"])}
                                    style={{"animationDelay": str(min(itineraryPreview["affected"].get(item.id, 0), 8) * 45) + "ms"} if itineraryPreview else {}}>
                                    <div className="item-symbol" data-kind={item.category}>{icon(item.category)}</div>
                                    <div className="item-content"><div className="item-title-line"><h3>{item.title}</h3><span className="category-tag">{item.category}</span>
                                        {(<span className="category-tag itinerary-fixed">Fixed or completed</span>) if itineraryPreview and item.id in itineraryPreview["protected"] else None}
                                        {(<span className="category-tag itinerary-affected">Check impact</span>) if itineraryPreview and item.id in itineraryPreview["affected"] else None}</div>
                                        {(<p className="item-schedule">{prettyDate(item.date) + (" · " + item.time if item.time else " · Flexible time")}</p>) if item.date else (<p className="item-schedule">{"Essential" if item.category == "packing" else "Date to be decided"}</p>)}
                                        {(<p className="item-schedule">{item.journey["zone"] + " → " + item.journey["arrival_date"] + " " + item.journey["arrival_time"] + " " + item.journey["end_zone"]}</p>) if item.journey else None}
                                        {(<p className="item-location">◎ {item.location if not item.location.startswith("fixture:") else "Sample location"}
                                            {(<a className="itinerary-map" href={itineraryMapLink(item.location, current.destination)}
                                                target="_blank" rel="noopener noreferrer" aria-label={"Map for " + item.title + " (opens in a new tab)"}>Map ↗</a>) if tab == "itinerary" and not item.location.startswith("fixture:") else None}
                                        </p>) if item.location else None}
                                        {(<p className="itinerary-proposed" key={itineraryPreview["choice"]}>
                                            <strong>Proposed</strong> {itineraryPreview["changes"][item.id]["start"]["local"].replace("T", " ")}
                                            {(<span className="time-shift">{shiftLabel(itineraryPreview["time_changes"][item.id])}</span>) if item.id in itineraryPreview.get("time_changes", {}) else None}
                                            {(" · " + itineraryPreview["changes"][item.id]["title"]) if itineraryPreview["changes"][item.id]["title"] != item.title else ""}
                                        </p>) if itineraryPreview and item.id in itineraryPreview["changes"] else None}
                                        {(<p className="reference">Booking ref: <strong>{item.reference}</strong></p>) if item.reference else None}
                                        {(<p className="item-notes">{item.notes}</p>) if item.notes else None}
                                        <div className="item-actions">
                                            {(<ItemActions trip_id={current.id} item_id={item.id} title={item.title} category={item.category}
                                                disabled={busy or loading} onReview={openReview}/>) if tab == "itinerary" else None}
                                            {(<PlacePopover trip_id={current.id} item={item} destination={current.destination} disabled={busy or loading}
                                                onReview={openReview} onSelect={showPlace} onSaved={lambda { mapRevision += 1; }}/>) if tab == "itinerary" and item.location and not reviewRequest else None}
                                            {(<button type="button" className="state-button" data-checked={item.done} onClick={lambda { toggle(item); }} disabled={busy or loading}>{("✓ " if item.done else "○ ") + stateLabel(item)}</button>) if item.category != "expense" and tab != "budget" else None}
                                            {(<button type="button" className="state-button" data-checked={item.paid} onClick={lambda { toggle(item, True); }} disabled={busy or loading}>{"✓ Paid" if item.paid else "Mark paid"}</button>) if item.cost_cents else None}
                                            <button type="button" className="text-button" onClick={lambda { editItem(item); }} disabled={busy or loading}>Edit</button>
                                            <button type="button" className="text-button delete" aria-label={"Delete " + item.title} onClick={lambda { removeItem(item); }} disabled={busy or loading}>Delete</button>
                                        </div>
                                    </div>
                                    {(<strong className="item-cost">{money(item.cost_cents, current.currency)}</strong>) if item.cost_cents else None}
                                </article></div> for (index, item) in enumerate(shown)
                            ]}</div>)}
                        </section>
                        <section className="card notes-card"><p className="eyebrow">A NOTE TO YOUR FUTURE SELF</p><h2>Trip notes</h2><p>{current.notes or "Keep useful addresses, ideas, and reminders here. Add notes in Edit trip."}</p></section>
                        <button type="button" className="text-button delete delete-trip" onClick={removeTrip} disabled={busy or loading}>Delete this trip</button>
                    </div>
                    {(<ItineraryReview key={current.id + ":" + str(reviewKey.current)} trip_id={current.id} currency={current.currency}
                        items={items} request={reviewRequest} onPreview={lambda (preview: any) { itineraryPreview = preview; }}
                        onClose={closeReview} onApplied={revisionApplied} onFacts={showReviewFacts}
                        onMapUpdate={lambda { mapRevision += 1; }}/>) if reviewRequest and tab == "itinerary" else None}
                    <div className="itinerary-side" hidden={bool(reviewRequest)}>
                    {(<div className="itinerary-side-tabs" role="group" aria-label="Itinerary tools">
                        <button type="button" className="itinerary-chip" aria-pressed={placesOpen}
                            onClick={lambda { railView = "places"; }}>◎ Places</button>
                        <button type="button" className="itinerary-chip" aria-pressed={not placesOpen} disabled={busy or loading}
                            onClick={showItemEditor}>{"Edit item" if editing_item else "＋ Add item"}</button>
                    </div>) if tab == "itinerary" else None}
                    {(<ItineraryPlaces places={places} place={currentPlace} destination={current.destination} day={day}
                        disabled={busy or loading} onSelect={lambda (id: str) { placeId = id; }} onReview={openReview}/>) if placesOpen else None}
                    <aside className="card item-editor" hidden={placesOpen}>
                        <span className="form-symbol">＋</span><p className="eyebrow">PUT IT ON THE PLAN</p><h2>{"Edit item" if editing_item else "One more good idea."}</h2>
                        <p className="section-caption">{"Keep the details up to date." if editing_item else "Big adventures are made of little plans."}</p>
                        <form onSubmit={submitItem}>
                            <label htmlFor="category">Category</label><select id="category" value={category} onChange={lambda (e: ChangeEvent) { category = e.target.value; }}>{[<option key={kind} value={kind}>{"Activity / sightseeing" if kind == "activity" else "Flight / transport" if kind == "transport" else "Hotel / stay" if kind == "stay" else "Food / dining" if kind == "food" else "Packing essential" if kind == "packing" else "Other cost"}</option> for kind in ["activity", "transport", "stay", "food", "packing", "expense"]]}</select>
                            <label htmlFor="item-title">Title</label><input id="item-title" value={item_title} maxLength={160} placeholder={"Passport" if category == "packing" else "e.g. Check in at the hotel"} required={True} onChange={lambda (e: ChangeEvent) { item_title = e.target.value; }}/>
                            {(<div>
                                <div className="form-pair"><div><label htmlFor="item-date">Date</label><input id="item-date" type="date" min={current.start_date} max={current.end_date} value={item_date} required={bool(item_time)} onChange={lambda (e: ChangeEvent) { item_date = e.target.value; }}/></div>
                                <div><label htmlFor="item-time">Time</label><input id="item-time" type="time" value={item_time} onChange={lambda (e: ChangeEvent) { item_time = e.target.value; }}/></div></div>
                                {(<fieldset className="journey-item-fields"><legend>City / intercity transport</legend>
                                    <label htmlFor="item-city-stop">City stop</label><select id="item-city-stop" value={item_stop} onChange={lambda (e: ChangeEvent) { item_stop = e.target.value; item_leg = ""; }}><option value="">Choose a city, or a transport leg below</option>{[<option key={stop["id"]} value={stop["id"]}>{stop["city"] + " · " + stop["zone"]}</option> for stop in journeyData["journey"]["stops"]]}</select>
                                    {(<div><label htmlFor="item-journey-leg">Intercity leg</label><select id="item-journey-leg" value={item_leg} onChange={lambda (e: ChangeEvent) { item_leg = e.target.value; item_stop = ""; }}><option value="">Local transport in selected city</option>{[<option key={leg["id"]} value={leg["id"]}>{legLabel(journeyData["journey"], leg) + " · " + leg["mode"]}</option> for leg in journeyData["journey"]["legs"]]}</select></div>) if category == "transport" else None}
                                    <label htmlFor="item-duration">Elapsed duration (minutes)</label><input id="item-duration" type="number" min="1" max="1440" value={item_duration} required={True} onChange={lambda (e: ChangeEvent) { item_duration = e.target.value; }}/>
                                    {(<div className="form-pair"><label>Arrival date<input aria-label="Transport arrival date" type="date" value={arrival_date} required={True} onChange={lambda (e: ChangeEvent) { arrival_date = e.target.value; }}/></label><label>Arrival time<input aria-label="Transport arrival time" type="time" value={arrival_time} required={True} onChange={lambda (e: ChangeEvent) { arrival_time = e.target.value; }}/></label></div>) if item_leg else None}
                                    <p className="form-help">Departure uses the origin city's local time; arrival uses the destination city's local time.</p>
                                </fieldset>) if journeyData.get("journey") else None}
                                <label htmlFor="location">Location / address</label><input id="location" value={location} maxLength={300} placeholder="Where to go" onChange={lambda (e: ChangeEvent) { location = e.target.value; }}/>
                                {(<div><label htmlFor="reference">Booking reference</label><input id="reference" value={reference} maxLength={160} placeholder="Confirmation number" onChange={lambda (e: ChangeEvent) { reference = e.target.value; }}/></div>) if category in ["transport", "stay"] else None}
                                <label htmlFor="cost">{"Cost (" + current.currency + ")"}</label><input id="cost" type="number" min="0" max="100000000" step="0.01" value={cost} placeholder="0.00" onChange={lambda (e: ChangeEvent) { cost = e.target.value; }}/>
                            </div>) if category != "packing" else None}
                            <label htmlFor="item-notes">Notes</label><textarea id="item-notes" value={item_notes} maxLength={3000} placeholder="Anything worth remembering…" onChange={lambda (e: ChangeEvent) { item_notes = e.target.value; }}/>
                            <button type="submit" className="primary" disabled={busy or loading or not item_title.strip()}>{"Saving…" if busy else "Save changes" if editing_item else "Add to trip ↗"}</button>
                            {(<button type="button" className="text-button cancel-edit" onClick={resetItem} disabled={busy}>Cancel editing</button>) if editing_item else None}
                        </form>
                        <p className="form-help">{"Packing items are checklists without dates or costs." if category == "packing" else "Use local times for the selected city or transport endpoints." if journeyData.get("journey") else "Times are local to the destination. Date and cost are optional."}</p>
                    </aside>
                    </div>
                </div>
            </div>)}
            <footer>Jacplan <span>A place for your plans. A little room for the unexpected.</span></footer>
        </main>
        {(<div className="revision-toast" role="status">{revisionNotice}
            <button type="button" className="itinerary-chip" aria-label="Dismiss saved revision message" onClick={lambda { revisionNotice = ""; }}>×</button>
        </div>) if revisionNotice else None}
        {(<ChatSidebar key={selected} trip_id={selected} destination={current.destination} onUpdate={receiveAI} reload={aiReload}
            compose={aiCompose} composeMode={aiMode} composeText={aiText} externalBusy={busy}/>) if current else None}
    </div>
}
