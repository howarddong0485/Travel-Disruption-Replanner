"""Versioned, evidenced planning facts joined to P4's authoritative saved state.

The payload supplements saved records; it cannot replace their identity, prices,
paid state, dates or fixed/dependency rules. Absent facts stay unknown.
"""
import json;
import from copy { deepcopy }
import from datetime { datetime, timedelta }
import from dataclasses { asdict }
import from hashlib { sha256 }
import from planning.profile_io { profile_from_data }
import from profile.checks { hard_requirements }
import from budget.ledger { build_ledger }
import from schema.bundle { bundle_from_dict }
import from schema.common { to_plain }
import from risk.analyzer { analyze_trip }
import from backup.validation { instant, evidence_problem }
import from backup.validation_models { TripContext, ScheduledItem, Profile, Evidence, Moment, Window, Transfer, Dependency }

glob CONTEXT_VERSION = "roam.planning-context.v1";

def install_context_schema(conn: any) -> None {
    conn.execute("CREATE TABLE IF NOT EXISTS planning_contexts (trip_id TEXT PRIMARY KEY REFERENCES trips(id) ON DELETE CASCADE, payload TEXT NOT NULL)");
    conn.execute("CREATE TABLE IF NOT EXISTS planning_runs (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE, request_hash TEXT NOT NULL, payload TEXT NOT NULL)");
    for operation in ("INSERT", "UPDATE", "DELETE") {
        ref = "OLD" if operation == "DELETE" else "NEW";
        conn.execute("CREATE TRIGGER IF NOT EXISTS planning_context_" + operation.lower() + " AFTER " + operation +
            " ON planning_contexts BEGIN UPDATE trip_versions SET version=version+1 WHERE trip_id=" + ref + ".trip_id; END");
    }
    conn.commit();
}

def read_facts(conn: any, trip_id: str) -> dict[str, any] {
    row = conn.execute("SELECT payload FROM planning_contexts WHERE trip_id=?", (trip_id,)).fetchone();
    return json.loads(row["payload"]) if row else {};
}

def parse_evidence(data: any) -> Evidence | None {
    if data is None { return None; }
    if not isinstance(data, dict) or set(data) != {"source", "checked_at", "expires_at"} {
        raise ValueError("Evidence needs source, checked_at and expires_at");
    }
    if any(not isinstance(v, str) for v in data.values()) { raise ValueError("Evidence fields must be text"); }
    return Evidence(**data);
}

def parse_moment(data: any) -> Moment {
    if not isinstance(data, dict) or set(data) - {"local", "zone", "fold"} { raise ValueError("Invalid time record"); }
    return Moment(**data);
}

def check_payload(data: dict[str, any], state: dict[str, any]) -> dict[str, any] {
    data = deepcopy(data);
    allowed = {"contract_version", "profile", "zone", "reserve_minor", "items", "transfers", "evidence", "evidence_deadlines",
        "policies", "forecasts", "place_hours", "travel_estimates", "manual_risks", "inventory_change"};
    if not isinstance(data, dict) or set(data) - allowed { raise ValueError("Unsupported planning context fields"); }
    if data.get("contract_version") != CONTEXT_VERSION { raise ValueError("Unsupported planning context version"); }
    if data.get("profile") is not None { profile_from_data(data["profile"]); }
    reserve = data.get("reserve_minor", 0);
    if type(reserve) is not int or reserve < 0 { raise ValueError("Reserve must be nonnegative integer minor units"); }
    ids = {i["id"] for i in state["items"]};
    if set(data.get("items", {})) - ids { raise ValueError("Planning facts refer to another or removed item"); }
    allowed_facts = {"zone", "end", "evidence", "availability", "hours", "eligibility", "party_size", "fees_included",
        "child_min_age", "child_max_age", "kind", "tags", "policy_id", "end_zone", "start_fold", "blocks_time"};
    for facts in data.get("items", {}).values() {
        if not isinstance(facts, dict) or set(facts) - allowed_facts { raise ValueError("Unsupported item facts"); }
        parse_evidence(facts.get("evidence"));
        if "end" in facts { parse_moment(facts["end"]); }
        for window in facts.get("hours") or [] { parse_moment(window["start"]); parse_moment(window["end"]); }
        if any(type(v) is not bool and v is not None for v in facts.get("eligibility", {}).values()) {
            raise ValueError("Eligibility must be true, false or unknown");
        }
        for field in ("party_size", "child_min_age", "child_max_age") {
            if facts.get(field) is not None and (type(facts[field]) is not int or facts[field] < 0) { raise ValueError("Invalid " + field); }
        }
        for field in ("fees_included", "blocks_time") {
            if field in facts and type(facts[field]) is not bool { raise ValueError("Invalid " + field); }
        }
    }
    for route in data.get("transfers", []) {
        if route["from_id"] not in ids or route["to_id"] not in ids { raise ValueError("Foreign transfer item"); }
        parse_evidence(route.get("evidence"));
        if route.get("minutes") is not None and (type(route["minutes"]) is not int or route["minutes"] < 0) { raise ValueError("Invalid transfer minutes"); }
    }
    if len(json.dumps(data, allow_nan=False)) > 500000 { raise ValueError("Planning context is too large"); }
    return data;
}

def build_context(state: dict[str, any], facts: dict[str, any], now: datetime) -> dict[str, any] {
    trip = state["trip"]; source_profile = facts.get("profile");
    traveler = profile_from_data(source_profile) if source_profile else None;
    ledger_view = to_plain(build_ledger(trip, state["items"], facts.get("reserve_minor", 0)));
    commitments = {line["item_id"]: line["committed"] for line in ledger_view["lines"]};
    profile = Profile(traveler.adults, tuple(traveler.child_ages), complete=True,
        interests=tuple(traveler.interests)) if traveler else Profile(None, complete=False);
    nodes = [];
    for item in state["items"] {
        if item["category"] in ("packing", "expense") { continue; }
        detail = facts.get("items", {}).get(item["id"], {});
        zone = detail.get("zone", facts.get("zone", ""));
        start = Moment(item["date"] + "T" + item["time"] if item["date"] and item["time"] else "", zone, detail.get("start_fold"));
        end = parse_moment(detail["end"]) if detail.get("end") else Moment("", zone);
        evidence = parse_evidence(detail.get("evidence"));
        hours = tuple(Window(parse_moment(w["start"]), parse_moment(w["end"])) for w in detail["hours"]) if detail.get("hours") is not None else None;
        nodes.append(ScheduledItem(item["id"], item["title"], item["category"], item["location"], start, end,
            trip["currency"], item["cost_cents"] if evidence else None, detail.get("party_size"), detail.get("fees_included"), evidence,
            detail.get("availability", "unknown"), hours, detail.get("eligibility", {}), detail.get("child_min_age"),
            detail.get("child_max_age"), item["cost_cents"] if item["paid"] else 0,
            bool(item["fixed"]), bool(item["done"] and item["category"] in ("food", "activity")), detail.get("blocks_time", True), commitments.get(item["id"], False)));
    }
    transfers = tuple(Transfer(r["from_id"], r["to_id"], r["from_venue"], r["to_venue"], r.get("minutes"), parse_evidence(r.get("evidence"))) for r in facts.get("transfers", []));
    dependencies = tuple(Dependency(e["prerequisite_id"], e["dependent_id"], e["buffer_minutes"]) for e in state["dependencies"]);
    context = TripContext(trip["id"], trip["currency"], facts.get("zone", ""), trip["start_date"], trip["end_date"],
        trip["budget_cents"] or None, facts.get("reserve_minor", 0), profile, tuple(nodes), transfers, dependencies,
        traveler_profile=source_profile, extra_cost_minor=sum(i["cost_cents"] for i in state["items"] if i["category"] == "expense"),
        latest_starts={i["id"]: Moment(i["latest_start"], facts.get("items", {}).get(i["id"], {}).get("zone", facts.get("zone", ""))) for i in state["items"] if i.get("latest_start")},
        extra_items=tuple({key: i[key] for key in ("id", "trip_id", "title", "category", "cost_cents", "paid", "done")} for i in state["items"] if i["category"] == "expense"));
    kind_map = {"transport": "transit", "stay": "stay", "food": "food", "activity": "activity"};
    graph_nodes = [];
    supporting = deepcopy(facts.get("evidence", []));
    deadlines = dict(facts.get("evidence_deadlines", {}));
    for item in nodes {
        detail = facts.get("items", {}).get(item.id, {});
        # P2's time helper chooses a DST fold; only pass times that our strict resolver can establish.
        start_local = item.start.local; end_local = item.end.local;
        try { instant(Moment(item.start.local, item.start.zone)); } except ValueError { start_local = ""; }
        try { instant(Moment(item.end.local, item.end.zone)); } except ValueError { end_local = ""; }
        cited = [];
        if item.evidence is not None {
            evidence_id = "item-facts:" + item.id;
            supporting.append({"id": evidence_id, "source_ref": item.evidence.source, "excerpt": "Supplied itinerary facts",
                "retrieved_at": item.evidence.checked_at, "origin": "mock"});
            deadlines[evidence_id] = item.evidence.expires_at; cited.append(evidence_id);
        }
        graph_nodes.append({"id": item.id, "kind": detail.get("kind", kind_map[item.category]), "title": item.title,
            "tz": item.start.zone, "start_local": start_local, "end_local": end_local, "end_tz": item.end.zone,
            "location": item.venue, "area": trip["destination"], "fixed": item.fixed,
            "booking_status": "completed" if item.completed else "booked" if item.paid_minor or next(i for i in state["items"] if i["id"] == item.id)["done"] else "planned",
            "currency": item.currency, "price_minor": item.cost_minor, "paid_minor": item.paid_minor,
            "tags": detail.get("tags", []), "policy_id": detail.get("policy_id", ""), "evidence_ids": cited});
    }
    bundle_data = {key: deepcopy(facts.get(key, [])) for key in ("evidence", "policies", "forecasts", "place_hours", "travel_estimates")};
    bundle_data["evidence"] = supporting;
    bundle_data["itinerary"] = {"trip_id": trip["id"], "version": state["version"], "nodes": graph_nodes,
        "edges": [{"source_id": e.from_id, "target_id": e.to_id, "relation": "depends_on", "min_transition_minutes": e.buffer_minutes} for e in dependencies]};
    bundle = bundle_from_dict(bundle_data);
    for policy in bundle.policies {
        for tier in policy.tiers {
            if tier.deadline_local {
                try { instant(Moment(tier.deadline_local, policy.tz)); }
                except ValueError {
                    # P2 cannot represent a deadline fold; no refund conclusion
                    # may depend on guessing an ambiguous or nonexistent time.
                    policy.tiers = []; policy.unknowns.append("Cancellation deadline requires an unambiguous instant"); break;
                }
            }
        }
    }
    risks = to_plain(analyze_trip(bundle, now.isoformat()));
    evidence_by_id = {record["id"]: record for record in supporting};
    for risk in risks {
        stale = [];
        for key in risk["evidence_ids"] {
            evidence_data = evidence_by_id.get(key, {});
            observed = Evidence(evidence_data.get("source_ref", ""), evidence_data.get("retrieved_at", ""), deadlines.get(key, ""));
            if evidence_problem(observed, now) { stale.append(key); }
        }
        if stale or not risk["evidence_ids"] { risk["status"] = "unresolved"; }
        risk["stale_evidence_ids"] = stale;
    }
    for risk in facts.get("manual_risks", []) {
        if set(risk) - {"id", "category", "node_ids", "summary", "evidence", "not_before"} { raise ValueError("Unsupported manual risk fields"); }
        if not risk.get("node_ids") or set(risk["node_ids"]) - {i.id for i in nodes} { raise ValueError("Foreign manual risk nodes"); }
        fresh = not evidence_problem(parse_evidence(risk.get("evidence")), now);
        risks.append({**risk, "rule_id": "traveler_report", "severity": "medium", "status": "flagged" if fresh else "unresolved",
            "source": "traveler_report", "evidence_ids": [], "evaluated_at": now.isoformat()});
    }
    fingerprint = sha256(json.dumps({"state": state, "facts": facts}, sort_keys=True).encode()).hexdigest();
    return {"contract_version": CONTEXT_VERSION, "trip_id": trip["id"], "trip_version": state["version"],
        "checked_at": now.isoformat(),
        "base_snapshot": fingerprint, "trip": context, "risks": risks, "bundle": bundle, "facts": deepcopy(facts),
        "ledger": ledger_view, "state": deepcopy(state)};
}

def public_context(context: dict[str, any]) -> dict[str, any] {
    result = {key: context[key] for key in ("contract_version", "trip_id", "trip_version", "base_snapshot", "risks", "ledger", "facts", "checked_at")};
    result["items"] = [{key: item[key] for key in ("id", "title", "category", "date", "time", "location", "cost_cents", "done", "paid")} for item in context["state"]["items"]];
    return result;
}
