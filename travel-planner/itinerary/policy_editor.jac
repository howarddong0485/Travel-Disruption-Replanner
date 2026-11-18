"""Explicitly save source terms; extraction does not book or cancel anything."""
import from workspace { workspaceKey }
import from server.main { save_policy_terms }
import from assistant.frontend { assistantError }

def:pub PolicyEditor(trip_id: str, items: any, version: int, onSaved: any, disabled: bool) -> JsxElement {
    has item: str = "", terms: str = "", source: str = "", zone: str = "", expires: str = "",
        busy: bool = False, failure: str = "", notice: str = "";
    async def save(e: FormEvent) -> None {
        e.preventDefault(); busy = True; failure = ""; notice = "";
        try {
            result = await save_policy_terms(workspace_key=await workspaceKey(), trip_id=trip_id, item_id=item, terms=terms, source=source,
                zone=zone, expires_at=expires, expected_version=version);
            onSaved(result);
            notice = "Terms saved for review. No booking or cancellation was made.";
            if result.get("policy_notes", []) { notice += " " + result["policy_notes"].join(" "); }
        } except Exception as exc { failure = assistantError(exc); }
        finally { busy = False; }
    }
    <details className="planning-facts policy-editor"><summary>Add or update cancellation terms</summary>
        <p>Copy the applicable rate's exact terms. Missing or ambiguous terms remain unresolved. This saves evidence only.</p>
        <form onSubmit={save}><fieldset disabled={busy or disabled}>
            <label>Booking or itinerary item<select required={True} value={item} onChange={lambda (e: ChangeEvent) { item = e.target.value; }}>
                <option value="">Choose an item</option>{[<option key={i.id} value={i.id}>{i.title}</option> for i in items if i.category not in ["packing", "expense"]]}</select></label>
            <label>Exact cancellation terms<textarea required={True} maxLength={20000} value={terms} onChange={lambda (e: ChangeEvent) { terms = e.target.value; }}/></label>
            <label>Source URL or booking document reference<input required={True} maxLength={1000} value={source} onChange={lambda (e: ChangeEvent) { source = e.target.value; }}/></label>
            <label>Timezone for this booking and its terms<input required={True} placeholder="America/Chicago" value={zone} onChange={lambda (e: ChangeEvent) { zone = e.target.value; }}/></label>
            <label>Recheck evidence by (ISO timestamp with UTC offset)<input required={True} placeholder="2027-01-01T12:00:00-06:00" value={expires} onChange={lambda (e: ChangeEvent) { expires = e.target.value; }}/></label>
            <button type="submit" className="secondary">{ "Saving terms…" if busy else "Save cancellation terms"}</button>
        </fieldset></form>
        {(<p role="alert">{failure}</p>) if failure else None}
        {(<p role="status">{notice}</p>) if notice else None}
    </details>
}
