"""Day navigation and place cards for the saved itinerary."""
import from server.main { ItemView }
import from itinerary.actions { focusItineraryControl }
import from journey.display { journeyCity }

def:pub itineraryMapLink(location: str, destination: str) -> str {
    browser: any = window;
    return "https://www.google.com/maps/search/?api=1&query=" + browser.encodeURIComponent(location + ", " + destination);
}

def shortDate(value: str) -> str {
    return new(Date, value + "T12:00:00").toLocaleDateString("en-US",
        {"weekday": "short", "month": "short", "day": "numeric"});
}

def:pub ItineraryDays(items: list[ItemView], day: str, start_date: str, end_date: str,
    onChange: any) -> JsxElement {
    counts: dict[str, int] = {};
    for item in items {
        if item.date { counts[item.date] = counts.get(item.date, 0) + 1; }
    }
    browser: any = window;
    days: list[str] = sorted(browser.Object.keys(counts));
    <div className="itinerary-day-controls">
        <div className="itinerary-day-list" role="group" aria-label="Itinerary dates">
            <button type="button" className="itinerary-day-chip" aria-pressed={not day} onClick={lambda { onChange(""); }}>
                <strong>All days</strong><small>{str(len(items)) + (" stop" if len(items) == 1 else " stops")}</small>
            </button>
            {[<button type="button" className="itinerary-day-chip" key={date} aria-pressed={day == date}
                onClick={lambda { onChange(date); }}>
                <strong>{shortDate(date)}</strong><small>{str(counts[date]) + (" stop" if counts[date] == 1 else " stops")}</small>
            </button> for date in days]}
        </div>
        <details className="itinerary-date-jump">
            <summary>Jump to date</summary>
            <label htmlFor="day-filter">Show date</label>
            <input id="day-filter" type="date" min={start_date} max={end_date} value={day}
                onChange={lambda (e: ChangeEvent) { onChange(e.target.value); }}/>
        </details>
    </div>
}

def:pub ItineraryPlaces(places: list[ItemView], place: ItemView | None, destination: str,
    day: str, disabled: bool, onSelect: any, onReview: any) -> JsxElement {
    activeId = place.id if place is not None else "";
    title = place.title if place is not None else "";
    address = place.location if place is not None else "";
    hasMapAddress = bool(address) and not address.startswith("fixture:");
    return <section className="card itinerary-places" aria-labelledby="itinerary-places-heading">
        <div className="places-heading">
            <p className="eyebrow">EXPLORE YOUR STOPS</p>
            <h2 id="itinerary-places-heading" tabIndex={-1}>Places in {journeyCity(place, destination)}</h2>
            <p>{shortDate(day) if day else "All days"} <span aria-hidden="true">·</span>
                {" " + str(len(places)) + (" place" if len(places) == 1 else " places")}</p>
        </div>
        {(<div className="places-content">
            <div className="place-list" role="group" aria-label="Select an itinerary place">
                {[<button type="button" className="place-list-button" key={item.id}
                    aria-pressed={item.id == activeId} disabled={disabled}
                    onClick={lambda { onSelect(item.id); }}>
                    <span className="place-number" aria-hidden="true">{str(index + 1)}</span>
                    <span><strong>{item.title}</strong><small>{item.category + (" · " + item.time if item.time else "")}</small></span>
                </button> for (index, item) in enumerate(places)]}
            </div>
            <div className="place-detail" aria-live="polite">
                <h3>{title}</h3>
                <p>{address if hasMapAddress else "Sample stop without a map address"}</p>
                <div className="place-actions">
                    <button type="button" className="itinerary-chip" disabled={disabled}
                        onClick={lambda { focusItineraryControl("itinerary-stop-" + activeId); }}>Show in itinerary</button>
                    {(<a className="itinerary-chip" href={itineraryMapLink(address, journeyCity(place, destination))} target="_blank"
                        rel="noopener noreferrer">Open in Maps ↗</a>) if hasMapAddress else None}
                    <button type="button" id="place-review-action" className="itinerary-chip" disabled={disabled}
                        onClick={lambda { onReview(activeId, "", "place-review-action"); }}>Review this stop</button>
                </div>
            </div>
        </div>) if place else (<p className="places-empty">Add an address or a place name to a stop to see it here.</p>)}
    </section>;
}
