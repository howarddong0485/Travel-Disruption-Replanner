"""Contextual itinerary actions and read-only delay impact."""
import from server.main { replan_state }
import from itinerary.presentation { affectedItemIds }

def:pub focusItineraryControl(id: str) -> None {
    element: any = document.getElementById(id);
    if element { element.focus(); }
}

def:pub ItemActions(trip_id: str, item_id: str, title: str, category: str, disabled: bool, onReview: any) -> JsxElement {
    has open: bool = False, delayMode: bool = False, minutes: str = "60",
        snapshot: any = None, loading: bool = False, failure: str = "", placement: any = {},
        sequence: Ref[int] = Ref(0), alive: Ref[bool] = Ref(True), outside: Ref[any] = Ref(None);
    control = "itinerary-actions-" + item_id;
    panel = control + "-panel";
    def positionPanel(expanded: bool) -> None {
        browser: any = window; trigger: any = document.getElementById(control);
        rect = trigger.getBoundingClientRect(); width = min(292, browser.innerWidth - 24);
        height = 300 if expanded else 180;
        top = rect.bottom + 6 if rect.bottom + height + 6 <= browser.innerHeight else max(12, rect.top - height - 6);
        placement = {"position": "fixed", "left": str(max(12, min(rect.left, browser.innerWidth - width - 12))) + "px",
            "top": str(top) + "px", "width": str(width) + "px", "maxWidth": "calc(100vw - 24px)",
            "maxHeight": str(browser.innerHeight - top - 12) + "px", "overflowY": "auto"};
    }
    def close -> None { open = False; sequence.current += 1; focusItineraryControl(control); }
    def review(reason: str, amount: str = "") -> None {
        open = False; sequence.current += 1;
        onReview(item_id, reason, control, amount);
    }
    async def delayImpact -> None {
        positionPanel(True);
        delayMode = True; loading = True; failure = ""; snapshot = None;
        sequence.current += 1; token = sequence.current;
        window.requestAnimationFrame(lambda { focusItineraryControl(panel + "-delay"); });
        try {
            fresh = await replan_state(trip_id=trip_id);
            if alive.current and token == sequence.current { snapshot = fresh; }
        } except Exception {
            if alive.current and token == sequence.current { failure = "Open the review to check the latest trip."; }
        } finally { if alive.current and token == sequence.current { loading = False; } }
    }
    can with [open] entry {
        if open { delayMode = False; focusItineraryControl(panel + "-first"); }
    }
    can with entry {
        outside.current = lambda (e: any) {
            anchor: any = document.getElementById(control + "-anchor");
            if anchor and not anchor.contains(e.target) { open = False; sequence.current += 1; }
        };
        window.addEventListener("pointerdown", outside.current);
    }
    can with exit { alive.current = False; sequence.current += 1; window.removeEventListener("pointerdown", outside.current); }
    affected = affectedItemIds(snapshot, item_id);
    <div id={control + "-anchor"} className="itinerary-actions" onBlur={lambda (e: any) {
        if e.relatedTarget and not e.currentTarget.contains(e.relatedTarget) { open = False; sequence.current += 1; }
    }} onKeyDown={lambda (e: any) {
        if open and e.key == "Escape" { e.stopPropagation(); close(); }
    }}>
        <button type="button" id={control} className="itinerary-chip" disabled={disabled}
            aria-label={"Options for " + title} aria-expanded={open} aria-controls={panel}
            onClick={lambda { if open { close(); } else { positionPanel(False); open = True; } }}>Actions <span aria-hidden="true">⌄</span></button>
        {(<div id={panel} className="itinerary-popover" style={placement} role="group" aria-label={"Actions for " + title}>
            {(<div className="quick-delay">
                <strong>{title}</strong><p>How late is it?</p>
                <div role="group" aria-label="Quick delay">
                    {[<button type="button" id={panel + "-delay" if value == "30" else panel + "-" + value}
                        key={value} aria-pressed={minutes == value} onClick={lambda { minutes = value; }}>
                        {"+30 min" if value == "30" else "+1 hour" if value == "60" else "+3 hours"}
                    </button> for value in ["30", "60", "180"]]}
                </div>
                <p role="status">{("Checking saved connections…" if loading else
                    str(len(affected)) + (" arrangement to check" if len(affected) == 1 else " arrangements to check"))
                    if not failure else failure}</p>
                <small>Includes this stop and its saved downstream dependencies.</small>
                <button type="button" className="quick-delay-review" disabled={loading}
                    onClick={lambda { review("timing", minutes); }}>Review impact and options →</button>
                <button type="button" className="text-button" onClick={lambda {
                    delayMode = False; sequence.current += 1; positionPanel(False);
                    window.requestAnimationFrame(lambda { focusItineraryControl(panel + "-first"); });
                }}>Back to actions</button>
            </div>) if delayMode else (<div>
                <button type="button" id={panel + "-first"} onClick={delayImpact}>Report a delay</button>
                <button type="button" onClick={lambda { review(""); }}>Review impact</button>
                <button type="button" onClick={lambda { review("traveler_change"); }}>Find alternatives</button>
                {(<button type="button" onClick={lambda { review("weather"); }}>Find indoor options</button>) if category == "activity" else None}
            </div>)}
        </div>) if open else None}
    </div>
}
