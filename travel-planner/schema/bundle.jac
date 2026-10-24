"""A trip plus the policies and evidence needed to analyze it, loadable from JSON fixtures.

PROPOSAL (Person 2). Loading checks structure only: unique IDs, resolvable
references, valid zones and local times. Budget and traveler-constraint
validation belong to the ConstraintValidator (Person 1).
"""
import json;
import from schema.common { Evidence, Origin, valid_zone, valid_local }
import from schema.itinerary {
    ItineraryNode, ItineraryEdge, ItineraryGraph, NodeKind, BookingStatus,
    EdgeRelation, PlaceHours, WeatherForecast, TravelEstimate
}
import from schema.policy { RefundPolicy, CancellationTier, RefundForm }

obj TripBundle {
    has itinerary: ItineraryGraph;
    has policies: list[RefundPolicy] = [];
    has evidence: list[Evidence] = [];
    has place_hours: list[PlaceHours] = [];
    has forecasts: list[WeatherForecast] = [];
    has travel_estimates: list[TravelEstimate] = [];

    def policy(policy_id: str) -> RefundPolicy | None {
        for p in self.policies { if p.id == policy_id { return p; } }
        return None;
    }
}

def _node(d: dict[str, any]) -> ItineraryNode {
    return ItineraryNode(**{**d, "kind": NodeKind(d["kind"]),
        "booking_status": BookingStatus(d.get("booking_status", "planned"))});
}

def _edge(d: dict[str, any]) -> ItineraryEdge {
    return ItineraryEdge(**{**d, "relation": EdgeRelation(d["relation"])});
}

def _policy(d: dict[str, any]) -> RefundPolicy {
    tiers = [CancellationTier(**{**t, "refund_form": RefundForm(t.get("refund_form", "unknown"))})
        for t in d.get("tiers", [])];
    return RefundPolicy(**{**d, "tiers": tiers, "origin": Origin(d.get("origin", "mock"))});
}

def _evidence(d: dict[str, any]) -> Evidence {
    return Evidence(**{**d, "origin": Origin(d.get("origin", "mock"))});
}

def bundle_from_dict(data: dict[str, any]) -> TripBundle {
    g = data["itinerary"];
    itinerary = ItineraryGraph(trip_id=g["trip_id"], version=g["version"],
        nodes=[_node(n) for n in g.get("nodes", [])],
        edges=[_edge(e) for e in g.get("edges", [])]);
    bundle = TripBundle(itinerary=itinerary,
        policies=[_policy(p) for p in data.get("policies", [])],
        evidence=[_evidence(e) for e in data.get("evidence", [])],
        place_hours=[PlaceHours(**h) for h in data.get("place_hours", [])],
        forecasts=[WeatherForecast(**f) for f in data.get("forecasts", [])],
        travel_estimates=[TravelEstimate(**t) for t in data.get("travel_estimates", [])]);
    problems = structural_problems(bundle);
    if problems { raise ValueError("Invalid trip bundle:\n- " + "\n- ".join(problems)); }
    return bundle;
}

def load_bundle(path: str) -> TripBundle {
    with open(path, encoding="utf-8") as handle { return bundle_from_dict(json.load(handle)); }
}

def _check_times(label: str, tz: str, locals: list[str], problems: list[str]) -> None {
    used = [t for t in locals if t];
    if used and not valid_zone(tz) { problems.append(f"{label}: unknown time zone '{tz}'"); }
    for t in used {
        if not valid_local(t) { problems.append(f"{label}: time '{t}' is not YYYY-MM-DDTHH:MM"); }
    }
}

"""Every structural problem in the bundle; empty when it is consistent."""
def structural_problems(bundle: TripBundle) -> list[str] {
    problems: list[str] = [];
    evidence_ids = {e.id for e in bundle.evidence};
    node_ids: set[str] = set();
    for n in bundle.itinerary.nodes {
        if n.id in node_ids { problems.append(f"duplicate node id '{n.id}'"); }
        node_ids.add(n.id);
        _check_times(f"node {n.id}", n.tz, [n.start_local], problems);
        _check_times(f"node {n.id}", n.end_zone(), [n.end_local], problems);
        for e in n.evidence_ids {
            if e not in evidence_ids { problems.append(f"node {n.id}: unknown evidence '{e}'"); }
        }
    }
    for e in bundle.itinerary.edges {
        for end in [e.source_id, e.target_id] {
            if end not in node_ids { problems.append(f"edge {e.source_id}->{e.target_id}: unknown node '{end}'"); }
        }
    }
    policy_ids: set[str] = set();
    for p in bundle.policies {
        if p.id in policy_ids { problems.append(f"duplicate policy id '{p.id}'"); }
        policy_ids.add(p.id);
        if p.booking_node_id not in node_ids { problems.append(f"policy {p.id}: unknown node '{p.booking_node_id}'"); }
        _check_times(f"policy {p.id}", p.tz, [t.deadline_local for t in p.tiers], problems);
        cited = [t.evidence_id for t in p.tiers] + ([p.no_show_evidence_id] if p.no_show_evidence_id else []);
        for e in cited {
            if e not in evidence_ids { problems.append(f"policy {p.id}: unknown evidence '{e}'"); }
        }
    }
    for n in bundle.itinerary.nodes {
        if n.policy_id and n.policy_id not in policy_ids { problems.append(f"node {n.id}: unknown policy '{n.policy_id}'"); }
    }
    for h in bundle.place_hours {
        if h.node_id not in node_ids { problems.append(f"hours for unknown node '{h.node_id}'"); }
        if h.evidence_id not in evidence_ids { problems.append(f"hours for {h.node_id}: unknown evidence '{h.evidence_id}'"); }
    }
    for f in bundle.forecasts {
        _check_times(f"forecast {f.id}", f.tz, [f.start_local, f.end_local], problems);
        if f.evidence_id not in evidence_ids { problems.append(f"forecast {f.id}: unknown evidence '{f.evidence_id}'"); }
    }
    for t in bundle.travel_estimates {
        for end in [t.from_node_id, t.to_node_id] {
            if end not in node_ids { problems.append(f"travel estimate: unknown node '{end}'"); }
        }
        if t.evidence_id not in evidence_ids { problems.append(f"travel estimate: unknown evidence '{t.evidence_id}'"); }
    }
    return problems;
}
