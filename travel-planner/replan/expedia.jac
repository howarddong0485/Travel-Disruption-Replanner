"""Automatic hotel backup/replan drafts. No writes, booking, or mock fallback."""
import copy;
import from datetime { timedelta }
import from tools.alternatives.expedia { search_hotels }
import from tools.alternatives.liteapi { search_hotels as search_liteapi }
import from replan.engine { start, end, set_start, affected_ids, build_combination }
import from events.simulator { simulated_event }

def plans(state: dict[str, any], item_id: str, checkout: str, property_ids: list[str],
    occupancy: str = "2", country: str = "US", mode: str = "backup",
    kind: str = "interrupted", delay_minutes: int = 180, provider: str = "expedia",
    city: str = "", destination_country: str = "US") -> dict[str, any] {
    if provider not in ["expedia", "liteapi"] { raise ValueError("Unsupported hotel provider"); }
    if mode not in ["backup", "replan"] { raise ValueError("Choose backup or replan"); }
    matches = [i for i in state["items"] if i["id"] == item_id and i["category"] == "stay"];
    if not matches { raise ValueError("Select a hotel stay belonging to this trip"); }
    hotel = matches[0];
    if hotel["protected"] { raise ValueError("Unfix this hotel before generating replacements"); }
    start(hotel);
    if not hotel["date"] < checkout <= state["trip"]["end_date"] {
        raise ValueError("Check-out must follow the stay date and be within the trip");
    }
    event = simulated_event(state["trip"]["id"], item_id,
        kind if mode == "replan" else "interrupted", delay_minutes);
    affected = affected_ids(state, item_id);
    if len(affected) > 8 { raise ValueError("Replan up to eight connected items at a time"); }
    # Propagate the disruption before querying dates. No fictitious backup inventory is used.
    probe = {i["id"]: copy.deepcopy(i) for i in state["items"]};
    for node_id in affected {
        earliest = start(probe[node_id]);
        for edge in state["dependencies"] {
            if edge["dependent_id"] == node_id {
                earliest = max(earliest, end(probe[edge["prerequisite_id"]]) + timedelta(minutes=edge["buffer_minutes"]));
            }
        }
        if node_id == item_id and event["type"] == "delayed" {
            earliest = max(earliest, start(hotel) + timedelta(minutes=event["delay_minutes"]));
        }
        set_start(probe[node_id], earliest);
    }
    proposed_checkin = probe[item_id]["date"];
    if proposed_checkin >= checkout { raise ValueError("Disruption moves check-in past check-out. Choose a later check-out date."); }
    shopping = search_hotels(proposed_checkin, checkout, property_ids, occupancy,
        state["trip"]["currency"], country) if provider == "expedia" else search_liteapi(
            proposed_checkin, checkout, city, destination_country, occupancy, state["trip"]["currency"], country);
    proposals = []; warnings = list(shopping["exclusions"]);
    for offer in shopping["offers"] {
        candidate = {**offer, "item_id": item_id, "duration_minutes": hotel["duration_minutes"],
            "offset_minutes": 0, "location": offer["title"]};
        try {
            proposal = build_combination(state, event, affected, {item_id: offer["id"]},
                manual=True, inventory=[candidate]);
            proposal.update(title="Plan B" if not proposals else "Plan C", offer=offer,
                mock=False, mode=provider + "_" + shopping["mode"], status="needs_validation",
                validation="Passed stored itinerary schedule, dependency, fixed-item and budget checks only.",
                base_version=state["version"]);
            for change in proposal["changes"] {
                if change["backup_id"] { change["reason"] = offer.get("source", provider) + " hotel replacement for traveler review"; }
            }
            proposals.append(proposal);
            if len(proposals) == 2 { break; }
        } except ValueError as error {
            warnings.append(offer["title"] + ": " + str(error));
        }
    }
    warnings += [
        "Drafts only. Hotel-specific check-in windows, route changes and traveler eligibility require validation. Stored durations and transfer buffers are reused.",
        "Prices are whole-stay totals for one room. Refresh and revalidate the provider quote before booking. Refund eligibility for the original booking is unknown.",
        "No itinerary changes, bookings or cancellations were made. These drafts cannot be accepted through the mock-plan review endpoint."
    ];
    return {"status": "needs_validation" if proposals else "no_candidates", "mode": shopping["mode"], "provider": provider,
        "workflow": mode, "proposals": proposals, "warnings": warnings,
        "base_version": state["version"], "affected": [i["title"] for i in state["items"] if i["id"] in affected]};
}
