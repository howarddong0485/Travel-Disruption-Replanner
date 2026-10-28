"""Read-only whole-itinerary validation for Gehao Dong's standalone fixtures.

This is a local reference implementation, not the project's shared validator.
No database, provider, LLM, comparison score, booking or patch application.
"""
import from copy { deepcopy }
import from dataclasses { asdict }
import from datetime { date, datetime, timedelta, timezone }
import from hashlib { sha256 }
import json;
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }
import from backup.validation_models {
    Evidence,
    Moment,
    Replacement,
    RiskContext,
    TripContext
}
glob UTC = timezone.utc;
"""A missing/ambiguous fact is unresolved rather than a constraint failure."""
class MissingFact(ValueError) {}
"""Resolve an IANA local time; never guess DST folds or normalize a gap."""
def instant(moment: Moment) -> datetime {
    if (not moment.local or not moment.zone) {
        raise MissingFact("Local time or IANA timezone is missing");
    }
    try {
        local = datetime.fromisoformat(moment.local);
        zone = ZoneInfo(moment.zone);
    } except (ValueError, ZoneInfoNotFoundError, TypeError) as exc {
        raise ValueError("Invalid local time or IANA timezone") from exc;
    }
    if (local.tzinfo is not None) {
        raise ValueError("Use a local time without an offset plus its IANA timezone");
    }
    if (
        (moment.fold is not None)
        and ((`type(moment.fold) is not int) or (moment.fold not in (0, 1)))
    ) {
        raise ValueError("DST fold must be 0 or 1");
    }
    possibilities = {};
    for fold in (0, 1) {
        value = local.replace(tzinfo=zone, fold=fold).astimezone(UTC);
        if (value.astimezone(zone).replace(tzinfo=None) == local) {
            possibilities[fold] = value;
        }
    }
    if not possibilities {
        raise ValueError("This local time does not exist because of a DST transition");
    }
    if ((len(`set(possibilities.values())) > 1) and (moment.fold is None)) {
        raise MissingFact("Ambiguous DST time: specify its first or second occurrence");
    }
    return possibilities[moment.fold if (moment.fold is not None) else 0];
}
def evidence_problem(evidence: (Evidence | None), now: datetime) -> str {
    if ((evidence is None) or not evidence.source.strip()) {
        return "Source evidence is missing";
    }
    try {
        checked = datetime.fromisoformat(evidence.checked_at);
        expires = datetime.fromisoformat(evidence.expires_at);
        if ((checked.utcoffset() is None) or (expires.utcoffset() is None)) {
            return "Evidence timestamps need UTC offsets";
        }
        if ((checked > now) or (expires <= now) or (expires <= checked)) {
            return "Evidence is expired or has an invalid observation window";
        }
    } except (ValueError, TypeError) {
        return "Evidence timestamps are invalid";
    }
    return "";
}
def _minor(value: any) -> bool {
    return ((`type(value) is int) and (value >= 0));
}
def validate_replacement(
    trip: TripContext, risk: RiskContext, replacement: Replacement, now: datetime
) -> dict[str, any] {
    if (now.utcoffset() is None) {
        raise ValueError("Validation clock needs a UTC offset");
    }
    # Construct proposals from copies without mutating caller-owned inputs.
    (trip, risk, replacement) = deepcopy((trip, risk, replacement));
    fingerprint = sha256(json.dumps(asdict(trip), sort_keys=True).encode()).hexdigest();
    checks = [];
    def record(code: any, status: any, message: any, *ids: any) -> any {
        checks.append(
            {"code": code, "status": status, "message": message, "item_ids": `list(ids)}
        );
    }
    def resolve(moment: any, code: any, item_id: any) -> any {
        try {
            return instant(moment);
        } except MissingFact as exc {
            record(code, "unknown", str(exc), item_id);
        } except ValueError as exc {
            record(code, "fail", str(exc), item_id);
        }
        return None;
    }
    def evidence(e: any, code: any, *ids: any) -> any {
        problem = evidence_problem(e, now);
        record(
            code,
            "unknown" if problem else "pass",
            (problem or "Fresh source evidence"),
            *ids
        );
        return not problem;
    }
    def finish(total: any = None, retained: any = None) -> any {
        statuses = {check["status"] for check in checks};
        status = "invalid"
            if ("fail" in statuses)
            else "needs_validation"
                if ("unknown" in statuses)
                else "passed_fixture_checks";
        return {
            "candidate_id": replacement.id,
            "title": replacement.item.title,
            "status": status,
            "scope": "standalone_fixture",
            "base_snapshot": fingerprint,
            "checked_at": now.isoformat(),
            "checks": checks,
            "cost": {
                "currency": trip.currency,
                "projected_total_minor": total,
                "retained_original_payment_minor": retained,
                "reserve_minor": trip.reserve_minor,
                "budget_minor": trip.budget_minor
            },
            "proposed_items": [asdict(item) for item in nodes],
            "notice": "Synthetic fixture validation only. No shared-agent integration or booking. "
            "Paid original costs are retained; no refund is assumed."
        };
    }
    nodes = `list(trip.items);
    ids = [item.id for item in nodes];
    if (
        not ids or `any(not key.strip() for key in ids) or (len(`set(ids)) != len(ids))
    ) {
        record("item_ids", "fail", "Itinerary IDs must be nonempty and unique");
        return finish();
    }
    if (
        (replacement.replaces_id not in ids)
        or (replacement.item.id != replacement.replaces_id)
    ) {
        record(
            "replacement_scope", "fail", "Replacement must preserve an existing item ID"
        );
        return finish();
    }
    old = next(
        item
        for item in nodes
        if (item.id == replacement.replaces_id)
    );
    if (old.fixed or old.completed) {
        record(
            "protected_item", "fail", "Cannot replace a fixed or completed item", old.id
        );
        return finish();
    }
    record(
        "protected_item",
        "pass",
        "Fixed and completed itinerary items remain unchanged",
        old.id
    );
    if ((risk.trip_id != trip.id) or (risk.item_id != old.id)) {
        record(
            "risk_scope",
            "fail",
            "Risk does not refer to this trip and replacement item",
            old.id
        );
    }
    evidence(risk.evidence, "risk_evidence", old.id);
    if (risk.status != "flagged") {
        record(
            "risk_status",
            "unknown",
            "The activation risk has not been established",
            old.id
        );
    }
    if (risk.trigger not in ("rain", "arrival_delay")) {
        record("risk_trigger", "unknown", "Unsupported activation condition", old.id);
    } elif (old.category != ("activity" if risk.trigger == "rain" else "food")) {
        record(
            "risk_trigger",
            "fail",
            "Activation condition does not match the original item",
            old.id
        );
    }
    if (replacement.item.category != old.category) {
        record(
            "replacement_category",
            "fail",
            "Replacement category differs from the original",
            old.id
        );
    }
    if (replacement.item.paid_minor != 0) {
        record(
            "replacement_payment",
            "fail",
            "A proposed new purchase cannot already be paid",
            old.id
        );
    }
    nodes = [replacement.item if (item.id == old.id) else item for item in nodes];
    profile = trip.profile;
    party_size = (profile.adults if `type(profile.adults) is int else 0) + len(profile.child_ages);
    if (
        (`type(profile.adults) is not int)
        or (profile.adults < 1)
        or `any(
            ((`type(age) is not int) or not (0 <= age <= 17))
            for age in profile.child_ages
        )
    ) {
        record(
            "profile", "fail", "Party requires adults and child ages from 0 through 17"
        );
    }
    if not profile.complete {
        record("profile", "unknown", "Traveler hard requirements are incomplete");
    }
    if `any(not code.strip() for code in profile.dietary) {
        record("profile", "unknown", "A dietary requirement has no interpretable code");
    }
    try {
        (first, last) = (
            date.fromisoformat(trip.start_date),
            date.fromisoformat(trip.end_date)
        );
        if (last < first) {
            raise ValueError("Trip end precedes start");
        }
        lower = instant(Moment((first.isoformat() + "T00:00"), trip.zone));
        upper = instant(
            Moment(((last + timedelta(days=1)).isoformat() + "T00:00"), trip.zone)
        );
    } except MissingFact as exc {
        record("trip_bounds", "unknown", str(exc));
        lower = upper=None;
    } except (ValueError, TypeError) as exc {
        record("trip_bounds", "fail", str(exc));
        lower = upper=None;
    }
    times = {};
    known_costs = trip.currency == "USD";
    if not known_costs {
        record("currency", "unknown", "Standalone fixtures currently support USD only");
    }
    for item in nodes {
        if (item.category not in ("transport", "stay", "food", "activity")) {
            record(
                "category", "unknown", "Unsupported scheduled item category", item.id
            );
        }
        if (not item.blocks_time and (item.category != "stay")) {
            record(
                "blocking_time",
                "fail",
                "Only lodging reservations may be nonblocking",
                item.id
            );
        }
        fresh = evidence(item.evidence, "item_evidence", item.id);
        if (item.availability == "unavailable") {
            record("availability", "fail", "Inventory is unavailable", item.id);
        } elif (item.availability != "available") {
            record(
                "availability", "unknown", "Inventory availability is unknown", item.id
            );
        } else {
            record(
                "availability", "pass", "Available in the supplied fixture", item.id
            );
        }
        if not item.venue.strip() {
            record("location", "unknown", "Venue is missing", item.id);
        }
        begin = resolve(item.start, "schedule", item.id);
        end = resolve(item.end, "schedule", item.id);
        if ((begin is not None) and (end is not None)) {
            if (begin >= end) {
                record("schedule", "fail", "Event end must follow start", item.id);
            } else {
                times[item.id] = (begin, end);
                if ((lower is not None) and ((begin < lower) or (end > upper))) {
                    record(
                        "trip_bounds",
                        "fail",
                        "Item lies outside the trip window",
                        item.id
                    );
                } else {
                    record(
                        "schedule",
                        "pass",
                        "Scheduled interval resolved in UTC",
                        item.id
                    );
                }
            }
            if (item.hours is None) {
                record(
                    "opening_hours",
                    "unknown",
                    "Opening or operating window is missing",
                    item.id
                );
            } else {
                (contained, unknown_window) = (False, False);
                for window in item.hours {
                    left = resolve(window.start, "opening_hours", item.id);
                    right = resolve(window.end, "opening_hours", item.id);
                    if ((left is None) or (right is None)) {
                        unknown_window = True;
                    } elif (right <= left) {
                        record(
                            "opening_hours",
                            "fail",
                            "Operating window must have positive duration",
                            item.id
                        );
                    } elif ((left <= begin) and (end <= right)) {
                        contained = True;
                    }
                }
                if not contained {
                    record(
                        "opening_hours",
                        "unknown" if unknown_window else "fail",
                        "No evidenced operating window covers the whole visit",
                        item.id
                    );
                } elif fresh {
                    record(
                        "opening_hours",
                        "pass",
                        "Whole visit fits the operating window",
                        item.id
                    );
                }
            }
        }
        needs = [("dietary:" + code) for code in profile.dietary]
            if (item.category == "food")
            else [];
        if profile.pet {
            needs.append(("pet:" + profile.pet));
        }
        if profile.wheelchair {
            needs.append("accessibility:wheelchair");
        }
        if ((item.id == old.id) and (risk.trigger == "rain")) {
            needs.append("indoor");
        }
        for need in needs {
            value = item.eligibility.get(need);
            status = "unknown"
                if (not fresh or (`type(value) is not bool))
                else "pass" if value else "fail";
            record(
                "eligibility",
                status,
                need + (": evidence missing" if status == "unknown" else ": supported" if value else ": not supported"),
                item.id
            );
        }
        if profile.child_ages {
            (lo, hi) = (item.child_min_age, item.child_max_age);
            if ((lo is None) or (hi is None) or not fresh) {
                record(
                    "child_age",
                    "unknown",
                    "Child admission age evidence is missing",
                    item.id
                );
            } elif (not _minor(lo) or not _minor(hi) or (hi < lo)) {
                record(
                    "child_age", "fail", "Invalid child admission age range", item.id
                );
            } else {
                allowed = all((lo <= age <= hi) for age in profile.child_ages);
                record(
                    "child_age",
                    "pass" if allowed else "fail",
                    "Child ages fit admission limits"
                        if allowed
                        else "A child is outside admission age limits",
                    item.id
                );
            }
        }
        if (item.currency != trip.currency) {
            record(
                "currency",
                "unknown",
                "Currency mismatch: conversion evidence is absent",
                item.id
            );
            known_costs = False;
        }
        if ((item.cost_minor is None) or not fresh) {
            record("price", "unknown", "Current quote is missing", item.id);
            known_costs = False;
        } elif not _minor(item.cost_minor) {
            record(
                "price",
                "fail",
                "Quote must be nonnegative integer minor units",
                item.id
            );
            known_costs = False;
        }
        if ((item.party_size != party_size) or (item.fees_included is not True)) {
            record(
                "party_quote",
                "unknown",
                "Need a quote for the entire party including taxes/fees",
                item.id
            );
            known_costs = False;
        }
        if (item.paid_minor is None) {
            record("payment", "unknown", "Payment history is incomplete", item.id);
            known_costs = False;
        } elif (
            not _minor(item.paid_minor)
            or (_minor(item.cost_minor) and (item.paid_minor > item.cost_minor))
        ) {
            record(
                "payment",
                "fail",
                "Payment must be within the item's total quote",
                item.id
            );
            known_costs = False;
        }
    }
    if (risk.trigger == "arrival_delay") {
        if (risk.not_before is None) {
            record(
                "arrival_delay",
                "unknown",
                "Revised earliest dinner time is missing",
                old.id
            );
        } else {
            earliest = resolve(risk.not_before, "arrival_delay", old.id);
            if ((earliest is not None) and (old.id in times)) {
                ok = times[old.id][0] >= earliest;
                record(
                    "arrival_delay",
                    "pass" if ok else "fail",
                    "Dinner follows revised arrival"
                        if ok
                        else "Dinner starts before the revised arrival",
                    old.id
                );
            }
        }
    }
    scheduled = sorted(
        (
            (times[item.id][0], times[item.id][1], item)
            for item in nodes
            if (item.blocks_time and (item.id in times))
        ),
        key=lambda (value: any) { (value[0], value[1], value[2].id); }
    );
    transfers = (
        [
            `edge
            for `edge in trip.transfers
            if (old.id not in (`edge.from_id, `edge.to_id))
        ]
        + `list(replacement.transfers)
    );
    pairs = [(e.from_id, e.to_id) for e in transfers];
    if (len(`set(pairs)) != len(pairs)) {
        record("transfer", "fail", "Duplicate transfer records");
    }
    for `edge in transfers {
        if (
            (`edge.from_id not in ids)
            or (`edge.to_id not in ids)
            or (`edge.from_id == `edge.to_id)
        ) {
            record("transfer", "fail", "Transfer refers to invalid item IDs");
        }
    }
    for (previous, following) in zip(scheduled, scheduled[1:]) {
        (left, right) = (previous[2], following[2]);
        gap = (following[0] - previous[1]).total_seconds() / 60;
        record(
            "overlap",
            "fail" if (gap < 0) else "pass",
            "Scheduled events overlap"
                if (gap < 0)
                else "Scheduled events do not overlap",
            left.id,
            right.id
        );
        matches = [
            e
            for e in transfers
            if ((e.from_id == left.id) and (e.to_id == right.id))
        ];
        if not matches {
            record(
                "transfer",
                "unknown",
                "Travel-time evidence between these venues is missing",
                left.id,
                right.id
            );
            continue;
        }
        `edge = matches[0];
        if ((`edge.from_venue != left.venue) or (`edge.to_venue != right.venue)) {
            record(
                "transfer",
                "unknown",
                "Travel estimate is for different venues",
                left.id,
                right.id
            );
        } elif evidence(`edge.evidence, "transfer_evidence", left.id, right.id) {
            if (`edge.minutes is None) {
                record(
                    "transfer",
                    "unknown",
                    "Travel duration is unknown",
                    left.id,
                    right.id
                );
            } elif not _minor(`edge.minutes) {
                record(
                    "transfer",
                    "fail",
                    "Travel minutes must be a nonnegative integer",
                    left.id,
                    right.id
                );
            } else {
                record(
                    "transfer",
                    "pass" if (gap >= `edge.minutes) else "fail",
                    "Travel buffer fits"
                        if (gap >= `edge.minutes)
                        else "Not enough time to reach the next venue",
                    left.id,
                    right.id
                );
            }
        }
    }
    remaining = {key: `set() for key in ids};
    for `edge in trip.dependencies {
        if (
            (`edge.from_id not in ids)
            or (`edge.to_id not in ids)
            or not _minor(`edge.buffer_minutes)
        ) {
            record("dependency", "fail", "Invalid dependency reference or buffer");
            continue;
        }
        remaining[`edge.to_id].add(`edge.from_id);
        if ((`edge.from_id in times) and (`edge.to_id in times)) {
            fits = (
                (times[`edge.from_id][1] + timedelta(minutes=`edge.buffer_minutes))
                <= times[`edge.to_id][0]
            );
            record(
                "dependency",
                "pass" if fits else "fail",
                "Dependency boundary fits" if fits else "Dependency boundary violated",
                `edge.from_id,
                `edge.to_id
            );
        }
    }
    while remaining {
        ready = {
            key
            for (key, deps) in remaining.items()
            if not deps
        };
        if not ready {
            record("dependency_cycle", "fail", "Dependencies contain a cycle");
            break;
        }
        remaining = {
            key: (deps - ready)
            for (key, deps) in remaining.items()
            if (key not in ready)
        };
    }
    retained = old.paid_minor;
    if (retained is None) {
        record("original_payment", "unknown", "Original payment amount is unknown");
        known_costs = False;
    } elif (
        not _minor(retained)
        or (
            (old.cost_minor is not None)
            and _minor(old.cost_minor)
            and (retained > old.cost_minor)
        )
    ) {
        record("original_payment", "fail", "Invalid original payment amount");
        known_costs = False;
    }
    if ((old.currency != trip.currency) and (retained != 0)) {
        record("original_payment", "unknown", "Paid original has a different currency");
        known_costs = False;
    }
    if not _minor(trip.reserve_minor) {
        record("reserve", "fail", "Reserve must be nonnegative integer minor units");
        known_costs = False;
    }
    total = (sum(item.cost_minor for item in nodes) + retained + trip.reserve_minor)
        if known_costs
        else None;
    if (trip.budget_minor is None) {
        record("budget", "unknown", "Trip budget is not supplied");
    } elif not _minor(trip.budget_minor) {
        record("budget", "fail", "Budget must be nonnegative integer minor units");
    } elif (total is None) {
        record("budget", "unknown", "Cannot calculate a supported full-trip cost");
    } else {
        record(
            "budget",
            "pass" if (total <= trip.budget_minor) else "fail",
            f"Full trip including reserve and retained payment: {trip.currency} {total} minor units; budget {trip.budget_minor}"
        );
    }
    return finish(total, retained);
}
