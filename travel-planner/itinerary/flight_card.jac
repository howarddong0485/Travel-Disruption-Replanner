"""Dated, linked flight research displayed in plan review and on the saved-trip map."""
def:pub FlightCard(flight: any) -> JsxElement {
    <div className="flight-details" aria-label="Flight listing">
        <strong>{flight["airline"] + " · " + flight["flight_number"]}</strong>
        <p>{flight["departure_airport"] + " → " + flight["arrival_airport"]}</p>
        <p>{flight["departure_date"] + " " + flight["departure_time"] + " → " + flight["arrival_date"] + " " + flight["arrival_time"] + " · airport local times"}</p>
        <small>Web-sourced listing · confirm availability with the airline</small>
        {(<p>{flight["currency"] + " " + (flight["fare_cents"] / 100).toFixed(2) + " · web-listed fare"}</p>) if flight.get("fare_cents") is not None else None}
        <small>{flight["price_status"]}</small>
        <a href={flight["source_url"]} target="_blank" rel="noopener noreferrer">View flight source ↗</a>
    </div>
}
