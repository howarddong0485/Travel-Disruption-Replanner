"""Validate a complete multi-node alternative using P1 and the whole-trip checks."""
import from dataclasses { replace, asdict }
import from datetime { datetime }
import from backup.validation { validate_replacement, evidence_problem }
import from backup.validation_models { TripContext, RiskContext, Replacement }
import from tools.alternatives.catalog { routes }

def validate_plan(trip: TripContext, risks: tuple[RiskContext, ...], replacements: tuple[Replacement, ...], now: datetime) -> dict[str, any] {
    originals = {item.id: item for item in trip.items};
    ids = [candidate.replaces_id for candidate in replacements];
    if not ids or len(set(ids)) != len(ids) or set(ids) - set(originals) { raise ValueError("Plan must replace distinct existing nodes"); }
    if len(risks) != len(replacements) { raise ValueError("Every changed node needs its activation context"); }
    changed = {candidate.replaces_id: candidate.item for candidate in replacements};
    nodes = tuple(changed.get(item.id, item) for item in trip.items);
    try { travel = routes(trip, nodes, now); } except ValueError { travel = trip.transfers; }
    reports = [];
    for (candidate, risk) in zip(replacements, risks) {
        others = {other.replaces_id: other.item for other in replacements if other.replaces_id != candidate.replaces_id};
        retained_others = [originals[other.replaces_id].paid_minor for other in replacements
            if other.replaces_id != candidate.replaces_id and other.action == "replace"];
        extra = sum(value for value in retained_others if type(value) is int);
        extra_lines = list(trip.extra_items) + [{"id": "retained-other:" + other.replaces_id, "trip_id": trip.id, "title": "Retained original payment",
            "category": "expense", "cost_cents": originals[other.replaces_id].paid_minor, "paid": True, "done": False} for other in replacements
            if other.replaces_id != candidate.replaces_id and other.action == "replace" and type(originals[other.replaces_id].paid_minor) is int];
        base = replace(trip, items=tuple(others.get(item.id, item) for item in trip.items),
            transfers=travel, extra_cost_minor=trip.extra_cost_minor + extra, extra_items=tuple(extra_lines));
        checked = replace(candidate, transfers=tuple(edge for edge in travel if candidate.replaces_id in (edge.from_id, edge.to_id)));
        checked_result = validate_replacement(base, risk, checked, now);
        for other in replacements {
            original = originals[other.replaces_id];
            if original.fixed or original.completed {
                checked_result["checks"].append({"code": "protected_item", "status": "fail", "message": "Plan changes a fixed or completed node", "item_ids": [original.id]});
            }
        }
        if any(value is None for value in retained_others) {
            checked_result["checks"].append({"code": "original_payment", "status": "unknown", "message": "Original payment is unknown", "item_ids": ids});
            checked_result["cost"]["projected_total_minor"] = None;
        }
        reports.append(checked_result);
    }
    checks = [check for result_data in reports for check in result_data["checks"]];
    status = "invalid" if any(c["status"] == "fail" for c in checks) else "needs_validation" if any(c["status"] == "unknown" for c in checks) else "valid";
    deadlines = [];
    supporting = [item.evidence for item in nodes] + [item.evidence for item in trip.items] + [risk.evidence for risk in risks] + [edge.evidence for edge in travel];
    for source in supporting {
        if source is not None and not evidence_problem(source, now) { deadlines.append(datetime.fromisoformat(source.expires_at)); }
    }
    return {"status": status, "scope": "integrated_mock", "checks": checks,
        "projected_total_minor": reports[0]["cost"]["projected_total_minor"], "ledger": reports[0]["ledger"],
        "expires_at": min(deadlines).isoformat() if deadlines else now.isoformat(),
        "proposed_items": [asdict(item) for item in nodes], "transfers": [asdict(edge) for edge in travel]};
}
