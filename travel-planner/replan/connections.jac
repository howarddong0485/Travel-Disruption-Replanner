"""Enforce supplied venue-bound transfer evidence on every proposed saved trip."""
import from datetime { datetime, timedelta, timezone }
import from backup.validation { instant, evidence_problem }
import from backup.validation_models { Moment, Evidence }

def moment(item: dict[str, any], facts: dict[str, any], ending: bool = False) -> datetime {
    detail = item.get("journey") or {};
    zone = detail.get("zone") or facts.get("items", {}).get(item["id"], {}).get("zone") or facts.get("zone", "");
    if ending and detail.get("arrival_date") and detail.get("arrival_time") {
        return instant(Moment(detail["arrival_date"] + "T" + detail["arrival_time"], detail["end_zone"]));
    }
    first = instant(Moment(item["date"] + "T" + item["time"], zone, facts.get("items", {}).get(item["id"], {}).get("start_fold")));
    return first + timedelta(minutes=item["duration_minutes"]) if ending else first;
}

def validate_connections(state: dict[str, any], nodes: dict[str, any], facts: dict[str, any], checked_at: datetime) -> None {
    originals = {i["id"]:i for i in state["items"]};
    records = [];
    evidence = {e["id"]:e for e in facts.get("evidence", [])};
    for estimate in facts.get("travel_estimates", []) {
        left = estimate["from_node_id"]; right = estimate["to_node_id"];
        if left not in originals or right not in originals { continue; }
        proof = evidence.get(estimate["evidence_id"], {});
        records.append({"from_id":left, "to_id":right, "from_venue":originals[left]["location"], "to_venue":originals[right]["location"],
            "minutes":estimate["minutes"], "evidence":{"source":proof.get("source_ref", ""), "checked_at":proof.get("retrieved_at", ""),
                "expires_at":facts.get("evidence_deadlines", {}).get(estimate["evidence_id"], "")}});
    }
    records.extend(facts.get("transfers", []));
    pairs = sorted(set((r["from_id"], r["to_id"]) for r in records));
    for (left, right) in pairs {
        if left not in nodes or right not in nodes { continue; }
        matching = [r for r in records if r["from_id"] == left and r["to_id"] == right and
            r["from_venue"] == nodes[left]["location"] and r["to_venue"] == nodes[right]["location"]];
        if not matching { raise ValueError("Refresh travel time between " + nodes[left]["title"] + " and " + nodes[right]["title"] + " after changing their locations."); }
        durations: list[int] = [];
        for record in matching {
            data = record.get("evidence") or {};
            proof = Evidence(data.get("source", ""), data.get("checked_at", ""), data.get("expires_at", ""));
            minutes = record.get("minutes");
            if type(minutes) is not int or minutes < 0 or evidence_problem(proof, checked_at) {
                raise ValueError("Travel-time evidence between " + nodes[left]["title"] + " and " + nodes[right]["title"] + " is missing or expired. Refresh it before saving.");
            }
            durations.append(minutes);
        }
        gap = (moment(nodes[right], facts) - moment(nodes[left], facts, True)).total_seconds() / 60;
        if gap < max(durations) { raise ValueError("The connection from " + nodes[left]["title"] + " to " + nodes[right]["title"] + " needs at least " + str(max(durations)) + " minutes."); }
    }
}
