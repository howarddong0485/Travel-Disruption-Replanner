"""Choose display alternatives only after refreshed full-trip validation."""
import from copy { deepcopy }

def select_options(source_report: dict[str, any]) -> dict[str, any] {
    data = deepcopy(source_report);
    evaluated = data["results"];
    # Preserve provider search order within each feasibility group. This is not
    # a price/preference ranking and never relaxes a failed hard requirement.
    usable = [r for r in evaluated if r["status"] == "passed_fixture_checks"];
    provisional = [r for r in evaluated if r["status"] == "needs_validation" and
        r["refresh_state"] == "received"];
    chosen = (usable + provisional)[:2];
    selected_ids = {r["provider_id"] for r in chosen};
    for (index, option) in enumerate(chosen) {
        option["display_label"] = "Plan B" if index == 0 else "Plan C";
    }
    decisions = [];
    for option in evaluated {
        reason = "selected" if option["provider_id"] in selected_ids else (
            "requirements_failed" if option["status"] == "invalid" else
            "provider_unavailable" if option["refresh_state"] != "received" else "display_limit");
        decisions.append({"provider_id": option["provider_id"], "candidate_id": option["candidate_id"],
            "status": option["status"], "reason": reason,
            "checks": [c for c in option["checks"] if c["status"] != "pass"]});
    }
    if chosen {
        outcome = "available" if usable else "needs_confirmation";
        message = "Review these alternatives. Your itinerary has not changed." if len(chosen) == 2 else
            "Only one alternative is available for this itinerary. Your itinerary has not changed.";
        if any(r["status"] == "needs_validation" for r in chosen) {
            message = "Some details still need confirmation before these alternatives can be used.";
        }
    } elif not evaluated {
        outcome = "no_inventory";
        message = "No alternatives are available for this destination and currency.";
    } elif all(r["refresh_state"] == "provider_error" for r in evaluated) {
        outcome = "provider_unavailable";
        message = "Availability could not be refreshed. Please try again.";
    } else {
        outcome = "no_feasible_options";
        failures = {c["code"] for r in evaluated for c in r["checks"] if c["status"] == "fail"};
        message = "No alternative fits the current itinerary and traveler requirements.";
        if "protected_item" in failures { message = "This item is fixed or completed and cannot be replaced."; }
        elif all(any(c["code"] == "availability" and c["status"] == "fail" for c in r["checks"]) for r in evaluated) {
            message = "All matching alternatives are currently sold out.";
        } elif all(any(c["code"] == "budget" and c["status"] == "fail" for c in r["checks"]) for r in evaluated) {
            message = "No alternative fits your trip budget. Try adjusting the budget or itinerary.";
        }
    }
    data["evaluated_options"] = evaluated;
    data["evaluated_summary"] = data["summary"];
    data["results"] = chosen;
    data["summary"] = {status: sum(r["status"] == status for r in chosen)
        for status in ("passed_fixture_checks", "invalid", "needs_validation")};
    data["selection"] = {"version": "backup-selection-v1", "outcome": outcome,
        "message": message, "selected_provider_ids": [r["provider_id"] for r in chosen],
        "evaluated_count": len(evaluated), "decisions": decisions};
    return data;
}
