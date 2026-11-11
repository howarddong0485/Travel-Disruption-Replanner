"""Explain unresolved checks using recorded source and freshness information."""
import from itinerary.actions { focusItineraryControl }

def:pub planSources(plan: any, facts: any) -> any {
    sources: any = [];
    ids = [change["replaces_id"] for change in plan["replacements"]];
    for change in plan["replacements"] {
        proof = change["item"].get("evidence");
        if proof { sources.append(proof); }
    }
    for id in ids {
        proof = facts.get("items", {}).get(id, {}).get("evidence");
        if proof and not any(source["source"] == proof["source"] for source in sources) { sources.append(proof); }
    }
    for risk in plan.get("risks", []) {
        proof = risk.get("evidence");
        if proof and not any(source["source"] == proof["source"] for source in sources) { sources.append(proof); }
    }
    return sources;
}

def:pub EvidencePopover(id: str, checks: any, sources: any, onFacts: any,
    actionLabel: str = "Open saved trip facts") -> JsxElement {
    has open: bool = False, placement: any = {}, outside: Ref[any] = Ref(None);
    def close -> None { open = False; focusItineraryControl(id); }
    def toggle -> None {
        if open { close(); return; }
        browser: any = window; trigger: any = document.getElementById(id);
        rect = trigger.getBoundingClientRect();
        width = min(360, browser.innerWidth - 32);
        height = min(440, browser.innerHeight - 32);
        top = rect.bottom + 8 if rect.bottom + height + 8 <= browser.innerHeight else max(12, rect.top - height - 8);
        placement = {"left": str(max(12, min(rect.left, browser.innerWidth - width - 12))) + "px",
            "top": str(top) + "px", "maxHeight": str(browser.innerHeight - top - 12) + "px"};
        open = True;
    }
    can with [open] entry { if open { focusItineraryControl(id + "-close"); } }
    can with entry {
        outside.current = lambda (e: any) {
            anchor: any = document.getElementById(id + "-anchor");
            if anchor and not anchor.contains(e.target) { open = False; }
        };
        window.addEventListener("pointerdown", outside.current);
    }
    can with exit { window.removeEventListener("pointerdown", outside.current); }
    browser: any = window;
    def freshness(source: any) -> str {
        expires = Date.parse(source.get("expires_at", ""));
        checked = Date.parse(source.get("checked_at", ""));
        if browser.Number.isNaN(expires) or browser.Number.isNaN(checked) { return "Freshness needs confirmation"; }
        if checked > Date.now() { return "Checked time is in the future"; }
        return "Source expired" if expires <= Date.now() else "Within recorded validity period";
    }
    <div id={id + "-anchor"} className="evidence-popover-anchor" onBlur={lambda (e: any) {
        if e.relatedTarget and not e.currentTarget.contains(e.relatedTarget) { open = False; }
    }} onKeyDown={lambda (e: any) {
        if open and e.key == "Escape" { e.stopPropagation(); close(); }
    }}>
        <button id={id} type="button" className="evidence-trigger" aria-expanded={open} aria-controls={id + "-popup"}
            onClick={toggle}>Needs confirmation <span aria-hidden="true">ⓘ</span></button>
        {(<div className="evidence-popover" style={placement} role="dialog" aria-modal={False} aria-label="Why confirmation is needed" id={id + "-popup"}>
            <div className="itinerary-panel-heading"><h3>What needs checking?</h3>
                <button id={id + "-close"} type="button" className="itinerary-chip" aria-label="Close confirmation details" onClick={close}>×</button></div>
            <ul className="evidence-checks">{[<li key={str(index)}>
                <strong>{check["code"].replace("_", " ")}</strong><p>{check["message"]}</p>
            </li> for (index, check) in enumerate(checks)]}</ul>
            <h4>Recorded sources</h4>
            {(<p>No source is recorded for the affected items.</p>) if len(sources) == 0 else None}
            {[<div className="evidence-source" key={str(index)}>
                <p>{source["source"]}</p>
                <small>{"Checked " + (source.get("checked_at") or "time unavailable")}</small>
                <small>{"Expires " + (source.get("expires_at") or "time unavailable")}</small>
                <strong>{freshness(source)}</strong>
            </div> for (index, source) in enumerate(sources)]}
            <button type="button" className="itinerary-chip" onClick={lambda { open = False; onFacts(); }}>{actionLabel}</button>
        </div>) if open else None}
    </div>
}
