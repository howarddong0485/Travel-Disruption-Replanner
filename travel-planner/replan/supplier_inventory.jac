"""Read-only LiteAPI quotes and server-side supplier status for Backup plans."""
import from workspace { workspaceKey }
import from server.main { quote_liteapi_hotels, travel_provider_status }

def providerStatus(config: dict[str, any], testLabel: str) -> str {
    if config.get("error") { return config["error"]; }
    if not config["configured"] { return "Not configured"; }
    return "Live access configured" if config["mode"] == "live" else testLabel;
}

def quoteTotal(quote: dict[str, any]) -> str {
    cents = quote["cost_cents"];
    fraction = cents % 100;
    return quote["currency"] + " " + str(cents // 100) + "." + ("0" if fraction < 10 else "") + str(fraction);
}

def:pub SupplierInventory(trip: any) -> JsxElement {
    has config: any = None, statusFailed: bool = False, busy: bool = False, result: any = None, error: str = "",
        city: str = trip.destination, country: str = "", checkin: str = trip.start_date,
        checkout: str = trip.end_date, guests: str = "2", nationality: str = "";
    async can with entry {
        try { config = await travel_provider_status(); }
        except Exception { statusFailed = True; }
    }
    async def findRates(e: FormEvent) -> None {
        e.preventDefault();
        if busy or not config or not config["liteapi"]["configured"] { return; }
        busy = True; error = ""; result = None;
        try {
            data = await quote_liteapi_hotels(workspace_key=await workspaceKey(), trip_id=trip.id,
                checkin=checkin, checkout=checkout, city=city, destination_country=country.strip().upper(),
                occupancy=guests.strip(), nationality=nationality.strip().upper());
            if data.get("error") { error = data["error"]; }
            else { result = data; }
        } except Exception { error = "Could not check hotel rates. Reload the trip or try again."; }
        finally { busy = False; }
    }
    <section className="card replan-workspace provider-panel" aria-label="Supplier inventory">
        <h2>Supplier inventory</h2>
        <p>Check LiteAPI hotel rates and availability for this trip. Searching does not reserve a room or change your itinerary.</p>
        {(<p className="alert error" role="alert">Could not check provider status. Reopen Backup plans to retry.</p>) if statusFailed else (
            <p role="status">Checking provider status…</p>) if not config else (
            <ul aria-label="Provider configuration">
                <li><strong>LiteAPI</strong> {providerStatus(config["liteapi"], "Sandbox access configured")}</li>
                <li><strong>Expedia</strong> {providerStatus(config["expedia"], "Test access configured")} · separate integration</li>
                <li><strong>Geoapify</strong> {"Configured" if config["geoapify"]["configured"] else "Not configured"} · place discovery</li>
            </ul>)}
        <p className="section-caption">The sample backup plans use simulated inventory. This search shows supplier quotes or sandbox test data, labeled on the results.</p>
        {(<form onSubmit={findRates} onChange={lambda { result = None; error = ""; }}>
            <fieldset disabled={busy}>
                <label htmlFor="supplier-city">Destination city</label><input id="supplier-city" value={city}
                    onChange={lambda (e: ChangeEvent) { city = e.target.value; }} required={True} maxLength={160}/>
                <label htmlFor="supplier-country">Destination country code</label><input id="supplier-country" value={country}
                    onChange={lambda (e: ChangeEvent) { country = e.target.value; }} placeholder="US" required={True} maxLength={2}/>
                <label htmlFor="supplier-checkin">Check-in</label><input id="supplier-checkin" type="date" value={checkin}
                    onChange={lambda (e: ChangeEvent) { checkin = e.target.value; }} required={True} min={trip.start_date} max={trip.end_date}/>
                <label htmlFor="supplier-checkout">Check-out</label><input id="supplier-checkout" type="date" value={checkout}
                    onChange={lambda (e: ChangeEvent) { checkout = e.target.value; }} required={True} min={trip.start_date} max={trip.end_date}/>
                <label htmlFor="supplier-guests">Guests in one room</label><input id="supplier-guests" value={guests}
                    onChange={lambda (e: ChangeEvent) { guests = e.target.value; }} required={True} maxLength={19} aria-describedby="supplier-guests-help"/>
                <p id="supplier-guests-help" className="section-caption">Use 2 for two adults, or 2-9,4 for two adults and children aged 9 and 4.</p>
                <label htmlFor="supplier-nationality">Guest nationality code</label><input id="supplier-nationality" value={nationality}
                    onChange={lambda (e: ChangeEvent) { nationality = e.target.value; }} placeholder="US" required={True} maxLength={2}/>
                <button className="primary" type="submit">{"Checking rates…" if busy else "Check hotel rates"}</button>
            </fieldset>
        </form>) if config and config["liteapi"]["configured"] else None}
        {(<p className="alert error" role="alert">{error}</p>) if error else None}
        {(<div role="status">
            <h3>{"LiteAPI live quotes" if result["mode"] == "live" else "LiteAPI sandbox quotes · Test data"}</h3>
            {(<p>No usable quotes were returned for this search.</p>) if not result["quotes"] else None}
            <div className="backup-grid">{[<article className="backup-chip" key={quote["property_id"]}>
                <h4>{quote["title"]}</h4>
                <p>{quote["room_name"] + " · Property " + quote["property_id"]}</p>
                <p>{quote["checkin"] + " to " + quote["checkout"] + " · One room · Guests " + quote["occupancy"]}</p>
                <p><strong>{quoteTotal(quote)}</strong> whole-stay total</p>
                <p>{"Refundability: " + quote["refundability"]}</p>
                <small>Retrieved <time dateTime={quote["checked_at"]}>{quote["checked_at"]}</time></small>
            </article> for quote in result["quotes"]]}</div>
            {(<p className="section-caption">{"Rates excluded by quote checks: " + str(result["excluded_count"])}</p>) if result["excluded_count"] else None}
        </div>) if result else None}
    </section>
}
