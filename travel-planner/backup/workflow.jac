"""One search/validate/refresh pipeline for sample and saved-trip backup inputs."""
import from datetime { datetime }
import from backup.planner { screen }
import from backup.validation { validate_replacement }
import from backup.validation_models { Replacement, RiskContext, TripContext }
import from backup.refresh { refresh_alternatives }
import from tools.alternatives.mock { search }
import from tools.alternatives.details { materialize }
import from backup.selection { select_options }

def discover(trip: TripContext, risk: RiskContext, destination: str, now: datetime,
    scenario: str = "", sample: bool = True, expanded: bool = False) -> tuple[tuple[Replacement, ...], dict[str, any]] {
    if now.utcoffset() is None { raise ValueError("Search clock needs a UTC offset"); }
    targets = [i for i in trip.items if i.id == risk.item_id];
    if len(targets) != 1 or risk.trip_id != trip.id { raise ValueError("Risk target must belong to this trip"); }
    if risk.trigger not in ("rain", "arrival_delay") { raise ValueError("Choose rain or arrival_delay"); }
    category = "activity" if risk.trigger == "rain" else "food";
    if targets[0].category != category { raise ValueError("Risk trigger does not match the target category"); }
    found = search(destination, category, now, expanded=expanded);
    candidates: list[Replacement] = []; exclusions: list[dict[str, str]] = []; seen: set[str] = set();
    for item in found {
        problem = "Duplicate inventory ID" if item.id in seen else screen(item, trip.currency, now);
        seen.add(item.id);
        if not problem and not expanded and len(candidates) >= 2 { problem = "Legacy fixture candidate limit reached"; }
        if problem { exclusions.append({"provider_id": item.id, "reason": problem}); continue; }
        try { candidates.append(materialize(item, trip, risk, now, scenario, sample)); }
        except ValueError as exc { exclusions.append({"provider_id": item.id, "reason": str(exc)}); }
    }
    return (tuple(candidates), {"destination": destination, "target_id": risk.item_id,
        "trigger": risk.trigger, "searched_count": len(found), "selected_count": len(candidates), "evaluated_count": len(candidates),
        "provider_ids": [c.provider_id for c in candidates], "exclusions": exclusions,
        "search_sources": [{"provider_id": c.id, "source": c.source_ref,
            "checked_at": c.checked_at, "expires_at": c.expires_at} for c in found]});
}

def run_workflow(trip: TripContext, risk: RiskContext, destination: str,
    inventory_change: str, now: datetime, scenario: str = "", sample: bool = True, expanded: bool = True) -> dict[str, any] {
    (candidates, trace) = discover(trip, risk, destination, now, scenario, sample, expanded);
    initial = [validate_replacement(trip, risk, c, now) for c in candidates];
    result_data = refresh_alternatives(trip, risk, candidates, inventory_change, now);
    trace["initial_checks"] = [{"candidate_id": r["candidate_id"], "provider_id": c.provider_id,
        "status": r["status"], "checks": [check for check in r["checks"] if check["status"] != "pass"]}
        for (c, r) in zip(candidates, initial)];
    result_data["pipeline"] = trace;
    if expanded {
        result_data = select_options(result_data);
        result_data["pipeline"]["selected_count"] = len(result_data["results"]);
        result_data["pipeline"]["selected_provider_ids"] = result_data["selection"]["selected_provider_ids"];
    }
    if not candidates {
        result_data["message"] = "No matching supported inventory. The synthetic search covers Boston activities and dining in USD.";
    }
    return result_data;
}
