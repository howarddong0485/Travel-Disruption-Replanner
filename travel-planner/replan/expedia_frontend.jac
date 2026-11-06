"""Hotel shopping and automatically computed review drafts."""
import from server.main { preview_expedia_hotels, expedia_status }

def:pub ExpediaPanel(trip: any, items: list[any], workflow: str = "backup") -> JsxElement {
    has item_id: str = "", checkout: str = "", property_ids: str = "", occupancy: str = "2",
        country: str = "US", kind: str = "interrupted", delay: str = "180",
        busy: bool = False, error: str = "", result: any = None,
        config: dict[str, any] = {"configured": False, "mode": "test"};
    def clear -> None { result = None; error = ""; }
    def amount(cents: int) -> str {
        return trip.currency + " " + str(cents // 100) + "." + ("0" if cents % 100 < 10 else "") + str(cents % 100);
    }
    async def generate(e: FormEvent) -> None {
        e.preventDefault(); if busy { return; } busy = True; clear();
        try {
            result = await preview_expedia_hotels(trip_id=trip.id, item_id=item_id, checkout=checkout,
                property_ids=[p.strip() for p in property_ids.split(",") if p.strip()], occupancy=occupancy,
                country=country, mode=workflow, kind=kind, delay_minutes=int(delay) if kind == "delayed" else 0);
        } except Exception as exc { error = str(exc); }
        finally { busy = False; }
    }
    async can with entry {
        try { config = await expedia_status(); } except Exception as exc { error = str(exc); }
    }
    hotels = [i for i in items if i.category == "stay"];
    <section className="card expedia-panel" aria-label="Expedia hotel alternatives">
        <p className="eyebrow">EXPEDIA · {"LIVE SEARCH" if config["mode"] == "live" else "PROVIDER TEST DATA"}</p>
        <h3>{"Replan a hotel disruption" if workflow == "replan" else "Find hotel Plan B / C"}</h3>
        <p>Search your hotel shortlist and automatically compare replacement costs and schedule changes.</p>
        {(<p role="status" className="section-caption">Expedia partner access needs to be configured on the server before searching.</p>) if not config["configured"] else None}
        {(<p>Add a dated hotel stay in Itinerary first.</p>) if len(hotels) == 0 else None}
        <form onSubmit={generate}>
            <fieldset disabled={busy}>
                <label htmlFor="expedia-stay">Hotel stay to replace</label>
                <select id="expedia-stay" value={item_id} required={True} onChange={lambda (e: ChangeEvent) { item_id = e.target.value; clear(); }}>
                    <option value="">Choose a stay</option>{[<option key={i.id} value={i.id}>{i.title + " · " + i.date}</option> for i in hotels]}
                </select>
                <label htmlFor="expedia-checkout">Check-out date</label>
                <input id="expedia-checkout" type="date" required={True} max={trip.end_date} value={checkout} onChange={lambda (e: ChangeEvent) { checkout = e.target.value; clear(); }}/>
                <label htmlFor="expedia-properties">Hotel shortlist (Expedia property IDs, comma-separated)</label>
                <input id="expedia-properties" required={True} value={property_ids} placeholder="19248, 20321" onChange={lambda (e: ChangeEvent) { property_ids = e.target.value; clear(); }}/>
                <label htmlFor="expedia-party">Guests in one room</label>
                <input id="expedia-party" required={True} value={occupancy} onChange={lambda (e: ChangeEvent) { occupancy = e.target.value; clear(); }}/>
                <p className="section-caption">Use 2 for two adults, or 2-9,4 for two adults and children aged 9 and 4.</p>
                <label htmlFor="expedia-country">Traveler country code</label>
                <input id="expedia-country" required={True} maxLength={2} value={country} onChange={lambda (e: ChangeEvent) { country = e.target.value.upper(); clear(); }}/>
                {(<div><label htmlFor="expedia-kind">What changed?</label><select id="expedia-kind" value={kind} onChange={lambda (e: ChangeEvent) { kind = e.target.value; clear(); }}><option value="interrupted">Hotel unavailable / canceled</option><option value="delayed">Delayed arrival at hotel</option></select>
                    {(<div><label htmlFor="expedia-delay">Delay in minutes</label><input id="expedia-delay" type="number" required={True} min="1" max="1440" value={delay} onChange={lambda (e: ChangeEvent) { delay = e.target.value; clear(); }}/></div>) if kind == "delayed" else None}
                </div>) if workflow == "replan" else None}
                <button type="submit" className="primary" disabled={busy or not config["configured"] or not item_id}>{"Searching Expedia…" if busy else "Generate hotel options"}</button>
            </fieldset>
        </form>
        {(<div role="alert" className="alert error">{error}</div>) if error else None}
        {(<div role="status"><p>{"Expedia live results" if result["mode"] == "live" else "Expedia test results · Not live inventory"}</p>
            {(<p>No hotel replacements passed the current itinerary checks.</p>) if len(result["proposals"]) == 0 else None}
            <div className="replan-proposals">{[<article className="card proposal-card" key={p["offer"]["id"]}>
                <p className="eyebrow">{p["title"] + " · NEEDS VALIDATION"}</p><h3>{p["offer"]["title"]}</h3>
                <p>{p["offer"]["room_name"] + " · " + p["offer"]["checkin"] + " → " + p["offer"]["checkout"]}</p>
                <div className="proposal-metrics"><p><small>Replacement stay total</small><strong>{amount(p["replacement_cash_cents"])}</strong></p><p><small>Projected trip total</small><strong>{amount(p["projected_total_cents"])}</strong></p><p><small>Prior payment retained</small><strong>{amount(p["retained_paid_cents"])}</strong></p></div>
                <p>{"Replacement rate refundability: " + p["offer"]["current_refundability"]}</p>
                <ul className="proposal-changes">{[<li key={c["item_id"]}><strong>{c["before"]["title"] + " → " + c["after"]["title"]}</strong><span>{c["after"]["date"] + " " + c["after"]["time"]}</span></li> for c in p["changes"]]}</ul>
                <p className="section-caption">{p["validation"]}</p><p className="section-caption">{"Checked: " + p["offer"]["checked_at"] + ". Refresh before booking."}</p>
            </article> for p in result["proposals"]]}</div>
            <ul>{[<li key={w}>{w}</li> for w in result["warnings"]]}</ul>
        </div>) if result else None}
        <p className="section-caption">Preview only. Review hotel check-in rules, travel times and traveler requirements before choosing. Your saved itinerary stays unchanged.</p>
    </section>
}
