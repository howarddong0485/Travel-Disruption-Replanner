"""Independent synthetic inventory refresh. Never applies or books a proposal."""
import from copy { deepcopy }
import from dataclasses { asdict, replace }
import from datetime { datetime, timedelta }
import from hashlib { sha256 }
import json;
import uuid;
import from backup.validation { validate_replacement, evidence_problem }
import from backup.validation_models { Evidence, Replacement, RiskContext, TripContext }

glob INVENTORY_CHANGES = ("unchanged", "price_increase", "sold_out", "all_sold_out",
    "expired_evidence", "provider_failure", "partial_failure");

def observe(candidate: Replacement, change: str, now: datetime) -> Replacement {
    # This deterministic adapter stands in for a provider. No network or real inventory.
    if change == "provider_failure" or (change == "partial_failure" and candidate.id == "plan-b") {
        raise TimeoutError("Synthetic provider timeout");
    }
    fresh = Evidence("fixture://inventory/refresh/" + change + "/" + candidate.id,
        now.isoformat(), (now + timedelta(minutes=15)).isoformat());
    item = replace(candidate.item, evidence=fresh);
    if change == "price_increase" and candidate.id == "plan-b" and item.cost_minor is not None {
        item = replace(item, cost_minor=item.cost_minor + 20000);
    }
    if change == "all_sold_out" or (change == "sold_out" and candidate.id == "plan-b") {
        item = replace(item, availability="unavailable");
    }
    if change == "expired_evidence" and candidate.id == "plan-b" {
        item = replace(item, evidence=replace(fresh,
            checked_at=(now - timedelta(minutes=16)).isoformat(), expires_at=now.isoformat()));
    }
    # A refresh may confirm an existing estimate, but cannot invent missing routing facts.
    edges = `tuple(replace(edge, evidence=fresh) if edge.evidence is not None else edge
        for edge in candidate.transfers);
    return replace(candidate, item=item, transfers=edges);
}

def refresh_alternatives(trip: TripContext, risk: RiskContext,
    candidates: tuple[Replacement, ...], change: str, now: datetime) -> dict[str, any] {
    if now.utcoffset() is None { raise ValueError("Refresh clock needs a UTC offset"); }
    if change not in INVENTORY_CHANGES { raise ValueError("Choose a supported inventory change"); }
    (trip, risk, candidates) = deepcopy((trip, risk, candidates));
    results: list[dict[str, any]] = [];
    deadlines = [now + timedelta(minutes=15)];
    for candidate in candidates {
        failed = False;
        try { updated = observe(candidate, change, now); }
        except TimeoutError {
            failed = True;
            # Do not reuse a previously passing quote, policy or route after fetch failure.
            updated = replace(candidate, item=replace(candidate.item, evidence=None,
                cost_minor=None, availability="unknown", hours=None, eligibility={},
                child_min_age=None, child_max_age=None),
                transfers=`tuple(replace(edge, evidence=None, minutes=None) for edge in candidate.transfers));
        }
        result = validate_replacement(trip, risk, updated, now);
        result["refresh_state"] = "provider_error" if failed else "received";
        if failed {
            result["checks"].append({"code": "provider_refresh", "status": "unknown",
                "message": "Inventory provider did not respond. Previous evidence was discarded; retry refresh.",
                "item_ids": [candidate.replaces_id]});
        }
        observations = [risk.evidence, updated.item.evidence];
        observations.extend(item.evidence for item in trip.items if item.id != candidate.replaces_id);
        observations.extend(edge.evidence for edge in trip.transfers
            if candidate.replaces_id not in (edge.from_id, edge.to_id));
        observations.extend(edge.evidence for edge in updated.transfers);
        result["valid_until"] = None;
        if result["status"] == "passed_fixture_checks" {
            # Unchanged itinerary/risk evidence is never renewed by the candidate adapter.
            expiry = min(datetime.fromisoformat(e.expires_at) for e in observations
                if e is not None and not evidence_problem(e, now));
            result["valid_until"] = expiry.isoformat();
            deadlines.append(expiry);
        }
        payload = {"trip": asdict(trip), "risk": asdict(risk), "candidate": asdict(updated),
            "change": change, "provider_error": failed, "checked_at": now.isoformat()};
        result["evidence_fingerprint"] = sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest();
        result["source"] = updated.item.evidence.source if updated.item.evidence is not None else "";
        result["evidence_expires_at"] = updated.item.evidence.expires_at if updated.item.evidence is not None else None;
        results.append(result);
    }
    summary = {status: sum(r["status"] == status for r in results)
        for status in ("passed_fixture_checks", "invalid", "needs_validation")};
    return {"results": results, "summary": summary, "inventory_change": change,
        "refresh_id": str(uuid.uuid4()), "checked_at": now.isoformat(),
        "expires_at": min(deadlines).isoformat(), "scope": "standalone_fixture",
        "message": "Fresh synthetic checks are shown below. No saved trip was changed."
            if summary["passed_fixture_checks"] > 0 else
            "No alternative currently passes all fixture checks. Review the reasons or refresh again."};
}
