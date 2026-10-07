"""Deterministic risk rules. Each returns RiskFlags citing the rule and its evidence.

When a rule cannot evaluate an item because evidence is missing, it reports an
UNRESOLVED flag instead of treating the item as safe.
"""
import from datetime { datetime, timedelta }
import from schema.common { local_to_instant, minutes_between, format_money, to_local_text }
import from schema.itinerary { ItineraryNode, NodeKind, BookingStatus, EdgeRelation }
import from schema.bundle { TripBundle }
import from schema.risk { RiskFlag, RiskCategory, Severity, FlagStatus }
import from policy.cancellation { evaluate_cancellation, CancelState }
import from risk.config { RiskConfig }

def _flag(rule_id: str, category: RiskCategory, severity: Severity, status: FlagStatus,
    node_ids: list[str], summary: str, mitigation: str, now: datetime,
    evidence_ids: list[str] = [], probability_pct: int | None = None) -> RiskFlag {
    return RiskFlag(id=rule_id + ":" + "+".join(node_ids), rule_id=rule_id, category=category,
        severity=severity, status=status, node_ids=node_ids, summary=summary,
        mitigation=mitigation, evaluated_at=now.isoformat(), evidence_ids=sorted(set(evidence_ids)),
        probability_pct=probability_pct);
}

def _active(n: ItineraryNode) -> bool {
    return n.booking_status not in [BookingStatus.CANCELLED, BookingStatus.COMPLETED];
}

def _duration(minutes: int) -> str {
    if minutes < 60 { return f"{minutes} min"; }
    return f"{minutes // 60} h {minutes % 60} min" if minutes % 60 else f"{minutes // 60} h";
}

"""Gaps between linked items that are shorter than the time needed to get from one to the next."""
def check_connections(bundle: TripBundle, config: RiskConfig, now: datetime) -> list[RiskFlag] {
    rule = "tight_connection";
    flags: list[RiskFlag] = [];
    for edge in bundle.itinerary.edges {
        if edge.relation == EdgeRelation.ALTERNATIVE { continue; }
        src = bundle.itinerary.find_node(edge.source_id);
        dst = bundle.itinerary.find_node(edge.target_id);
        if src is None or dst is None or not _active(src) or not _active(dst) { continue; }
        ids = [src.id, dst.id];
        src_end = local_to_instant(src.end_local, src.end_zone());
        dst_start = local_to_instant(dst.start_local, dst.tz);
        if src_end is None or dst_start is None {
            missing = f"end time of {src.title}" if src_end is None else f"start time of {dst.title}";
            flags.append(_flag(rule, RiskCategory.TIMING, Severity.LOW, FlagStatus.UNRESOLVED, ids,
                f"Cannot check the connection from {src.title} to {dst.title}: the {missing} is unknown.",
                "Add the missing time so the connection can be checked.", now));
            continue;
        }
        needs: list[int] = [];
        basis: list[str] = [];
        evidence = src.evidence_ids + dst.evidence_ids;
        if edge.min_transition_minutes is not None {
            needs.append(edge.min_transition_minutes);
            basis.append("stated minimum");
        }
        for est in bundle.travel_estimates {
            if est.from_node_id == src.id and est.to_node_id == dst.id {
                needs.append(est.minutes);
                basis.append(f"{est.mode} estimate");
                evidence.append(est.evidence_id);
            }
        }
        if not needs {
            fallback = config.flight_arrival_buffer_minutes if src.kind == NodeKind.FLIGHT else config.min_transfer_minutes;
            needs.append(fallback);
            basis.append("default buffer");
        }
        required = max(needs);
        gap = minutes_between(src_end, dst_start);
        if gap >= required { continue; }
        if gap < 0 {
            severity = Severity.HIGH;
            summary = f"{dst.title} starts {_duration(-gap)} before {src.title} ends.";
        } else {
            severity = Severity.HIGH if gap * 2 < required else Severity.MEDIUM;
            summary = (f"Only {_duration(gap)} between {src.title} and {dst.title}; "
                + f"about {_duration(required)} is needed ({', '.join(basis)}).");
        }
        if src.kind == NodeKind.FLIGHT { summary += " Any arrival delay makes this worse."; }
        flags.append(_flag(rule, RiskCategory.TIMING, severity, FlagStatus.FLAGGED, ids, summary,
            f"Move {dst.title} later or prepare a backup for it in case {src.title} runs late.", now, evidence));
    }
    return flags;
}

"""True or False when tags or the title say whether an activity is outdoors; None when unclear."""
def is_outdoor(n: ItineraryNode, config: RiskConfig) -> bool | None {
    tags = [t.lower() for t in n.tags];
    if "outdoor" in tags { return True; }
    if "indoor" in tags { return False; }
    title = n.title.lower();
    for word in config.outdoor_keywords { if word in title { return True; } }
    return None;
}

"""Outdoor activities whose forecast window shows a high chance of precipitation."""
def check_weather(bundle: TripBundle, config: RiskConfig, now: datetime) -> list[RiskFlag] {
    rule = "weather_exposure";
    flags: list[RiskFlag] = [];
    for n in bundle.itinerary.nodes {
        if n.kind != NodeKind.ACTIVITY or not _active(n) or is_outdoor(n, config) is not True { continue; }
        start = local_to_instant(n.start_local, n.tz);
        end = local_to_instant(n.end_local, n.tz) or start;
        if start is None or end is None {
            flags.append(_flag(rule, RiskCategory.WEATHER, Severity.LOW, FlagStatus.UNRESOLVED, [n.id],
                f"{n.title} is outdoors but has no scheduled time, so weather cannot be checked.",
                "Schedule it, then recheck the forecast.", now));
            continue;
        }
        matching = [f for f in bundle.forecasts if f.area == n.area
            and local_to_instant(f.start_local, f.tz) < max(end, start + timedelta(minutes=1))
            and local_to_instant(f.end_local, f.tz) > start];
        known = [f for f in matching if f.precip_probability_pct is not None];
        if not known {
            reason = "no forecast covers its time" if not matching else "the forecast gives no precipitation probability";
            flags.append(_flag(rule, RiskCategory.WEATHER, Severity.LOW, FlagStatus.UNRESOLVED, [n.id],
                f"{n.title} is outdoors and {reason}.",
                "Recheck the forecast closer to the date and keep an indoor alternative in mind.",
                now, [f.evidence_id for f in matching]));
            continue;
        }
        worst = known[0];
        chance = 0;
        for f in known {
            p = f.precip_probability_pct;
            if p is not None and p > chance { chance = p; worst = f; }
        }
        if chance < config.rain_probability_pct { continue; }
        severity = Severity.HIGH if chance >= config.high_rain_probability_pct else Severity.MEDIUM;
        flags.append(_flag(rule, RiskCategory.WEATHER, severity, FlagStatus.FLAGGED, [n.id],
            f"{n.title} is outdoors and the forecast shows {chance}% chance of precipitation ({worst.condition}).",
            "Prepare an indoor backup or move it to a drier time.", now,
            [f.evidence_id for f in known], chance));
    }
    return flags;
}

"""Drives longer than the configured limit."""
def check_long_drives(bundle: TripBundle, config: RiskConfig, now: datetime) -> list[RiskFlag] {
    rule = "long_drive";
    flags: list[RiskFlag] = [];
    for n in bundle.itinerary.nodes {
        if n.kind != NodeKind.DRIVE or not _active(n) { continue; }
        start = local_to_instant(n.start_local, n.tz);
        end = local_to_instant(n.end_local, n.end_zone());
        if start is None or end is None {
            flags.append(_flag(rule, RiskCategory.LONG_DRIVE, Severity.LOW, FlagStatus.UNRESOLVED, [n.id],
                f"The length of {n.title} is unknown.", "Add start and end times or a travel estimate.", now));
            continue;
        }
        minutes = minutes_between(start, end);
        if minutes <= config.long_drive_minutes { continue; }
        severity = Severity.HIGH if minutes * 2 > config.long_drive_minutes * 3 else Severity.MEDIUM;
        flags.append(_flag(rule, RiskCategory.LONG_DRIVE, severity, FlagStatus.FLAGGED, [n.id],
            f"{n.title} takes {_duration(minutes)}, over the {_duration(config.long_drive_minutes)} limit.",
            "Plan rest stops, split the drive, or consider another way to travel.", now, n.evidence_ids));
    }
    return flags;
}

"""Visits scheduled outside, or close to the end of, the place's opening hours."""
def check_opening_hours(bundle: TripBundle, config: RiskConfig, now: datetime) -> list[RiskFlag] {
    rule = "opening_hours";
    flags: list[RiskFlag] = [];
    for n in bundle.itinerary.nodes {
        if n.kind not in [NodeKind.ACTIVITY, NodeKind.FOOD] or not _active(n) or not n.start_local { continue; }
        date = n.start_local[:10];
        hours = [h for h in bundle.place_hours if h.node_id == n.id and h.date == date];
        if not hours {
            flags.append(_flag(rule, RiskCategory.OPENING_HOURS, Severity.LOW, FlagStatus.UNRESOLVED, [n.id],
                f"No opening-hours evidence for {n.title} on {date}.",
                "Confirm the hours for that date.", now));
            continue;
        }
        h = hours[0];
        if h.closed {
            flags.append(_flag(rule, RiskCategory.OPENING_HOURS, Severity.HIGH, FlagStatus.FLAGGED, [n.id],
                f"{n.title} is closed on {date}.", "Move it to another day or replace it.", now, [h.evidence_id]));
            continue;
        }
        start = local_to_instant(n.start_local, n.tz);
        end = local_to_instant(n.end_local, n.tz);
        opens = local_to_instant(f"{date}T{h.open_local}", n.tz);
        closes = local_to_instant(f"{date}T{h.close_local}", n.tz);
        if start is None or opens is None or closes is None { continue; }
        if closes <= opens { closes = closes + timedelta(days=1); }
        problem = "";
        severity = Severity.HIGH;
        if start < opens { problem = f"starts before it opens at {h.open_local}"; }
        elif start >= closes { problem = f"starts after it closes at {h.close_local}"; }
        elif end is not None and end > closes { problem = f"runs past closing at {h.close_local}"; }
        elif end is not None and minutes_between(end, closes) < config.closing_buffer_minutes {
            problem = f"ends only {_duration(minutes_between(end, closes))} before closing at {h.close_local}";
            severity = Severity.LOW;
        }
        if not problem { continue; }
        flags.append(_flag(rule, RiskCategory.OPENING_HOURS, severity, FlagStatus.FLAGGED, [n.id],
            f"{n.title} {problem}.", "Shift the visit inside opening hours or shorten it.", now, [h.evidence_id]));
    }
    return flags;
}

"""Booked items whose cancellation terms are restrictive, about to tighten, or unknown."""
def check_booking_terms(bundle: TripBundle, config: RiskConfig, now: datetime) -> list[RiskFlag] {
    rule = "booking_terms";
    flags: list[RiskFlag] = [];
    for n in bundle.itinerary.nodes {
        if n.booking_status != BookingStatus.BOOKED { continue; }
        policy = bundle.policy(n.policy_id) if n.policy_id else None;
        if policy is None {
            if n.paid_minor or n.price_minor {
                flags.append(_flag(rule, RiskCategory.BOOKING_TERMS, Severity.MEDIUM, FlagStatus.UNRESOLVED, [n.id],
                    f"No cancellation terms are on file for {n.title}, so its refund exposure is unknown.",
                    "Attach the booking's terms from the confirmation or provider page.", now));
            }
            continue;
        }
        status = evaluate_cancellation(policy, n, now);
        paid = format_money(status.paid_minor, status.currency);
        until = f" until {status.next_deadline_local}" if status.next_deadline_local else "";
        if status.state == CancelState.SERVICE_STARTED { continue; }
        if status.state == CancelState.UNKNOWN {
            flags.append(_flag(rule, RiskCategory.BOOKING_TERMS, Severity.MEDIUM, FlagStatus.UNRESOLVED, [n.id],
                f"Cancellation terms for {n.title} are incomplete (unknown: {', '.join(status.unknowns)}).",
                "Review the terms with the provider before relying on a refund.", now, status.evidence_ids));
        } elif status.state == CancelState.NO_REFUND {
            flags.append(_flag(rule, RiskCategory.BOOKING_TERMS, Severity.MEDIUM, FlagStatus.FLAGGED, [n.id],
                f"{n.title} is non-refundable if cancelled now; {paid} would be lost.",
                "Treat it as fixed when replanning, and ask the provider about changes or credit.",
                now, status.evidence_ids));
        } elif status.state == CancelState.PARTIAL_REFUND {
            refund = format_money(status.refund_if_cancel_now_minor, status.currency);
            flags.append(_flag(rule, RiskCategory.BOOKING_TERMS, Severity.LOW, FlagStatus.FLAGGED, [n.id],
                f"Cancelling {n.title} now refunds {refund} of {paid} as {status.refund_form.value}{until}.",
                "Factor the fee into any change to this booking.", now, status.evidence_ids));
        } elif status.minutes_to_next_deadline is not None
            and status.minutes_to_next_deadline <= config.deadline_soon_hours * 60 {
            flags.append(_flag(rule, RiskCategory.BOOKING_TERMS, Severity.MEDIUM, FlagStatus.FLAGGED, [n.id],
                f"Free cancellation for {n.title} ends in {_duration(status.minutes_to_next_deadline)} ({status.next_deadline_local}).",
                "Decide whether to keep this booking before the deadline.", now, status.evidence_ids));
        }
    }
    return flags;
}
