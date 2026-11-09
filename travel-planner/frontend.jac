"""Jacplan's responsive trip workspace."""
import from server.main { TripView, ItemView, list_trips, save_trip, delete_trip,
    list_items, save_item, set_item_state, delete_item, replan_demo, create_planning_demo }
import from assistant.frontend { ChatSidebar, AIPlanner }
import from server.main { assistant_review, assistant_update_prices, assistant_save_preferences }

def:pub app -> JsxElement {
    has trips: list[TripView] = [], items: list[ItemView] = [], selected: str = "",
        tab: str = "planner", aiData: dict[str, any] = {}, aiReload: int = 0, aiCompose: int = 0,
        aiMode: str = "ask", aiText: str = "", day: str = "", loading: bool = True, busy: bool = False,
        error: str = "", notice: str = "", requestRef: Ref[int] = Ref(0),
        routePaused: bool = False,
        trip_form: bool = False, editing_trip: str = "", trip_title: str = "",
        departure_location: str = "", return_location: str = "",
        destination: str = "", start_date: str = "", end_date: str = "",
        currency: str = "USD", budget: str = "", trip_notes: str = "",
        editing_item: str = "", item_title: str = "", category: str = "activity",
        item_date: str = "", item_time: str = "", location: str = "",
        reference: str = "", item_notes: str = "", cost: str = "";

    def toggleRoute -> None {
        route: any = document.getElementById("journey-animation");
        if route {
            if routePaused { route.unpauseAnimations(); } else { route.pauseAnimations(); }
            routePaused = not routePaused;
        }
    }
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
        await refresh();
    }

    matching = [trip for trip in trips if trip.id == selected];
    current: TripView | None = matching[0] if matching else None;
    total = sum([item.cost_cents for item in items]);
    paid = sum([item.cost_cents for item in items if item.paid]);
    packing = ["Passport / ID", "Wallet", "Phone & Charger", "Clothing"];
    packed = len([title for title in packing if packingChecked(title)]);
    bookings = [item for item in items if item.category in ["transport", "stay"]];
    shown = [item for item in items if (
        item.cost_cents > 0 if tab == "budget" else
        item.category == "packing" if tab == "packing" else
        item.category in ["transport", "stay"] if tab == "bookings" else
        item.category in ["activity", "food", "transport", "stay"]
    ) and (not day or tab in ["packing", "budget"] or item.date == day)];

    <div className={"app-shell" + (" with-assistant" if current else "")}>
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
                <div className="section-heading"><div><p className="eyebrow">TRIP DETAILS</p><h2>{"Edit your trip" if editing_trip else "Where are you headed?"}</h2></div>
                    <button type="button" className="text-button" onClick={lambda { trip_form = False; }} disabled={busy}>Cancel</button></div>
                <form onSubmit={submitTrip}>
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
                    <p className="form-help">Departure and return locations are optional. Enter the same place for a round trip, or a different return city.</p>
                    <label htmlFor="trip-notes">Trip notes</label><textarea id="trip-notes" value={trip_notes} maxLength={5000} placeholder="Ideas, useful addresses, things to remember…" onChange={lambda (e: ChangeEvent) { trip_notes = e.target.value; }}/>
                    <button className="primary" type="submit" disabled={busy}>{"Saving…" if busy else "Save changes" if editing_trip else "Create trip ↗"}</button>
                </form>
            </section>) if trip_form else None}
            {(<section className="welcome card"><div className="welcome-art" aria-hidden="true">↗</div><p className="eyebrow">YOUR TRAVEL WORKSPACE</p>
                <h1>{"Loading your trips…" if loading else "Plan your travel with confidence."}</h1>
                <p>Keep your itinerary, reservations, packing list, and budget together. Add your first trip to get started.</p>
                <button type="button" className="primary" onClick={lambda { openTrip(); }} disabled={busy or loading}>Plan my first trip ↗</button>
            </section>) if not current else (
            <div>
                <section className="hero">

                    <div className="hero-content"><span className="status-pill">{status(current)}</span><p className="eyebrow">TRIP OVERVIEW</p>
                        <h1>{current.title}</h1><p className="destination">◎ {current.destination}</p>
                        <p className="trip-route">{"Departing from: " + (current.departure_location or "Not set") + " · Return to: " + (current.return_location or "Not set")}</p>
                        <p className="trip-dates">{prettyDate(current.start_date) + " — " + prettyDate(current.end_date)}</p>
                        <button type="button" className="hero-edit" onClick={lambda { openTrip(current); }} disabled={busy or loading}>Edit trip ↗</button>
                    </div>
                </section>
                <section className="journey-card card" aria-label="Travel route">
                    <div className="section-heading"><div><p className="eyebrow">FROM TAKEOFF TO HOME</p><h2>Your journey</h2></div>
                        <button type="button" className="text-button journey-motion-control" aria-pressed={routePaused} onClick={toggleRoute}>{"Play animation" if routePaused else "Pause animation"}</button></div>
                    <svg id="journey-animation" className="journey-animation" viewBox="0 0 900 180" aria-hidden="true" focusable="false">
                        <path className="journey-track" d="M90 130 Q270 -30 450 130 Q630 -30 810 130"/>
                        <path className="journey-track-dash" d="M90 130 Q270 -30 450 130 Q630 -30 810 130"/>
                        <circle className="journey-halo" cx="90" cy="130" r="18"/><circle className="journey-stop" cx="90" cy="130" r="7"/>
                        <circle className="journey-halo" cx="450" cy="130" r="18"/><circle className="journey-stop" cx="450" cy="130" r="7"/>
                        <circle className="journey-halo" cx="810" cy="130" r="18"/><circle className="journey-stop" cx="810" cy="130" r="7"/>
                        <g className="journey-plane">
                            <circle r="23" className="journey-plane-disc"/>
                            <path d="M16 0 L2 -4 L-8 -16 L-13 -16 L-8 -3 L-16 -3 L-20 -8 L-23 -8 L-20 0 L-23 8 L-20 8 L-16 3 L-8 3 L-13 16 L-8 16 L2 4 Z" transform="scale(.7)"/>
                            <animateMotion dur="12s" repeatCount="indefinite" rotate="auto" path="M90 130 Q270 -30 450 130 Q630 -30 810 130" keyPoints="0;0;0.5;0.5;1;1" keyTimes="0;0.08;0.42;0.58;0.92;1" calcMode="linear"/>
                        </g>
                    </svg>
                    <ol className="journey-labels">
                        <li><span>01 · Departing from</span><strong>{current.departure_location or "Add departure location"}</strong><small>{prettyDate(current.start_date)}</small></li>
                        <li><span>02 · Destination</span><strong>{current.destination}</strong><small>Explore &amp; enjoy</small></li>
                        <li><span>03 · Return to</span><strong>{current.return_location or "Add return location"}</strong><small>{prettyDate(current.end_date)}</small></li>
                    </ol>
                    {(<p className="journey-help">Complete your route in <button type="button" className="text-button" onClick={lambda { openTrip(current); }} disabled={busy or loading}>Edit trip ↗</button></p>) if not current.departure_location or not current.return_location else None}
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
                </nav>
                <nav className="tabs" aria-label="Travel sections">{[
                    <button type="button" key={value} data-active={tab == value} onClick={lambda { chooseTab(value); }} disabled={busy or loading}>
                        {"AI planner" if value == "planner" else "Itinerary" if value == "itinerary" else "Bookings" if value == "bookings" else "Packing list" if value == "packing" else "Budget"}
                    </button> for value in ["planner", "itinerary", "bookings", "packing", "budget"]
                ]}</nav>
                {(<AIPlanner data={aiData} currency={current.currency} onCompose={composeAI} onReview={reviewAI} onPrices={priceAI} onPreferences={savePreferences} busy={busy}/>) if tab == "planner" else None}
                {(<section className="budget-overview card"><div><p className="eyebrow">EVERY LITTLE THING ADDS UP</p><h2>Your trip, in numbers.</h2>
                    <p>Costs are counted once, in {current.currency}. Mark each cost paid as you go.</p></div><div className="budget-numbers">
                    <p><span>Budget</span><strong>{money(current.budget_cents, current.currency) if current.budget_cents else "Not set"}</strong></p>
                    <p><span>Planned</span><strong>{money(total, current.currency)}</strong></p><p><span>Paid</span><strong>{money(paid, current.currency)}</strong></p>
                    <p><span>Still to pay</span><strong>{money(total - paid, current.currency)}</strong></p>
                    {(<p className="over-budget">{"Over budget by " + money(total - current.budget_cents, current.currency)}</p>) if current.budget_cents and total > current.budget_cents else None}
                </div></section>) if tab == "budget" else None}
                {(<section className="card packing-card" aria-label="Packing checklist">
                    <div className="section-heading"><h2>Your packing list</h2><span className="count-pill">{str(packed) + " / 4 packed"}</span></div>
                    <p className="section-caption">Check off the essentials before you head out.</p>
                    <div className="packing-checklist">{[
                        <label key={title} className="packing-check" data-checked={packingChecked(title)}>
                            <input type="checkbox" checked={packingChecked(title)} disabled={busy or loading}
                                onChange={lambda { togglePacking(title); }}/><span>{title}</span>
                        </label> for title in packing
                    ]}</div>
                </section>) if tab == "packing" else None}
                <div className="detail-grid" hidden={tab in ["planner", "packing"]}>
                    <div>
                        <section className="card plan-card">
                            <div className="section-heading"><div><p className="eyebrow">{"SMALL THINGS, BIG DIFFERENCE" if tab == "packing" else "KEEP THE DETAILS HANDY" if tab == "bookings" else "MAKE IT ALL ADD UP" if tab == "budget" else "LEAVE A LITTLE ROOM TO WANDER"}</p>
                                <h2>{"Your packing list" if tab == "packing" else "Reservations & transport" if tab == "bookings" else "Trip costs" if tab == "budget" else "The itinerary"}</h2></div><span className="count-pill">{str(len(shown)) + (" item" if len(shown) == 1 else " items")}</span></div>
                            {(<div className="day-filter"><label htmlFor="day-filter">Show date</label><input id="day-filter" type="date" min={current.start_date} max={current.end_date} value={day} onChange={lambda (e: ChangeEvent) { day = e.target.value; }}/><button type="button" className="text-button" onClick={lambda { day = ""; }}>All dates</button></div>) if tab in ["itinerary", "bookings"] else None}
                            <p className="section-caption">{"Transport and stays also appear in your itinerary." if tab == "bookings" else "Check off the essentials before you head out." if tab == "packing" else "Update an existing item's cost instead of adding it twice." if tab == "budget" else "Dated plans come first. Undated ideas stay at the end."}</p>
                            {(<div className="empty-state"><span>{"…" if loading else icon(category)}</span><h3>{"Loading your plan…" if loading else "A little space for something good."}</h3><p>{"Your details will appear shortly." if loading else "Add an item using the form, or choose another date."}</p></div>) if loading or not shown else (
                            <div className="item-list">{[
                                <article className="travel-item" key={item.id} data-done={item.done}>
                                    <div className="item-symbol" data-kind={item.category}>{icon(item.category)}</div>
                                    <div className="item-content"><div className="item-title-line"><h3>{item.title}</h3><span className="category-tag">{item.category}</span></div>
                                        {(<p className="item-schedule">{prettyDate(item.date) + (" · " + item.time if item.time else " · Flexible time")}</p>) if item.date else (<p className="item-schedule">{"Essential" if item.category == "packing" else "Date to be decided"}</p>)}
                                        {(<p className="item-location">◎ {item.location}</p>) if item.location else None}
                                        {(<p className="reference">Booking ref: <strong>{item.reference}</strong></p>) if item.reference else None}
                                        {(<p className="item-notes">{item.notes}</p>) if item.notes else None}
                                        <div className="item-actions">
                                            {(<button type="button" className="state-button" data-checked={item.done} onClick={lambda { toggle(item); }} disabled={busy or loading}>{("✓ " if item.done else "○ ") + stateLabel(item)}</button>) if item.category != "expense" and tab != "budget" else None}
                                            {(<button type="button" className="state-button" data-checked={item.paid} onClick={lambda { toggle(item, True); }} disabled={busy or loading}>{"✓ Paid" if item.paid else "Mark paid"}</button>) if item.cost_cents else None}
                                            <button type="button" className="text-button" onClick={lambda { editItem(item); }} disabled={busy or loading}>Edit</button>
                                            <button type="button" className="text-button delete" aria-label={"Delete " + item.title} onClick={lambda { removeItem(item); }} disabled={busy or loading}>Delete</button>
                                        </div>
                                    </div>
                                    {(<strong className="item-cost">{money(item.cost_cents, current.currency)}</strong>) if item.cost_cents else None}
                                </article> for item in shown
                            ]}</div>)}
                        </section>
                        <section className="card notes-card"><p className="eyebrow">A NOTE TO YOUR FUTURE SELF</p><h2>Trip notes</h2><p>{current.notes or "Keep useful addresses, ideas, and reminders here. Add notes in Edit trip."}</p></section>
                        <button type="button" className="text-button delete delete-trip" onClick={removeTrip} disabled={busy or loading}>Delete this trip</button>
                    </div>
                    <aside className="card item-editor">
                        <span className="form-symbol">＋</span><p className="eyebrow">PUT IT ON THE PLAN</p><h2>{"Edit item" if editing_item else "One more good idea."}</h2>
                        <p className="section-caption">{"Keep the details up to date." if editing_item else "Big adventures are made of little plans."}</p>
                        <form onSubmit={submitItem}>
                            <label htmlFor="category">Category</label><select id="category" value={category} onChange={lambda (e: ChangeEvent) { category = e.target.value; }}>{[<option key={kind} value={kind}>{"Activity / sightseeing" if kind == "activity" else "Flight / transport" if kind == "transport" else "Hotel / stay" if kind == "stay" else "Food / dining" if kind == "food" else "Packing essential" if kind == "packing" else "Other cost"}</option> for kind in ["activity", "transport", "stay", "food", "packing", "expense"]]}</select>
                            <label htmlFor="item-title">Title</label><input id="item-title" value={item_title} maxLength={160} placeholder={"Passport" if category == "packing" else "e.g. Check in at the hotel"} required={True} onChange={lambda (e: ChangeEvent) { item_title = e.target.value; }}/>
                            {(<div>
                                <div className="form-pair"><div><label htmlFor="item-date">Date</label><input id="item-date" type="date" min={current.start_date} max={current.end_date} value={item_date} required={bool(item_time)} onChange={lambda (e: ChangeEvent) { item_date = e.target.value; }}/></div>
                                <div><label htmlFor="item-time">Time</label><input id="item-time" type="time" value={item_time} onChange={lambda (e: ChangeEvent) { item_time = e.target.value; }}/></div></div>
                                <label htmlFor="location">Location / address</label><input id="location" value={location} maxLength={300} placeholder="Where to go" onChange={lambda (e: ChangeEvent) { location = e.target.value; }}/>
                                {(<div><label htmlFor="reference">Booking reference</label><input id="reference" value={reference} maxLength={160} placeholder="Confirmation number" onChange={lambda (e: ChangeEvent) { reference = e.target.value; }}/></div>) if category in ["transport", "stay"] else None}
                                <label htmlFor="cost">{"Cost (" + current.currency + ")"}</label><input id="cost" type="number" min="0" max="100000000" step="0.01" value={cost} placeholder="0.00" onChange={lambda (e: ChangeEvent) { cost = e.target.value; }}/>
                            </div>) if category != "packing" else None}
                            <label htmlFor="item-notes">Notes</label><textarea id="item-notes" value={item_notes} maxLength={3000} placeholder="Anything worth remembering…" onChange={lambda (e: ChangeEvent) { item_notes = e.target.value; }}/>
                            <button type="submit" className="primary" disabled={busy or loading or not item_title.strip()}>{"Saving…" if busy else "Save changes" if editing_item else "Add to trip ↗"}</button>
                            {(<button type="button" className="text-button cancel-edit" onClick={resetItem} disabled={busy}>Cancel editing</button>) if editing_item else None}
                        </form>
                        <p className="form-help">{"Packing items are checklists without dates or costs." if category == "packing" else "Times are local to the destination. Date and cost are optional."}</p>
                    </aside>
                </div>
            </div>)}
            <footer>Jacplan <span>A place for your plans. A little room for the unexpected.</span></footer>
        </main>
        {(<ChatSidebar key={selected} trip_id={selected} destination={current.destination} onUpdate={receiveAI} reload={aiReload}
            compose={aiCompose} composeMode={aiMode} composeText={aiText} externalBusy={busy}/>) if current else None}
    </div>
}
