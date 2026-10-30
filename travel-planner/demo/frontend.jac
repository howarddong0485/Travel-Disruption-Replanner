"""Guided backup generation and traveler-approved replanning on a saved demo trip."""
import from server.main { TripView, ItemView }
import from backup.frontend { LegacyBackupPanel as BackupPanel }
import from replan.frontend { ReplanPanel }

def:pub GuidedDemo(trip: TripView, items: list[ItemView], onRefresh: any, onViewItinerary: any) -> JsxElement {
    has step: str = "backups", generated: bool = False, accepted: bool = False,
        original: list[ItemView] = items;

    def money(cents: int) -> str {
        value = abs(cents); minor = value % 100;
        return trip.currency + " " + ("-" if cents < 0 else "") + str(value // 100) + "." + ("0" if minor < 10 else "") + str(minor);
    }
    def before(id: str) -> ItemView | None {
        matches = [item for item in original if item.id == id];
        return matches[0] if matches else None;
    }
    def originalTitle(item: ItemView) -> str {
        previous = before(item.id);
        if previous is None { return "Added cost"; }
        return previous.title;
    }
    def originalSchedule(item: ItemView) -> str {
        previous = before(item.id);
        if previous is None { return "—"; }
        return previous.date + " " + previous.time;
    }
    def changed(item: ItemView) -> bool {
        previous = before(item.id);
        if previous is None { return True; }
        return previous.title != item.title or previous.time != item.time or previous.date != item.date;
    }
    async def applied -> None {
        await onRefresh(); accepted = True; step = "complete";
    }
    dinners = [item for item in items if item.category == "food"];
    total = sum([item.cost_cents for item in items]);
    <section className="guided-demo" aria-label="Guided backup and replan demo">
        <div className="card demo-intro">
            <p className="eyebrow">INTERACTIVE DEMO · BOSTON</p><h2>From Plan B to a revised trip</h2>
            <p>Prepare alternatives for dinner, then delay your flight by three hours. See the rental-car, hotel and dinner changes, choose a revised plan, and check the saved result.</p>
            <p className="section-caption">Uses a separate saved demo trip and synthetic inventory. Backup previews are suggestions; the replanning engine checks its own mock combinations before you accept them. No API key or real booking is needed.</p>
        </div>
        <nav className="demo-steps" aria-label="Demo steps">
            <button type="button" data-active={step == "backups"} disabled={accepted} onClick={lambda { step = "backups"; }}>1 · Generate backups {"✓" if generated else ""}</button>
            <button type="button" data-active={step == "replan"} disabled={not generated or accepted} onClick={lambda { step = "replan"; }}>2 · Simulate & replan</button>
            <button type="button" data-active={step == "complete"} disabled={not accepted} onClick={lambda { step = "complete"; }}>3 · Updated itinerary {"✓" if accepted else ""}</button>
        </nav>
        {(<div>
            <div className="card demo-instructions"><h3>Prepare for a late arrival</h3><p>Dinner is already selected. Click <strong>Generate Plan B / C</strong> to get two later dining suggestions. You can also switch to rain and select <strong>Outdoor harbor walk</strong>.</p></div>
            <BackupPanel trip={trip} items={items} initial_trigger="arrival_delay"
                initial_target={dinners[0].id if dinners else ""} onGenerated={lambda { generated = True; }}/>
            <div className="card demo-next"><p>{"Your backup ideas are ready. Now see how a flight delay affects the trip." if generated else "Generate backup ideas to unlock the next step."}</p>
                <button type="button" className="primary" disabled={not generated} onClick={lambda { step = "replan"; }}>Continue to disruption & replan →</button></div>
        </div>) if step == "backups" else None}
        {(<div>
            <div className="card demo-instructions"><h3>Make the flight three hours late</h3><p>Keep <strong>Flight arrival</strong> and the <strong>180-minute</strong> delay, then click <strong>Generate replan options</strong>. Compare the alternatives and accept one. The fixed next-day museum visit stays in place.</p></div>
            <ReplanPanel trip_id={trip.id} currency={trip.currency} onApplied={applied}/>
        </div>) if step == "replan" else None}
        {(<div className="card demo-complete" role="status">
            <p className="eyebrow">REVISED PLAN SAVED</p><h2>Your itinerary is updated</h2>
            <p>Acceptance updated this demo trip in storage. Compare the original schedule with the saved plan below.</p>
            <div className="demo-totals"><p><small>Original planned cost</small><strong>{money(sum([item.cost_cents for item in original]))}</strong></p>
                <p><small>Revised planned cost</small><strong>{money(total)}</strong></p>
                <p><small>Remaining budget</small><strong>{money(trip.budget_cents - total)}</strong></p></div>
            <div className="demo-table-wrap"><table className="demo-timeline"><thead><tr><th>Original item</th><th>Original schedule</th><th>Saved plan</th><th>Updated schedule</th></tr></thead>
                <tbody>{[<tr key={item.id} data-changed={changed(item)}>
                    <td>{originalTitle(item)}</td><td>{originalSchedule(item)}</td>
                    <td>{item.title}</td><td>{item.date + " " + item.time}</td>
                </tr> for item in items if item.category != "packing"]}</tbody></table></div>
            <button type="button" className="primary" onClick={onViewItinerary}>Open updated itinerary →</button>
            <p className="section-caption">Start another demo from the sidebar to try a different choice. Each start creates a new trip.</p>
        </div>) if step == "complete" else None}
    </section>
}
