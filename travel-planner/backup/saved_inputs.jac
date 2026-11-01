"""Map saved Roam records to module-owned inputs without inventing missing facts."""
import json;
import uuid;
import from datetime { datetime }
import from hashlib { sha256 }
import from backup.history { identifier }
import from backup.validation_models { Moment, Profile, RiskContext, ScheduledItem, TripContext }

def trip_session(session_id: str, trip_id: str) -> str {
    return str(uuid.uuid5(uuid.UUID(identifier(session_id)), "saved-trip:" + trip_id));
}

def saved_fingerprint(trip: dict[str, any], items: list[dict[str, any]]) -> str {
    return sha256(json.dumps({"trip": trip, "items": sorted(items, key=lambda (i: dict[str, any]) -> str { str(i["id"]); })}, sort_keys=True).encode()).hexdigest();
}

def saved_inputs(trip: dict[str, any], items: list[dict[str, any]], item_id: str,
    trigger: str) -> tuple[TripContext, RiskContext] {
    if trigger not in ("rain", "arrival_delay") { raise ValueError("Choose rain or arrival_delay"); }
    matches = [i for i in items if i["id"] == item_id];
    if len(matches) != 1 { raise ValueError("Choose an item belonging to this trip"); }
    target = matches[0];
    if target["done"] or not target["date"] { raise ValueError("Choose a dated, unfinished item"); }
    if target["category"] != ("activity" if trigger == "rain" else "food") {
        raise ValueError("Trigger does not match the target category");
    }
    nodes = [];
    for item in sorted(items, key=lambda (i: dict[str, any]) -> str { str(i["date"]) + "|" + str(i["time"]) + "|" + str(i["id"]); }) {
        if item["category"] == "packing" { continue; }
        start = item["date"] + ("T" + item["time"] if item["time"] else "") if item["date"] else "";
        # Basic records have no timezone/end time, provider quote, party coverage,
        # route estimates or eligibility evidence. Their UI amount is not a quote.
        nodes.append(ScheduledItem(item["id"], item["title"], item["category"], item["location"],
            Moment(start, ""), Moment("", ""), trip["currency"], None, None, None, None,
            paid_minor=item["cost_cents"] if item["paid"] else 0, completed=bool(item["done"])));
    }
    context = TripContext(trip["id"], trip["currency"], "", trip["start_date"], trip["end_date"],
        trip["budget_cents"], 0, Profile(None, complete=False), tuple(nodes), ());
    # The trigger is user-selected, not a fabricated automatic RiskFlag.
    risk = RiskContext("manual:" + item_id + ":" + trigger, trip["id"], item_id, trigger, "unconfirmed", None);
    return (context, risk);
}
