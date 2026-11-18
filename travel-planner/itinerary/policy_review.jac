"""Reusable policy evidence on alternative cards, AI drafts and the risk panel."""
def:pub PolicyReview(rows: any) -> JsxElement {
    browser: any = window;
    has tick: float = 0, timer: Ref[any] = Ref(None);
    can with [rows] entry { tick = browser.Date.now(); }
    can with entry { tick = browser.Date.now(); timer.current = browser.setInterval(lambda { tick = browser.Date.now(); }, 1000); }
    can with exit { browser.clearInterval(timer.current); }
    def expired(row: any) -> bool {
        current = tick or browser.Date.now();
        return bool(row.get("deadline_at") and browser.Date.parse(row["deadline_at"]) <= current) or
            any(source["current"] and browser.Date.parse(source["expires_at"]) <= current for source in row["sources"]);
    }
    <section className="policy-review" aria-label="Cancellation consequences">
        <h4>Cancellation consequences</h4>
        <p>Saving an itinerary does not cancel or book with a supplier. Potential refunds are not deducted from the trip total.</p>
        {[<details className="policy-review-item" key={row["item_id"]}>
            <summary>{row["title"] + " · " + ("Cancellation terms need a fresh check" if expired(row) else row["label"])}</summary>
            {(<p>Changing the time keeps this saved item; confirm whether the provider permits the change.</p>) if row.get("action") == "reschedule" else None}
            <dl className="validation-costs">
                <div><dt>Cancellation fee</dt><dd>{"Unknown until rechecked" if expired(row) else row["fee"]}</dd></div>
                <div><dt>Potential refund</dt><dd>{"Unknown until rechecked" if expired(row) else row["refund"] + " · " + row["refund_form"]}</dd></div>
                <div><dt>Next deadline</dt><dd>{row["deadline"] + " · " + (row["zone"] or "Timezone unknown")}</dd></div>
            </dl>
            {(<div role="note"><strong>Unresolved policy risk</strong><ul>{[<li key={text}>{text}</li> for text in row["unknowns"]]}</ul></div>) if row["requires_confirmation"] else None}
            {(<p role="status">The evidence or cancellation window expired. Refresh before relying on these terms.</p>) if expired(row) else None}
            {[<div className="policy-source" key={str(index)}><blockquote>{source["excerpt"]}</blockquote>
                <p>{source["source"]}</p>
                <small>{"Checked: " + (source["checked_at"] or "Unknown") + " · Valid until: " + (source["expires_at"] or "Unknown")}</small>
                <strong>{"Within recorded validity period" if source["current"] and not expired(row) else "Evidence needs confirmation"}</strong>
            </div> for (index, source) in enumerate(row["sources"])]}
        </details> for row in rows]}
    </section>
}
