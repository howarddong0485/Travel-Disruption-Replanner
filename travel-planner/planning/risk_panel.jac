"""Traveler-facing risk panel: confirmed risks by severity, each with what to do next.

Risks that can't be confirmed yet (missing or expired information) are listed
separately, so an unknown is never presented as safe or as a confirmed problem.
"""

glob SEVERITY_ORDER: dict[str, int] = {"high": 0, "medium": 1, "low": 2};
glob SEVERITY_LABELS: dict[str, str] = {"high": "High", "medium": "Medium", "low": "Low"};
glob CATEGORY_LABELS: dict[str, str] = {"weather": "Weather", "timing": "Timing", "long_drive": "Long drive",
    "opening_hours": "Opening hours", "booking_terms": "Cancellation terms", "closure": "Closure",
    "cancellation": "Cancellation", "traveler_change": "Traveler change", "budget_change": "Budget",
    "inventory_change": "Availability"};

def bySeverity(risks: any) -> any {
    return sorted(risks, key=lambda (risk: any) -> int { return SEVERITY_ORDER.get(risk["severity"], 3); });
}

def RiskRow(risk: any, titles: any, checked: bool, disabled: bool, onToggle: any) -> JsxElement {
    # Name the affected items only when the summary doesn't already.
    affected = [titles[key] for key in risk["node_ids"] if key in titles and titles[key] not in risk["summary"]];
    confirmed = risk["status"] == "flagged";
    expired = len(risk.get("stale_evidence_ids", [])) > 0;
    return <label className="risk-row" data-severity={risk["severity"]} data-confirmed={confirmed}>
        <input type="checkbox" checked={checked} disabled={disabled}
            onChange={lambda (e: ChangeEvent) { onToggle(risk["id"], e.target.checked); }}/>
        <span className="risk-body">
            <span className="risk-tags">
                {(<span className="risk-severity" data-severity={risk["severity"]}>{SEVERITY_LABELS.get(risk["severity"], "Unknown")}</span>) if confirmed else None}
                <span className="risk-category">{CATEGORY_LABELS.get(risk["category"], risk["category"].replace("_", " "))}</span>
                {(<span className="risk-category">Reported by you</span>) if risk.get("source") == "traveler_report" else None}
            </span>
            <strong>{risk["summary"]}</strong>
            {(<small>{"Affects: " + ", ".join(affected)}</small>) if affected else None}
            {(<span className="risk-fix">{"What to do: " + risk["mitigation"]}</span>) if risk.get("mitigation") else None}
            {(<span className="risk-why">Can't confirm yet: the information it's based on has expired. Reload or update it.</span>) if not confirmed and expired else None}
        </span>
    </label>;
}

def:pub RiskPanel(risks: any, items: any, selected: list[str], disabled: bool, onToggle: any) -> JsxElement {
    titles = {item.id: item.title for item in items};
    confirmed = bySeverity([risk for risk in risks if risk["status"] == "flagged"]);
    pending = bySeverity([risk for risk in risks if risk["status"] != "flagged"]);
    return <section className="risk-panel" aria-label="Trip risks">
        <div className="risk-panel-heading"><h4>Trip risks</h4>
            <span className="count-pill">{str(len(confirmed)) + " need attention · " + str(len(pending)) + " can't be checked yet"}</span></div>
        <p className="section-caption">Select the risks the alternatives should address.</p>
        {(<p className="risk-empty">No confirmed risks right now.</p>) if len(confirmed) == 0 else None}
        {[<RiskRow key={risk["id"]} risk={risk} titles={titles} checked={risk["id"] in selected}
            disabled={disabled} onToggle={onToggle}/> for risk in confirmed]}
        {(<details className="risk-pending"><summary>{"Can't check yet (" + str(len(pending)) + ")"}</summary>
            <p className="section-caption">These need more information before they can be confirmed. Add the missing details, then reload.</p>
            {[<RiskRow key={risk["id"]} risk={risk} titles={titles} checked={risk["id"] in selected}
                disabled={disabled} onToggle={onToggle}/> for risk in pending]}
        </details>) if len(pending) > 0 else None}
    </section>;
}
