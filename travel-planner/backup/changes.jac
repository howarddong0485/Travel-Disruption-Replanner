"""Read-only change metrics for synthetic proposals; no ranking or cash-flow claim."""
import from dataclasses { asdict }
import from datetime { datetime, timedelta }
import from backup.validation { evidence_problem, instant }
import from backup.validation_models { Replacement, ScheduledItem, TripContext }

def minor(value: any) -> bool {
    return type(value) is int and value >= 0;
}

def quote_problem(item: ScheduledItem, trip: TripContext, now: datetime) -> str {
    profile = trip.profile;
    if profile.adults is None or type(profile.adults) is not int or profile.adults < 1 or not profile.complete or
        any(type(age) is not int or not 0 <= age <= 17 for age in profile.child_ages) {
        return "Traveler count or profile is incomplete";
    }
    if trip.currency != "USD" or item.currency != trip.currency {
        return "A comparable USD quote is unavailable";
    }
    if evidence_problem(item.evidence, now) { return "Current quote evidence is unavailable"; }
    if not minor(item.cost_minor) { return "A nonnegative whole-party quote is unavailable"; }
    if type(item.party_size) is not int or item.party_size != profile.adults + len(profile.child_ages) or
        item.fees_included is not True { return "Whole-party pricing including fees is unconfirmed"; }
    if item.paid_minor is None or item.cost_minor is None or not minor(item.paid_minor) or item.paid_minor > item.cost_minor {
        return "Payment history is incomplete or inconsistent";
    }
    return "";
}

def describe_changes(trip: TripContext, replacement: Replacement,
    validation: dict[str, any], now: datetime) -> dict[str, any] | None {
    if now.utcoffset() is None { raise ValueError("Change metrics need an aware clock"); }
    originals = [item for item in trip.items if item.id == replacement.replaces_id];
    if len(originals) != 1 or replacement.item.id != replacement.replaces_id or
        len({item.id for item in trip.items}) != len(trip.items) { return None; }
    old = originals[0]; updated = replacement.item;
    reasons: list[str] = [];
    baseline: int | None = None;
    baseline_problems: list[str] = [];
    for item in trip.items {
        problem = quote_problem(item, trip, now);
        if problem { baseline_problems.append(item.title + ": " + problem); }
    }
    if not minor(trip.reserve_minor) { baseline_problems.append("Reserve is incomplete or invalid"); }
    if not baseline_problems { baseline = sum(item.cost_minor for item in trip.items) + trip.reserve_minor; }
    else { reasons.append("Original planned total unknown. " + "; ".join(baseline_problems)); }
    # Use the validator's whole-trip accounting, never sum already-paid amounts twice.
    projected = validation["cost"]["projected_total_minor"];
    if not minor(projected) or trip.currency != "USD" { projected = None; }
    if projected is None { reasons.append("Proposed total is unknown; see the validation evidence reasons."); }
    budget = trip.budget_minor if minor(trip.budget_minor) else None;
    if budget is None { reasons.append("Budget remaining is unknown because no valid budget is supplied."); }
    delta = projected - baseline if projected is not None and baseline is not None else None;
    headroom = budget - projected if budget is not None and projected is not None else None;
    old_quote = old.cost_minor if not quote_problem(old, trip, now) else None;
    new_quote = updated.cost_minor if not quote_problem(updated, trip, now) else None;

    schedule: dict[str, any] = {"original_start": asdict(old.start), "original_end": asdict(old.end),
        "proposed_start": asdict(updated.start), "proposed_end": asdict(updated.end),
        "start_shift_minutes": None, "end_shift_minutes": None, "duration_delta_minutes": None};
    try {
        if evidence_problem(old.evidence, now) or evidence_problem(updated.evidence, now) {
            raise ValueError("Current timing evidence is unavailable");
        }
        a = instant(old.start); b = instant(old.end);
        c = instant(updated.start); d = instant(updated.end);
        if b <= a or d <= c { raise ValueError("An event has a nonpositive duration"); }
        schedule["start_shift_minutes"] = (c - a).total_seconds() / 60;
        schedule["end_shift_minutes"] = (d - b).total_seconds() / 60;
        schedule["duration_delta_minutes"] = ((d - c) - (b - a)).total_seconds() / 60;
    } except ValueError as exc { reasons.append("Timing change unknown. " + str(exc)); }

    deadlines = [now + timedelta(minutes=15)];
    # Original target evidence also supports the baseline/delta, although it is
    # absent from the proposed itinerary and its validation lifetime.
    for item in (*trip.items, updated) {
        if item.evidence is not None and not evidence_problem(item.evidence, now) {
            deadlines.append(datetime.fromisoformat(item.evidence.expires_at));
        }
    }
    return {"version": "backup-changes-v1", "scope": "standalone_fixture",
        "checked_at": now.isoformat(), "expires_at": min(deadlines).isoformat(),
        "item_id": old.id, "original_title": old.title, "proposed_title": updated.title,
        "unchanged_item_count": len(trip.items) - 1,
        "cost": {"currency": "USD", "original_total_minor": baseline,
            "proposed_total_minor": projected, "delta_minor": delta,
            "budget_remaining_minor": headroom, "original_quote_minor": old_quote,
            "replacement_quote_minor": new_quote}, "schedule": schedule, "unknown_reasons": reasons,
        "notice": "Planned totals include reserve and retained original payments, with no refund assumed. "
            "The difference is not an amount due now. The original plan may be disrupted or infeasible. "
            "Metrics do not rank alternatives or override validation."};
}
