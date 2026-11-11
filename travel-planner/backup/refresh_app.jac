"""Standalone preview of the same Roam validation panel, without other feature UIs."""
import "../styles.css";
import from backup.validation_frontend { ValidationLab }
import from backup.frontend { BackupPanel }
import from server.main { TripView, ItemView, list_trips, list_items }

def:pub app -> JsxElement {
    browser: any = window;
    diagnostics = browser.RegExp("(^|[?&])diagnostics=1(&|$)").test(browser.location.search);
    has trips: list[TripView] = [], items: list[ItemView] = [], selected: str = "",
        loading: bool = False, failure: str = "", source: str = "sample", sequence: Ref[int] = Ref(0);
    async def loadTrips -> None {
        loading = True; failure = "";
        try { trips = await list_trips(); } except Exception { failure = "Could not load saved trips."; }
        finally { loading = False; }
    }
    async def chooseTrip(id: str) -> None {
        sequence.current += 1; request = sequence.current;
        selected = id; items = []; loading = True; failure = "";
        try {
            latest = await list_items(trip_id=id) if id else [];
            if request == sequence.current { items = latest; }
        } except Exception { if request == sequence.current { failure = "Could not load this itinerary."; } }
        finally { if request == sequence.current { loading = False; } }
    }
    current = [trip for trip in trips if trip.id == selected];
    return <main className="workspace">
        <header className="topbar"><span>ROAM · BACKUP PLANS</span></header>
        {(<p role="status">Developer diagnostics enabled</p>) if diagnostics else None}
        <div className="card"><label htmlFor="backup-source">Backup input</label>
            <select id="backup-source" value={source} onChange={lambda (e: ChangeEvent) {
                source = e.target.value; if source == "saved" { loadTrips(); }
            }}><option value="sample">Synthetic sample trip</option><option value="saved">Saved Roam itinerary</option></select>
            {(<div><label htmlFor="backup-trip">Saved trip</label><select id="backup-trip" value={selected} disabled={loading} onChange={lambda (e: ChangeEvent) { chooseTrip(e.target.value); }}>
                <option value="">Choose a saved trip</option>{[<option key={trip.id} value={trip.id}>{trip.title + " · " + trip.destination}</option> for trip in trips]}
            </select><p>Explore alternatives for an item in your saved itinerary.</p>
            {(<p>No saved trips in this database.</p>) if not loading and len(trips) == 0 else None}</div>) if source == "saved" else None}
            {(<p role="alert">{failure}</p>) if failure else None}
        </div>
        {(<ValidationLab diagnostics={diagnostics}/>) if source == "sample" else (<BackupPanel key={selected} trip={current[0]} items={items} diagnostics={diagnostics}/>) if not loading and not failure and len(current) == 1 else None}
    </main>;
}
