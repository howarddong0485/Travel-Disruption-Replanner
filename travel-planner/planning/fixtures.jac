"""Explicit synthetic facts for repeatable integrated tests and the opt-in demo."""
import from dataclasses { asdict }
import from datetime { datetime, timedelta }
import from backup.validation_fixtures { build_fixture }
import from schema.common { to_plain }
import from profile.models { PROFILE_CONTRACT_VERSION }

def sample_state(now: datetime, scenario: str = "rain") -> tuple[dict[str, any], dict[str, any]] {
    (trip, risk, _) = build_fixture(scenario, "family", now, include_candidates=False);
    state: dict[str, any] = {"trip": {"id": trip.id, "title": "Integrated backup demo", "destination": "Boston", "currency": "USD",
        "start_date": trip.start_date, "end_date": trip.end_date, "budget_cents": trip.budget_minor, "notes": "Synthetic planning facts"},
        "items": [], "version": 1, "dependencies": [{"prerequisite_id": e.from_id, "dependent_id": e.to_id, "buffer_minutes": e.buffer_minutes} for e in trip.dependencies]};
    facts: dict[str, any] = {"contract_version": "roam.planning-context.v1", "zone": trip.zone, "reserve_minor": trip.reserve_minor,
        "profile": {"id": "family", "contract_version": PROFILE_CONTRACT_VERSION, "adults": 2, "child_ages": [8],
            "pets": [{"species": "dog", "size": "small"}], "requirements": [
                {"id": "vegetarian", "category": "dietary", "code": "vegetarian", "strength": "hard"},
                {"id": "dog", "category": "pet", "code": "dog", "strength": "hard"},
                {"id": "wheelchair", "category": "accessibility", "code": "wheelchair", "strength": "hard"}],
            "interests": ["museums"], "pace": "moderate"}, "items": {}, "transfers": [asdict(e) for e in trip.transfers],
        "evidence": [{"id": "forecast", "source_ref": "fixture://boston/weather", "excerpt": "Synthetic rain forecast",
            "retrieved_at": now.isoformat(), "origin": "mock"}], "evidence_deadlines": {"forecast": (now + timedelta(minutes=15)).isoformat()},
        "forecasts": [{"id": "rain", "area": "Boston", "tz": trip.zone, "start_local": trip.start_date + "T00:00",
            "end_local": trip.start_date + "T23:59", "condition": "rain", "evidence_id": "forecast", "precip_probability_pct": 90}],
        "place_hours": [], "manual_risks": []};
    for item in trip.items {
        state["items"].append({"id": item.id, "trip_id": trip.id, "title": item.title, "category": item.category,
            "date": item.start.local[:10], "time": item.start.local[11:], "location": item.venue, "reference": "", "notes": "",
            "cost_cents": item.cost_minor, "paid": bool(item.paid_minor), "done": item.completed,
            "duration_minutes": int((datetime.fromisoformat(item.end.local) - datetime.fromisoformat(item.start.local)).total_seconds() / 60),
            "latest_start": "", "fixed": item.fixed, "protected": item.fixed or item.completed});
        # Preserve the actual amount paid, not a fictional partial-payment value in Roam's boolean model.
        if item.paid_minor { state["items"][-1]["paid"] = False; }
        facts["items"][item.id] = {"zone": item.start.zone, "end": asdict(item.end), "evidence": asdict(item.evidence),
            "availability": item.availability, "hours": [asdict(w) for w in item.hours], "eligibility": dict(item.eligibility),
            "party_size": item.party_size, "fees_included": True, "child_min_age": 0, "child_max_age": 17,
            "tags": ["outdoor"] if item.id == "activity" else ["indoor"]};
        facts["place_hours"].append({"node_id": item.id, "date": trip.start_date, "evidence_id": "forecast", "open_local": "00:00", "close_local": "23:59"});
    }
    # Ticket terms for the paid garden visit, so alternatives that replace it can
    # show what cancelling costs: free until 24 hours before entry, then a fee.
    terms = ("Tickets can be cancelled for a full refund up to 24 hours before entry. "
        + "Later cancellations are refunded minus a USD 5.00 fee. Missed entries are not refunded.");
    facts["items"]["activity"]["policy_id"] = "garden-ticket-terms";
    facts["evidence"].append({"id": "garden-ticket-terms", "source_ref": "fixture://boston/garden-ticket-terms",
        "excerpt": terms, "retrieved_at": now.isoformat(), "origin": "mock"});
    facts["evidence_deadlines"]["garden-ticket-terms"] = (now + timedelta(minutes=15)).isoformat();
    facts["policies"] = [{"id": "garden-ticket-terms", "booking_node_id": "activity", "scope": "Garden entry tickets, whole party",
        "tz": trip.zone, "currency": "USD", "retrieved_at": now.isoformat(), "source_text": terms, "origin": "mock",
        "tiers": [{"evidence_id": "garden-ticket-terms", "hours_before_start": 24, "refund_percent": 100, "fee_minor": 0, "refund_form": "cash"},
            {"evidence_id": "garden-ticket-terms", "refund_percent": 100, "fee_minor": 500, "refund_form": "cash"}],
        "no_show_refund_percent": 0, "no_show_evidence_id": "garden-ticket-terms"}];
    if scenario == "arrival_delay" {
        facts["manual_risks"] = [{"id": "reported-arrival-delay", "category": "timing", "node_ids": ["dinner"],
            "summary": "Traveler-reported delayed arrival", "evidence": asdict(risk.evidence), "not_before": asdict(risk.not_before)}];
    }
    return (state, facts);
}
