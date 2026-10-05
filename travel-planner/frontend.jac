"""Roam's responsive trip workspace."""
import from server.main { TripView, ItemView, list_trips, save_trip, delete_trip,
    list_items, save_item, set_item_state, delete_item }

def:pub app -> JsxElement {
    has trips: list[TripView] = [], items: list[ItemView] = [], selected: str = "",
        tab: str = "itinerary", day: str = "", loading: bool = True, busy: bool = False,
        error: str = "", notice: str = "", requestRef: Ref[int] = Ref(0),
        trip_form: bool = False, editing_trip: str = "", trip_title: str = "",
        destination: str = "", start_date: str = "", end_date: str = "",
        currency: str = "USD", budget: str = "", trip_notes: str = "",
        editing_item: str = "", item_title: str = "", category: str = "activity",
        item_date: str = "", item_time: str = "", location: str = "",
        reference: str = "", item_notes: str = "", cost: str = "";

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
    async def removeItem(item: ItemView) -> None;
    async def removeTrip -> None;
    async can with entry {
        document.title = "Roam — Travel Planner";
        await refresh();
    }

    matching = [trip for trip in trips if trip.id == selected];
    current: TripView | None = matching[0] if matching else None;
    total = sum([item.cost_cents for item in items]);
    paid = sum([item.cost_cents for item in items if item.paid]);
    packing = [item for item in items if item.category == "packing"];
    packed = len([item for item in packing if item.done]);
    bookings = [item for item in items if item.category in ["transport", "stay"]];
    shown = [item for item in items if (
        item.cost_cents > 0 if tab == "budget" else
        item.category == "packing" if tab == "packing" else
        item.category in ["transport", "stay"] if tab == "bookings" else
        item.category in ["activity", "food", "transport", "stay"]
    ) and (not day or tab in ["packing", "budget"] or item.date == day)];

    <div className="app-shell">
        <aside className="sidebar">
            <a className="brand" href="#"><span className="brand-icon">↗</span>roam<span className="brand-dot">.</span></a>
            <p className="brand-caption">Good trips start here.</p>
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
            <div className="sidebar-bottom"><span className="little-sun">✳</span><p>Less scattered.<br/>More out there.</p><small>Your plans, all in one place.</small></div>
        </aside>
        <main className="workspace">
            <header className="topbar"><span>YOUR PERSONAL TRAVEL PLANNER</span><div className="topbar-actions">
                <button type="button" className="text-button" onClick={refresh} disabled={busy or loading}>{"Refreshing…" if loading else "↻ Refresh"}</button>
                <span className="avatar" title="Personal travel workspace">ZL</span></div></header>
            {(<div className="alert error" role="alert">{error}<button type="button" aria-label="Dismiss error" onClick={lambda { error = ""; }}>×</button></div>) if error else None}
            {(<div className="alert success" role="status">{notice}</div>) if notice else None}
            {(<section className="trip-editor card">
                <div className="section-heading"><div><p className="eyebrow">THE NEXT ADVENTURE</p><h2>{"Edit your trip" if editing_trip else "Where are you headed?"}</h2></div>
                    <button type="button" className="text-button" onClick={lambda { trip_form = False; }} disabled={busy}>Cancel</button></div>
                <form onSubmit={submitTrip}>
                    <div className="trip-fields">
                        <div><label htmlFor="trip-name">Trip name</label><input id="trip-name" value={trip_title} maxLength={160} placeholder="A week in Kyoto" required={True} onChange={lambda (e: ChangeEvent) { trip_title = e.target.value; }}/></div>
                        <div><label htmlFor="destination">Destination</label><input id="destination" value={destination} maxLength={160} placeholder="Kyoto, Japan" required={True} onChange={lambda (e: ChangeEvent) { destination = e.target.value; }}/></div>
                        <div><label htmlFor="departure">Departure</label><input id="departure" type="date" value={start_date} required={True} onChange={lambda (e: ChangeEvent) { start_date = e.target.value; }}/></div>
                        <div><label htmlFor="return">Return</label><input id="return" type="date" value={end_date} min={start_date} required={True} onChange={lambda (e: ChangeEvent) { end_date = e.target.value; }}/></div>
                        <div><label htmlFor="currency">Currency</label><select id="currency" value={currency} onChange={lambda (e: ChangeEvent) { currency = e.target.value; }}>{[<option key={unit} value={unit}>{unit}</option> for unit in ["USD", "EUR", "GBP", "CAD", "JPY", "CNY", "AUD", "CHF", "KRW", "INR"]]}</select></div>
                        <div><label htmlFor="budget">Trip budget</label><input id="budget" type="number" min="0" max="100000000" step="0.01" value={budget} placeholder="0.00" onChange={lambda (e: ChangeEvent) { budget = e.target.value; }}/></div>
                    </div>
                    <label htmlFor="trip-notes">Trip notes</label><textarea id="trip-notes" value={trip_notes} maxLength={5000} placeholder="Ideas, useful addresses, things to remember…" onChange={lambda (e: ChangeEvent) { trip_notes = e.target.value; }}/>
                    <button className="primary" type="submit" disabled={busy}>{"Saving…" if busy else "Save changes" if editing_trip else "Create trip ↗"}</button>
                </form>
            </section>) if trip_form else None}
            {(<section className="welcome card"><div className="welcome-art" aria-hidden="true">↗</div><p className="eyebrow">MAKE ROOM FOR ADVENTURE</p>
                <h1>{"Loading your trips…" if loading else "Your next chapter starts with a plan."}</h1>
                <p>Keep your itinerary, reservations, packing list, and budget together. Add your first trip to get started.</p>
                <button type="button" className="primary" onClick={lambda { openTrip(); }} disabled={busy or loading}>Plan my first trip ↗</button>
            </section>) if not current else (
            <div>
                <section className="hero">
                    <div className="hero-landscape" aria-hidden="true"><div className="sun"/><div className="hill hill-back"/><div className="hill hill-front"/><div className="landscape-line"/></div>
                    <div className="hero-content"><span className="status-pill">{status(current)}</span><p className="eyebrow">A LITTLE PLANNING. A LOT TO LOOK FORWARD TO.</p>
                        <h1>{current.title}</h1><p className="destination">◎ {current.destination}</p>
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
                <nav className="tabs" aria-label="Travel sections">{[
                    <button type="button" key={value} data-active={tab == value} onClick={lambda { chooseTab(value); }} disabled={busy or loading}>
                        {"Itinerary" if value == "itinerary" else "Bookings" if value == "bookings" else "Packing list" if value == "packing" else "Budget"}
                    </button> for value in ["itinerary", "bookings", "packing", "budget"]
                ]}</nav>
                {(<section className="budget-overview card"><div><p className="eyebrow">EVERY LITTLE THING ADDS UP</p><h2>Your trip, in numbers.</h2>
                    <p>Costs are counted once, in {current.currency}. Mark each cost paid as you go.</p></div><div className="budget-numbers">
                    <p><span>Budget</span><strong>{money(current.budget_cents, current.currency) if current.budget_cents else "Not set"}</strong></p>
                    <p><span>Planned</span><strong>{money(total, current.currency)}</strong></p><p><span>Paid</span><strong>{money(paid, current.currency)}</strong></p>
                    <p><span>Still to pay</span><strong>{money(total - paid, current.currency)}</strong></p>
                    {(<p className="over-budget">{"Over budget by " + money(total - current.budget_cents, current.currency)}</p>) if current.budget_cents and total > current.budget_cents else None}
                </div></section>) if tab == "budget" else None}
                <div className="detail-grid">
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
            <footer>roam. <span>A place for your plans. A little room for the unexpected.</span></footer>
        </main>
    </div>
}
