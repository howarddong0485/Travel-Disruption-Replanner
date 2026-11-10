"""Contextual itinerary actions and keyboard focus."""

def:pub focusItineraryControl(id: str) -> None {
    element: any = document.getElementById(id);
    if element { element.focus(); }
}

def:pub ItemActions(item_id: str, title: str, category: str, disabled: bool, onReview: any) -> JsxElement {
    has open: bool = False;
    control = "itinerary-actions-" + item_id;
    panel = control + "-panel";
    def close -> None { open = False; focusItineraryControl(control); }
    def review(reason: str) -> None {
        open = False;
        onReview(item_id, reason, control);
    }
    can with [open] entry {
        if open { focusItineraryControl(panel + "-first"); }
    }
    <div className="itinerary-actions" onBlur={lambda (e: any) {
        if not e.currentTarget.contains(e.relatedTarget) { open = False; }
    }} onKeyDown={lambda (e: any) {
        if open and e.key == "Escape" { e.stopPropagation(); close(); }
    }}>
        <button type="button" id={control} className="itinerary-chip" disabled={disabled}
            aria-label={"Options for " + title} aria-expanded={open} aria-controls={panel}
            onClick={lambda { open = not open; }}>Actions <span aria-hidden="true">⌄</span></button>
        {(<div id={panel} className="itinerary-popover" role="group" aria-label={"Actions for " + title}>
            <button type="button" id={panel + "-first"} onClick={lambda { review("timing"); }}>Report a delay</button>
            <button type="button" onClick={lambda { review(""); }}>Review impact</button>
            <button type="button" onClick={lambda { review("traveler_change"); }}>Find alternatives</button>
            {(<button type="button" onClick={lambda { review("weather"); }}>Find indoor options</button>) if category == "activity" else None}
        </div>) if open else None}
    </div>
}
