"""LiteAPI hotel drafts and Geoapify place suggestions, with independent keys."""
import from server.main { travel_provider_status, preview_liteapi_hotels, discover_travel_places }

def:pub TravelDataPanel(trip: any, items: list[any], workflow: str = "backup") -> JsxElement {
    has city: str = "", country: str = "US", item_id: str = "", checkout: str = "",
        occupancy: str = "2", nationality: str = "US", kind: str = "interrupted", delay: str = "180",
        category: str = "hotels", busy: bool = False, error: str = "", result: any = None, places: any = None,
        config: dict[str, any] = {"liteapi": {"configured": False, "mode": "sandbox"}, "geoapify": {"configured": False}};
    def clear -> None { result = None; places = None; error = ""; }
    def amount(cents: int) -> str {
        return trip.currency + " " + str(cents // 100) + "." + ("0" if cents % 100 < 10 else "") + str(cents % 100);
    }
    async def hotels(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; result = None; error = "";
        try {
            result = await preview_liteapi_hotels(trip_id=trip.id, item_id=item_id, checkout=checkout,
                city=city, destination_country=country, occupancy=occupancy, nationality=nationality,
                mode=workflow, kind=kind, delay_minutes=int(delay) if kind == "delayed" else 0);
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async def discover(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; places = None; error = "";
        try { places = await discover_travel_places(trip_id=trip.id, destination=city, country=country, category=category); }
        except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async can with entry {
        city = trip.destination;
        try { config = await travel_provider_status(); } except Exception as exc { error = str(exc); }
    }
    stays = [i for i in items if i.category == "stay"];
    <section className="card replan-workspace provider-panel" aria-label="Hotel and place alternatives">
        <p className="eyebrow">LITEAPI + GEOAPIFY</p>
        <h2>{"Find hotel backup plans" if workflow == "backup" else "Replan with hotel alternatives"}</h2>
        <p>Search hotels by city and compare replacement costs and schedule changes. Explore nearby places for more ideas.</p>
        <fieldset disabled={busy}>
            <label htmlFor="provider-city">Destination city or place</label><input id="provider-city" required={True} value={city} onChange={lambda (e: ChangeEvent) { city = e.target.value; clear(); }}/>
            <label htmlFor="provider-country">Destination country code</label><input id="provider-country" maxLength={2} value={country} onChange={lambda (e: ChangeEvent) { country = e.target.value.upper(); clear(); }}/>
        </fieldset>
        {(<div className="alert error" role="alert">{error}</div>) if error else None}
        <h3>LiteAPI hotel Plan B / C</h3>
        <p className="mock-badge">{"LIVE HOTEL SEARCH" if config["liteapi"]["mode"] == "live" else "SANDBOX · HOTEL TEST OFFERS"}</p>
        {(<p role="status">Add your free LiteAPI sandbox key to the server configuration to search hotels.</p>) if not config["liteapi"]["configured"] else None}
        {(<p>Add a hotel stay with a date and time in Itinerary to generate replacement plans.</p>) if len(stays) == 0 else None}
        <form onSubmit={hotels}><fieldset disabled={busy}>
            <label htmlFor="provider-stay">Stay to replace</label><select id="provider-stay" required={True} value={item_id} onChange={lambda (e: ChangeEvent) { item_id = e.target.value; result = None; }}><option value="">Choose a hotel stay</option>{[<option key={i.id} value={i.id}>{i.title + " · " + i.date}</option> for i in stays]}</select>
            <label htmlFor="provider-checkout">Check-out date</label><input id="provider-checkout" type="date" required={True} max={trip.end_date} value={checkout} onChange={lambda (e: ChangeEvent) { checkout = e.target.value; result = None; }}/>
            <label htmlFor="provider-guests">Guests in one room</label><input id="provider-guests" required={True} value={occupancy} onChange={lambda (e: ChangeEvent) { occupancy = e.target.value; result = None; }}/>
            <p className="section-caption">2 means two adults. 2-9,4 adds children aged 9 and 4.</p>
            <label htmlFor="provider-nationality">Guest nationality code</label><input id="provider-nationality" maxLength={2} required={True} value={nationality} onChange={lambda (e: ChangeEvent) { nationality = e.target.value.upper(); result = None; }}/>
            {(<div><label htmlFor="provider-event">Hotel disruption</label><select id="provider-event" value={kind} onChange={lambda (e: ChangeEvent) { kind = e.target.value; result = None; }}><option value="interrupted">Hotel canceled or unavailable</option><option value="delayed">Delayed arrival</option></select>
                {(<div><label htmlFor="provider-delay">Arrival delay in minutes</label><input id="provider-delay" type="number" min="1" max="1440" required={True} value={delay} onChange={lambda (e: ChangeEvent) { delay = e.target.value; result = None; }}/></div>) if kind == "delayed" else None}
            </div>) if workflow == "replan" else None}
            <button type="submit" className="primary" disabled={busy or not item_id or not config["liteapi"]["configured"]}>{"Searching…" if busy else "Generate hotel plans"}</button>
        </fieldset></form>
        {(<div role="status"><p>{"Live LiteAPI offers" if result["mode"] == "live" else "LiteAPI sandbox offers · Test data"}</p>
            {(<p>No replacement passed the current checks. Review the reasons below.</p>) if len(result["proposals"]) == 0 else None}
            <div className="replan-proposals">{[<article className="card proposal-card" key={p["offer"]["id"]}>
                <p className="eyebrow">{p["title"] + " · NEEDS VALIDATION"}</p><h3>{p["offer"]["title"]}</h3>
                <p>{p["offer"]["room_name"] + " · " + p["offer"]["checkin"] + " → " + p["offer"]["checkout"]}</p>
                <div className="proposal-metrics"><p><small>Replacement stay total</small><strong>{amount(p["replacement_cash_cents"])}</strong></p><p><small>Projected trip cost</small><strong>{amount(p["projected_total_cents"])}</strong></p><p><small>Prior payment retained</small><strong>{amount(p["retained_paid_cents"])}</strong></p></div>
                <p>{"Rate refundability: " + p["offer"]["current_refundability"]}</p>
                <ul className="proposal-changes">{[<li key={c["item_id"]}><strong>{c["before"]["title"] + " → " + c["after"]["title"]}</strong><span>{c["after"]["date"] + " " + c["after"]["time"]}</span></li> for c in p["changes"]]}</ul>
                <p className="section-caption">{p["validation"] + " Checked: " + p["offer"]["checked_at"]}</p>
            </article> for p in result["proposals"]]}</div><ul>{[<li key={w}>{w}</li> for w in result["warnings"]]}</ul>
        </div>) if result else None}
        <h3>Explore nearby places with Geoapify</h3>
        {(<p role="status">Add your free Geoapify key to the server configuration to find places.</p>) if not config["geoapify"]["configured"] else None}
        <form onSubmit={discover}><fieldset disabled={busy}><label htmlFor="provider-category">Places to find</label><select id="provider-category" value={category} onChange={lambda (e: ChangeEvent) { category = e.target.value; places = None; }}><option value="hotels">Hotels</option><option value="restaurants">Restaurants</option><option value="attractions">Attractions and sights</option></select>
            <button type="submit" className="secondary" disabled={busy or not config["geoapify"]["configured"]}>{"Searching…" if busy else "Find nearby places"}</button>
        </fieldset></form>
        {(<div role="status"><p>{"Resolved destination: " + places["resolved_destination"]}</p>
            {(<p>No matching places found.</p>) if len(places["places"]) == 0 else None}
            <div className="backup-grid">{[<article className="backup-chip" key={p["id"]}><strong>{p["title"]}</strong><p>{p["address"]}</p><small>Price and availability unknown</small></article> for p in places["places"]]}</div>
            <p className="section-caption">Place suggestions need location, opening-hours and traveler-requirement checks. Geoapify place IDs are separate from LiteAPI hotel IDs.</p>
        </div>) if places else None}
        <p className="section-caption"><a href="https://www.geoapify.com/">Powered by Geoapify</a> · <a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a></p>
        <p className="section-caption">Drafts only. No reservations or saved itinerary changes. Provider errors never fall back to invented live inventory.</p>
    </section>
}
