"""Traveler-supplied cancellation terms for saved bookings.

A traveler pastes a booking's terms. The rule-based PolicyAgent turns them into
an evidenced RefundPolicy, and only that verified policy is stored in the
planning facts. Anything the extractor cannot verify stays unknown or is sent to
review; nothing is guessed. Saving empty text removes the terms.
"""
import from copy { deepcopy }
import from datetime { datetime, timedelta }
import from schema.common { Origin, to_plain }
import from policy.agent { PolicyRequest, extract_policy }
import from planning.comparison { cancellation_terms }

glob TERMS_CATEGORIES: tuple[str, ...] = ("transport", "stay", "food", "activity");
# Pasted terms are the traveler's own record; recheck them weekly.
glob TERMS_VALID_DAYS: int = 7;

def terms_policy_id(item_id: str) -> str { return "traveler-terms:" + item_id; }

"""Current cancellation terms for every booking that has terms or a payment."""
def booking_terms(context: dict[str, any], now: datetime) -> dict[str, dict[str, any]] {
    result: dict[str, dict[str, any]] = {};
    for item in context["trip"].items {
        booking = context["bundle"].itinerary.find_node(item.id);
        if booking is None { continue; }
        policy = context["bundle"].policy(booking.policy_id) if booking.policy_id else None;
        if policy is None and not item.paid_minor { continue; }
        terms = cancellation_terms(context, item, booking, policy, now);
        terms["traveler_supplied"] = policy is not None and policy.id == terms_policy_id(item.id);
        result[item.id] = terms;
    }
    return result;
}

"""Return planning facts with this item's terms replaced, plus what the extractor reported."""
def attach_terms(context: dict[str, any], facts: dict[str, any], item_id: str, text: str,
    now: datetime) -> tuple[dict[str, any], dict[str, any]] {
    item = next((i for i in context["state"]["items"] if i["id"] == item_id), None);
    if item is None or item["category"] not in TERMS_CATEGORIES {
        raise ValueError("Choose an activity, meal, stay or transport item from this trip");
    }
    if len(text) > 20000 { raise ValueError("Paste at most 20,000 characters of terms"); }
    updated = deepcopy(facts);
    policy_id = terms_policy_id(item_id);
    removed = {p["id"] for p in updated.get("policies", []) if p["booking_node_id"] == item_id};
    cited = {tier["evidence_id"] for p in updated.get("policies", []) if p["id"] in removed for tier in p.get("tiers", [])}
        | {p.get("no_show_evidence_id", "") for p in updated.get("policies", []) if p["id"] in removed};
    updated["policies"] = [p for p in updated.get("policies", []) if p["id"] not in removed];
    still_cited = {tier["evidence_id"] for p in updated["policies"] for tier in p.get("tiers", [])}
        | {p.get("no_show_evidence_id", "") for p in updated["policies"]};
    dropped = cited - still_cited;
    updated["evidence"] = [e for e in updated.get("evidence", []) if e["id"] not in dropped];
    updated["evidence_deadlines"] = {key: value for (key, value) in updated.get("evidence_deadlines", {}).items() if key not in dropped};
    details = updated.setdefault("items", {}).setdefault(item_id, {});
    details.pop("policy_id", None);
    if not text.strip() {
        if not details { updated["items"].pop(item_id); }
        return (updated, {"removed": True, "needs_review": False, "notes": []});
    }
    booking = context["bundle"].itinerary.find_node(item_id);
    if booking is None { raise ValueError("This item can't hold cancellation terms yet"); }
    request = PolicyRequest(policy_id=policy_id, booking=booking, terms_text=text.strip(),
        source_ref="user://trip/" + context["trip_id"] + "/items/" + item_id + "/cancellation-terms",
        retrieved_at=now.isoformat(), scope="Pasted by the traveler", tz=booking.tz or updated.get("zone", ""),
        origin=Origin.USER);
    extraction = extract_policy(request);
    expires = (now + timedelta(days=TERMS_VALID_DAYS)).isoformat();
    updated["policies"].append(to_plain(extraction.policy));
    for record in extraction.evidence {
        updated["evidence"] = [e for e in updated["evidence"] if e["id"] != record.id] + [to_plain(record)];
        updated["evidence_deadlines"][record.id] = expires;
    }
    details["policy_id"] = policy_id;
    return (updated, {"removed": False, "needs_review": extraction.needs_review, "notes": list(extraction.notes)});
}
