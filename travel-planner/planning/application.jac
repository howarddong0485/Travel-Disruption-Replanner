"""P4's transactional application hook for P3 AlternativePlan proposals."""
import json;
import from copy { deepcopy }
import from dataclasses { asdict, replace }
import from datetime { datetime }
import from uuid { uuid4 }
import from planning.context { build_context, read_facts }
import from planning.serialization { replacement_from_data, risk_from_data }
import from planning.engine { risk_context, VALIDATION_VERSION }
import from planning.validation { validate_plan }
import from tools.alternatives.catalog { observe }
import from backup.validation { instant }
import from schema.alternative { alternative_from_dict }

def apply_backup(conn: any, state: dict[str, any], proposal: dict[str, any], now: datetime) -> None {
    alternative_from_dict(proposal);
    if proposal.get("validator_version") != VALIDATION_VERSION { raise ValueError("Validation rules changed; find fresh plans"); }
    if datetime.fromisoformat(proposal["expires_at"]) <= now { raise ValueError("Backup evidence expired; find fresh plans before accepting"); }
    if not proposal["selectable"] { raise ValueError("An unresolved plan cannot be accepted"); }
    context = build_context(state, read_facts(conn, state["trip"]["id"]), now);
    if context["base_snapshot"] != proposal["base_snapshot"] { raise ValueError("Planning inputs changed; find fresh plans"); }
    originals = {item.id: item for item in context["trip"].items};
    current_risks = {risk["id"]: risk for risk in context["risks"]};
    candidates = []; activations = [];
    for data in proposal["replacements"] {
        previous = replacement_from_data(data);
        original = originals[previous.replaces_id];
        if previous.action == "reschedule" {
            updated = replace(previous, item=replace(original, start=previous.item.start, end=previous.item.end));
        } else {
            try { updated = observe(context["trip"], original, previous.provider_id, previous.item.start, now, context["facts"].get("inventory_change", "unchanged")); }
            except (TimeoutError, LookupError) as exc { raise ValueError("Provider could not reconfirm this plan; find fresh alternatives") from exc; }
            reviewed_facts = asdict(previous.item); current_facts = asdict(updated.item);
            reviewed_facts.pop("evidence", None); current_facts.pop("evidence", None);
            if updated.provider_id != previous.provider_id or reviewed_facts != current_facts {
                raise ValueError("Inventory details changed; review a fresh plan before accepting");
            }
        }
        old_risk = next(r for r in proposal["risks"] if r["item_id"] == previous.replaces_id);
        if old_risk["id"] not in current_risks { raise ValueError("Activation risk changed; find fresh plans"); }
        activations.append(risk_context(context, current_risks[old_risk["id"]], previous.replaces_id));
        candidates.append(updated);
    }
    checked = validate_plan(context["trip"], tuple(activations), tuple(candidates), now);
    if checked["status"] != "valid" { raise ValueError("Plan no longer passes all traveler, evidence, budget and timing checks"); }
    facts = deepcopy(context["facts"]);
    for candidate in candidates {
        original = originals[candidate.replaces_id]; item = candidate.item;
        before = next(i for i in state["items"] if i["id"] == item.id);
        if candidate.action == "replace" and original.paid_minor {
            conn.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?,0,1)",
                (str(uuid4()), context["trip_id"], "Prior payment: " + original.title, "expense", "", "", "", "",
                    "Retained original payment; no refund assumed", original.paid_minor));
        }
        conn.execute("UPDATE items SET title=?,date=?,time=?,location=?,reference=?,cost_cents=?,done=?,paid=? WHERE id=? AND trip_id=?",
            (item.title, item.start.local[:10], item.start.local[11:16], item.venue,
                "" if candidate.action == "replace" else before["reference"], item.cost_minor,
                0 if candidate.action == "replace" else before["done"], 0 if candidate.action == "replace" else before["paid"], item.id, context["trip_id"]));
        duration = int((instant(item.end) - instant(item.start)).total_seconds() / 60);
        conn.execute("INSERT INTO replan_rules VALUES (?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET duration_minutes=excluded.duration_minutes, latest_start=excluded.latest_start",
            (item.id, duration, before["latest_start"], int(before["fixed"])));
        facts["items"][item.id] = {"zone": item.start.zone, "start_fold": item.start.fold, "end": asdict(item.end),
            "evidence": asdict(item.evidence) if item.evidence else None, "availability": item.availability,
            "hours": [asdict(window) for window in item.hours] if item.hours is not None else None,
            "eligibility": item.eligibility, "party_size": item.party_size, "fees_included": item.fees_included,
            "child_min_age": item.child_min_age, "child_max_age": item.child_max_age, "blocks_time": item.blocks_time,
            "tags": ["indoor"] if item.eligibility.get("indoor") is True else []};
    }
    facts["transfers"] = checked["transfers"];
    changed_ids = {c.replaces_id for c in candidates};
    facts["manual_risks"] = [r for r in facts.get("manual_risks", []) if not changed_ids.intersection(r["node_ids"])];
    conn.execute("UPDATE planning_contexts SET payload=? WHERE trip_id=?", (json.dumps(facts, sort_keys=True), context["trip_id"]));
}
