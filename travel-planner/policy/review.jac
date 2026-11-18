"""Traveler-facing cancellation review, derived only from evidenced contracts."""
import from datetime { datetime }
import from schema.bundle { TripBundle, _policy as parse_policy, _evidence as parse_source }
import from schema.itinerary { ItineraryNode }
import from schema.roam { graph_from_roam }
import from schema.common { to_plain, format_money }
import from policy.cancellation { evaluate_cancellation }
import from backup.validation { evidence_problem, instant }
import from backup.validation_models { Evidence, Moment }

def cancellation_review(bundle: TripBundle, booking: ItineraryNode, deadlines: dict[str, str], now: datetime) -> dict[str, any] {
    row: dict[str, any] = {"item_id":booking.id, "title":booking.title, "state":"unknown", "label":"Cancellation terms need confirmation",
        "currency":booking.currency, "fee":"Unknown", "refund":"Unknown", "refund_form":"unknown", "deadline":"Not supplied", "zone":booking.tz,
        "sources":[], "unknowns":[], "requires_confirmation":True, "reviewed_at":now.isoformat(), "deadline_at":""};
    policy = bundle.policy(booking.policy_id) if booking.policy_id else None;
    if policy is None { row["unknowns"] = ["No cancellation policy is recorded for this item."]; return row; }
    status = evaluate_cancellation(policy, booking, now);
    unknowns = list(status.unknowns);
    try {
        instant(Moment(booking.start_local, booking.tz));
        for tier in policy.tiers { if tier.deadline_local { instant(Moment(tier.deadline_local, policy.tz)); } }
    } except ValueError { unknowns.append("Service time or policy deadline needs an unambiguous local time and timezone."); }
    if policy.currency != booking.currency { unknowns.append("Policy and booking currencies differ; no exchange rate is assumed."); }
    sources = {e.id:e for e in bundle.evidence};
    for key in status.evidence_ids {
        proof = sources.get(key);
        if proof is None { unknowns.append("Applicable policy excerpt is missing."); continue; }
        if not proof.excerpt.strip() { unknowns.append("Applicable policy excerpt is missing."); }
        expires = deadlines.get(key, ""); problem = evidence_problem(Evidence(proof.source_ref, proof.retrieved_at, expires), now);
        if problem { unknowns.append("Policy evidence is missing, expired or not yet valid."); }
        row["sources"].append({"excerpt":proof.excerpt, "source":proof.source_ref, "checked_at":proof.retrieved_at, "expires_at":expires, "current":not bool(problem)});
    }
    if not status.evidence_ids { unknowns.append("No applicable, evidenced cancellation clause is available."); }
    if status.refund_form.value == "unknown" { unknowns.append("Refund form is unknown."); }
    if not row["sources"] and policy.source_text {
        row["sources"].append({"excerpt":policy.source_text, "source":"Supplied terms; applicable clause not verified", "checked_at":policy.retrieved_at, "expires_at":"", "current":False});
    }
    row["unknowns"] = list(dict.fromkeys(unknowns));
    row["deadline"] = status.next_deadline_local or "Not supplied; confirm the applicable window";
    row["deadline_at"] = status.next_deadline_local;
    row["zone"] = policy.tz;
    if not unknowns {
        row["state"] = status.state.value;
        row["label"] = {"free_cancel_open":"Free cancellation within the stated window", "partial_refund":"Fee-qualified or partial refund",
            "no_refund":"Refund explicitly excluded", "service_started":"Service started; no-show terms apply"}.get(status.state.value, "Cancellation terms need confirmation");
        row["fee"] = format_money(status.fee_if_cancel_now_minor, status.currency);
        row["refund"] = format_money(status.refund_if_cancel_now_minor, status.currency);
        row["refund_form"] = status.refund_form.value;
        row["requires_confirmation"] = status.state.value == "unknown";
    }
    return row;
}

def saved_policy_reviews(state: dict[str, any], facts: dict[str, any], now: datetime) -> list[dict[str, any]] {
    itinerary = graph_from_roam(state["trip"], state["items"], facts.get("zone", ""));
    for booking in itinerary.nodes {
        detail = facts.get("items", {}).get(booking.id, {});
        item = next(i for i in state["items"] if i["id"] == booking.id);
        booking.tz = (item.get("journey") or {}).get("zone") or detail.get("zone") or booking.tz;
        booking.policy_id = detail.get("policy_id", "");
    }
    ids = {booking.id for booking in itinerary.nodes};
    # Ordinary chats may have no timezone or policy evidence yet. Review those
    # unknowns without treating this read-only adapter as a validated trip.
    bundle = TripBundle(itinerary=itinerary,
        policies=[parse_policy(p) for p in facts.get("policies", []) if p["booking_node_id"] in ids],
        evidence=[parse_source({"excerpt":"", **e}) for e in facts.get("evidence", [])]);
    return [cancellation_review(bundle, booking, facts.get("evidence_deadlines", {}), now) for booking in bundle.itinerary.nodes];
}
