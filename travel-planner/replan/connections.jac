"""Enforce supplied venue-bound transfer evidence on every proposed saved trip."""
import from datetime { datetime, timedelta }
import from backup.validation { instant, evidence_problem }
import from backup.validation_models { Moment, Evidence }
import from zoneinfo { ZoneInfo }

def item_zone(item: dict[str, any], facts: dict[str, any], ending: bool = False) -> str {
    detail = item.get("journey") or {};
    return (detail.get("end_zone") if ending else detail.get("zone")) or facts.get("items", {}).get(item["id"], {}).get("zone") or facts.get("zone", "");
}

def moment(item: dict[str, any], facts: dict[str, any], ending: bool = False) -> datetime {
    detail = item.get("journey") or {};
    if ending and detail.get("arrival_date") and detail.get("arrival_time") {
        return instant(Moment(detail["arrival_date"] + "T" + detail["arrival_time"], detail["end_zone"]));
    }
    first = instant(Moment(item["date"] + "T" + item["time"], item_zone(item, facts), facts.get("items", {}).get(item["id"], {}).get("start_fold")));
    return first + timedelta(minutes=item["duration_minutes"]) if ending else first;
}

def time_label(item: dict[str, any], facts: dict[str, any], ending: bool = False) -> str {
    if not item.get("date") or not item.get("time") { return "time not set"; }
    zone = item_zone(item, facts, ending);
    if not zone {
        local = datetime.fromisoformat(item["date"] + "T" + item["time"]);
        if ending { local += timedelta(minutes=item["duration_minutes"]); }
        return local.isoformat(sep=" ", timespec="minutes") + " (time zone not set)";
    }
    try { return moment(item, facts, ending).astimezone(ZoneInfo(zone)).isoformat(sep=" ", timespec="minutes") + " " + zone; }
    except (ValueError, KeyError) { return "local time needs confirmation in " + zone; }
}

def transfer_records(items: list[dict[str, any]], facts: dict[str, any]) -> list[dict[str, any]] {
    originals = {i["id"]: i for i in items};
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
    return records;
}

def current_transfer(record: dict[str, any], checked_at: datetime) -> bool {
    data = record.get("evidence") or {};
    proof = Evidence(data.get("source", ""), data.get("checked_at", ""), data.get("expires_at", ""));
    return type(record.get("minutes")) is int and record["minutes"] >= 0 and not evidence_problem(proof, checked_at);
}

def validate_connections(state: dict[str, any], nodes: dict[str, any], facts: dict[str, any], checked_at: datetime,
    requirements: list[dict[str, any]] | None = None, supplied: list[dict[str, any]] | None = None) -> None {
    records = transfer_records(state["items"], facts);
    pairs = sorted(set((r["from_id"], r["to_id"]) for r in records));
    for (left, right) in pairs {
        if left not in nodes or right not in nodes { continue; }
        (first, second) = (nodes[left], nodes[right]);
        matching = [r for r in records if r["from_id"] == left and r["to_id"] == right and
            r["from_venue"] == first["location"] and r["to_venue"] == second["location"]];
        fresh = [record for record in matching if current_transfer(record, checked_at)];
        verified = [r for r in (supplied or []) if r["from_id"] == left and r["to_id"] == right and
            r["from_venue"] == first["location"] and r["to_venue"] == second["location"] and current_transfer(r, checked_at)];
        if not verified and (not matching or len(matching) != len(fresh)) {
            if requirements is None {
                pair = first["title"] + " and " + second["title"];
                if not matching { raise ValueError("Refresh travel time between " + pair + " after changing their locations."); }
                raise ValueError("Travel-time evidence between " + pair + " is missing or expired. Refresh it before saving.");
            }
            requirements.append({"id": left + ":" + right, "from_id": left, "to_id": right,
                "from_title": first["title"], "to_title": second["title"], "from_venue": first["location"], "to_venue": second["location"],
                "departure": time_label(first, facts, True), "arrival_by": time_label(second, facts)});
        }
        durations = [r["minutes"] for r in fresh + verified];
        if not durations { continue; }
        gap = (moment(second, facts) - moment(first, facts, True)).total_seconds() / 60;
        if gap < max(durations) {
            raise ValueError(first["title"] + " ends " + time_label(first, facts, True) + ". " + second["title"] +
                " starts " + time_label(second, facts) + ". The saved connection needs at least " + str(max(durations)) + " minutes.");
        }
    }
}
