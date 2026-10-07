"""Gehao Dong's isolated backup preview; no acceptance or trip mutation controls."""
import from server.main { TripView, ItemView, preview_backups }
import from backup.models { BackupPreview as PreviewState }

def:pub BackupPanel(trip: TripView, items: list[ItemView]) -> JsxElement {
    has target: str = "", trigger: str = "rain", pending: bool = False,
        failure: str = "", preview: PreviewState | None = None;

    async def generate -> None {
        if pending { return; }
        pending = True; failure = ""; preview = None;
        try { preview = await preview_backups(trip_id=trip.id, item_id=target, trigger=trigger); }
        except Exception as exc { failure = str(exc); }
        finally { pending = False; }
    }
    def estimate(minor: int) -> str {
        return "USD " + str(minor // 100) + "." + ("0" if minor % 100 < 10 else "") + str(minor % 100);
    }
    eligible = [item for item in items if item.category == ("activity" if trigger == "rain" else "food") and not item.done and item.date];
    return <section className="card backup-panel" aria-label="Proactive backups">
        <p className="eyebrow">PREPARE BEFORE PLANS CHANGE · MOCK DEMO</p>
        <h2>A little room for Plan B.</h2>
        <p>Preview backup ideas for a dated activity or dinner. The demo inventory covers Boston in USD.
            These are suggestions, not reservations. Generating ideas leaves your itinerary and budget unchanged.</p>
        <div className="form-pair">
            <div><label htmlFor="backup-trigger">Activation scenario</label>
                <select id="backup-trigger" value={trigger} disabled={pending} onChange={lambda (e: ChangeEvent) { trigger = e.target.value; target = ""; preview = None; failure = ""; }}>
                    <option value="rain">Rain affects an outdoor activity</option>
                    <option value="arrival_delay">Delayed arrival affects dinner</option>
                </select></div>
            <div><label htmlFor="backup-target">Original itinerary item</label>
                <select id="backup-target" value={target} disabled={pending} onChange={lambda (e: ChangeEvent) { target = e.target.value; preview = None; failure = ""; }}>
                    <option value="">Choose an item</option>
                    {[<option key={item.id} value={item.id}>{item.title + " · " + item.date}</option> for item in eligible]}
                </select></div>
        </div>
        {(<p role="status">Add a dated, unfinished {"activity" if trigger == "rain" else "dining item"} to preview backups.</p>) if len(eligible) == 0 else None}
        <button type="button" className="primary" disabled={pending or not target} onClick={generate}>{"Checking mock inventory…" if pending else "Refresh mock ideas" if preview else "Prepare Plan B / C"}</button>
        {(<p className="alert error" role="alert">{failure}</p>) if failure else None}
        {(<div aria-live="polite">
            <p className="backup-disclaimer">{preview.message}</p>
            <div className="backup-options">{[<article className="backup-option" key={option.id}>
                <p className="eyebrow">{option.label + " · NEEDS FULL VALIDATION"}</p>
                <h3>{option.candidate.title}</h3>
                <p>{option.activation_condition}</p>
                <p><strong>{estimate(option.candidate.estimated_cost_minor)}</strong> · synthetic candidate estimate</p>
                <p>Availability: {option.candidate.availability} in mock inventory</p>
                <p>Source: {option.candidate.source_ref}</p>
                <p>Checked: {option.candidate.checked_at}</p><p>Evidence expires: {option.candidate.expires_at}</p>
                <ul>{[<li key={note}>{note}</li> for note in option.validation_notes]}</ul>
            </article> for option in preview.options]}</div>
            {(<details><summary>Excluded inventory</summary><ul>{[<li key={reason}>{reason}</li> for reason in preview.exclusions]}</ul></details>) if len(preview.exclusions) > 0 else None}
        </div>) if preview else None}
    </section>;
}
