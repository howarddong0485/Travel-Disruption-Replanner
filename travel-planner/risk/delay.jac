"""Delay impact: what a late-running item does to the items scheduled after it.

The delay is carried forward along the itinerary's links. Each linked item gets
the same time it needs after the previous one as the tight-connection rule uses
(a stated minimum, a travel estimate, or the standard buffer). An item is pushed
only when it can't start on time; a stay keeps its checkout and only checks in
later. Missing times leave an item unresolved, and later items on the same day
that aren't linked are listed as unchecked, never as fine.
"""
import from datetime { datetime, timedelta }
import from schema.common { local_to_instant, minutes_between, to_local_text }
import from schema.itinerary { ItineraryNode, ItineraryEdge, NodeKind, BookingStatus, EdgeRelation }
import from schema.bundle { TripBundle }
import from risk.config { RiskConfig }

"""How one later item is affected. status is pushed, on_time, unresolved or not_linked."""
obj DelayEffect {
    has node_id: str;
    has title: str;
    has status: str;
    has minutes_late: int | None = None;
    has spare_minutes: int | None = None;
    has new_start_local: str = "";
    has after_id: str = "";
    has reason: str = "";
    has evidence_ids: list[str] = [];
}

obj DelayImpact {
    has node_id: str;
    has delay_minutes: int;
    has new_end_local: str;
    has effects: list[DelayEffect] = [];
}

def _active(n: ItineraryNode) -> bool {
    return n.booking_status not in [BookingStatus.CANCELLED, BookingStatus.COMPLETED];
}

def _local(instant: datetime, tz: str) -> str { return to_local_text(instant, tz)[:16]; }

"""Minutes needed between src ending and dst starting, and the evidence behind them."""
def _needed(bundle: TripBundle, link: ItineraryEdge, src: ItineraryNode, config: RiskConfig) -> tuple[int, list[str]] {
    needs: list[int] = [];
    evidence: list[str] = [];
    if link.min_transition_minutes is not None { needs.append(link.min_transition_minutes); }
    for est in bundle.travel_estimates {
        if est.from_node_id == src.id and est.to_node_id == link.target_id {
            needs.append(est.minutes);
            evidence.append(est.evidence_id);
        }
    }
    if not needs {
        needs.append(config.flight_arrival_buffer_minutes if src.kind == NodeKind.FLIGHT else config.min_transfer_minutes);
    }
    return (max(needs), evidence);
}

"""Carry a delay of `delay_minutes` on `node_id` forward through the items after it."""
def delay_impact(bundle: TripBundle, node_id: str, delay_minutes: int, config: RiskConfig | None = None) -> DelayImpact {
    cfg = config or RiskConfig();
    delayed = bundle.itinerary.find_node(node_id);
    if delayed is None { raise ValueError(f"unknown item '{node_id}'"); }
    if delay_minutes < 0 { raise ValueError("delay must be zero or more minutes"); }
    scheduled_end = local_to_instant(delayed.end_local, delayed.end_zone());
    late_end = scheduled_end + timedelta(minutes=delay_minutes) if scheduled_end is not None else None;
    impact = DelayImpact(node_id=delayed.id, delay_minutes=delay_minutes,
        new_end_local=_local(late_end, delayed.end_zone()) if late_end is not None else "");
    nodes = {n.id:n for n in bundle.itinerary.nodes};
    links = [e for e in bundle.itinerary.edges if e.relation != EdgeRelation.ALTERNATIVE and
        e.source_id in nodes and e.target_id in nodes and _active(nodes[e.source_id]) and _active(nodes[e.target_id])];
    reachable = {node_id}; queue = [node_id];
    while queue {
        source = queue.pop(0);
        for link in links {
            if link.source_id == source and link.target_id not in reachable {
                reachable.add(link.target_id); queue.append(link.target_id);
            }
        }
    }
    # Resolve every affected predecessor before a shared successor. Unaffected
    # incoming prerequisites still constrain that successor's earliest start.
    pending = set(reachable); order: list[str] = [];
    while pending {
        ready = sorted(key for key in pending if not any(e.target_id == key and e.source_id in pending for e in links));
        if not ready { raise ValueError("The affected itinerary has a dependency cycle. Correct its links before checking a delay."); }
        order.extend(ready); pending.difference_update(ready);
    }
    ends: dict[str, datetime | None] = {node_id:late_end};
    for key in order {
        if key == node_id { continue; }
        dst = nodes[key]; start = local_to_instant(dst.start_local, dst.tz);
        effect = DelayEffect(node_id=dst.id, title=dst.title, status="unresolved");
        earliest: datetime | None = None; missing: list[str] = []; evidence_ids: list[str] = []; need = 0;
        for link in links {
            if link.target_id != key { continue; }
            src = nodes[link.source_id];
            src_end = ends.get(src.id) if src.id in reachable else local_to_instant(src.end_local, src.end_zone());
            if src_end is None { missing.append(src.title); continue; }
            (minutes, evidence) = _needed(bundle, link, src, cfg); evidence_ids.extend(evidence);
            boundary = src_end + timedelta(minutes=minutes);
            if earliest is None or boundary > earliest {
                earliest = boundary; need = minutes; effect.after_id = src.id;
            }
        }
        ends[key] = None; effect.evidence_ids = sorted(set(evidence_ids));
        if missing { effect.reason = ", ".join(missing) + " has no known end time, so the effect on " + dst.title + " can't be checked."; }
        elif start is None { effect.reason = dst.title + " has no start time, so the effect of the delay can't be checked."; }
        elif earliest is not None {
            late = minutes_between(start, earliest);
            end = local_to_instant(dst.end_local, dst.end_zone());
            if late > 0 {
                effect.status = "pushed"; effect.minutes_late = late;
                effect.new_start_local = _local(earliest, dst.tz);
                effect.reason = dst.title + " can't start until " + effect.new_start_local[11:] + ", " + str(late) + " min late (" + str(need) + " min needed after " + nodes[effect.after_id].title + ").";
                ends[key] = end if dst.kind == NodeKind.STAY or end is None else end + timedelta(minutes=late);
            } else {
                effect.status = "on_time"; effect.minutes_late = 0; effect.spare_minutes = -late;
                effect.reason = dst.title + " still starts on time with " + str(-late) + " min to spare.";
                ends[key] = end;
            }
        }
        impact.effects.append(effect);
    }
    if scheduled_end is not None {
        day = _local(scheduled_end, delayed.end_zone())[:10];
        for n in bundle.itinerary.nodes {
            if n.id in ends or not _active(n) { continue; }
            start = local_to_instant(n.start_local, n.tz);
            if start is None or start < scheduled_end or _local(start, delayed.end_zone())[:10] != day { continue; }
            impact.effects.append(DelayEffect(node_id=n.id, title=n.title, status="not_linked",
                reason=f"{n.title} isn't linked to {delayed.title}, so this delay's effect on it isn't checked."));
        }
    }
    return impact;
}
