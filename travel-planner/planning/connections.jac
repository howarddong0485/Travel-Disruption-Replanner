"""Venue-bound P2 connection evidence shared by search and acceptance."""
import from dataclasses { replace }
import from datetime { datetime, timedelta }
import from backup.validation { instant, evidence_problem }
import from backup.validation_models { Evidence, ScheduledItem, Transfer, TripContext }
import from schema.bundle { TripBundle }
import from tools.alternatives.catalog { routes }

def estimate_connections(bundle: TripBundle, items: tuple[ScheduledItem, ...], deadlines: dict[str, str]) -> tuple[Transfer, ...] {
    nodes = {item.id:item for item in items}; sources = {source.id:source for source in bundle.evidence};
    result = [];
    for estimate in bundle.travel_estimates {
        if type(estimate.minutes) is not int or estimate.minutes < 0 or estimate.from_node_id == estimate.to_node_id {
            raise ValueError("Travel estimates require distinct endpoints and nonnegative integer minutes");
        }
        source = sources[estimate.evidence_id];
        proof = Evidence(source.source_ref, source.retrieved_at, deadlines.get(source.id, ""));
        left = nodes[estimate.from_node_id]; right = nodes[estimate.to_node_id];
        result.append(Transfer(left.id, right.id, left.venue, right.venue, estimate.minutes, proof));
    }
    return tuple(result);
}

def route_key(route: Transfer) -> tuple[str, str, str, str] {
    return (route.from_id, route.to_id, route.from_venue, route.to_venue);
}

def usable(route: Transfer, now: datetime) -> bool {
    return type(route.minutes) is int and route.minutes >= 0 and not evidence_problem(route.evidence, now);
}

def combine_connections(required: tuple[Transfer, ...], optional: tuple[Transfer, ...], now: datetime) -> Transfer {
    first = required[0];
    if any(not usable(route, now) for route in required) { return replace(first, minutes=None, evidence=None); }
    records = list(required) + [route for route in optional if usable(route, now)];
    proofs: list[Evidence] = []; durations: list[int] = [];
    for route in records {
        source = route.evidence; duration = route.minutes;
        if source is None or duration is None { return replace(first, minutes=None, evidence=None); }
        proofs.append(source); durations.append(duration);
    }
    proof = Evidence(";".join(dict.fromkeys(source.source for source in proofs)),
        max(datetime.fromisoformat(source.checked_at) for source in proofs).isoformat(),
        min(datetime.fromisoformat(source.expires_at) for source in proofs).isoformat());
    return replace(first, minutes=max(durations), evidence=proof);
}

def applicable_connections(trip: TripContext, nodes: tuple[ScheduledItem, ...], estimates: tuple[Transfer, ...], now: datetime) -> tuple[Transfer, ...] {
    current = {item.id:item for item in nodes}; groups: dict[tuple[str, str, str, str], list[Transfer]] = {};
    for route in estimates {
        left = current.get(route.from_id); right = current.get(route.to_id);
        if left is not None and right is not None and (left.venue, right.venue) == (route.from_venue, route.to_venue) {
            groups.setdefault(route_key(route), []).append(route);
        }
    }
    return tuple(combine_connections(tuple(required), tuple(route for route in trip.transfers if route_key(route) == key), now)
        for (key, required) in groups.items());
}

def validation_routes(trip: TripContext, nodes: tuple[ScheduledItem, ...], estimates: tuple[Transfer, ...], now: datetime) -> tuple[tuple[Transfer, ...], tuple[Transfer, ...]] {
    constraints = applicable_connections(trip, nodes, estimates, now);
    by_key = {route_key(route):route for route in constraints};
    try { travel = routes(trip, nodes, now); } except ValueError { travel = trip.transfers; }
    # A catalog fallback can add current routing evidence, but cannot weaken or
    # replace an unresolved mandatory estimate for the same pair of venues.
    travel = tuple(combine_connections((by_key[route_key(route)],), (route,), now)
        if route_key(route) in by_key else route for route in travel);
    return (travel, constraints);
}

def connection_boundaries(trip: TripContext, nodes: tuple[ScheduledItem, ...], estimates: tuple[Transfer, ...], now: datetime) -> dict[str, datetime] {
    current = {item.id:item for item in nodes}; boundaries = {};
    for route in applicable_connections(trip, nodes, estimates, now) {
        minutes = route.minutes;
        if not usable(route, now) or minutes is None { continue; }
        try { boundary = instant(current[route.from_id].end) + timedelta(minutes=minutes); }
        except ValueError { continue; }
        if route.to_id not in boundaries or boundary > boundaries[route.to_id] { boundaries[route.to_id] = boundary; }
    }
    return boundaries;
}

def connection_checks(nodes: tuple[ScheduledItem, ...], constraints: tuple[Transfer, ...], now: datetime) -> list[dict[str, any]] {
    current = {item.id:item for item in nodes}; checks = [];
    for route in constraints {
        status = "unknown"; code = "transfer_evidence"; message = "Supplemental travel estimate needs current evidence";
        minutes = route.minutes;
        if usable(route, now) and minutes is not None {
            code = "transfer";
            try {
                gap = (instant(current[route.to_id].start) - instant(current[route.from_id].end)).total_seconds() / 60;
                status = "pass" if gap >= minutes else "fail";
                message = "Supplemental connection needs at least " + str(minutes) + " minutes";
            } except ValueError { message = "Supplemental connection needs explicit unambiguous times"; }
        }
        checks.append({"code":code, "status":status, "message":message, "item_ids":[route.from_id, route.to_id]});
    }
    return checks;
}
