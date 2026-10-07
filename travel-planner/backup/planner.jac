"""Read-only BackupAgent scaffold: candidate screening, never full-trip validation."""
import datetime;
import hashlib;
import json;
import from backup.models { BackupCandidate, BackupOption, BackupPreview }
import from tools.alternatives.mock { search }

def screen(candidate: BackupCandidate, currency: str, now: datetime.datetime) -> str {
    if candidate.currency != currency { return "Currency mismatch; no conversion evidence"; }
    if candidate.estimated_cost_minor < 0 { return "Invalid negative cost"; }
    if candidate.availability != "available" { return "Inventory " + candidate.availability; }
    if not candidate.source_ref { return "Missing source evidence"; }
    try {
        checked = datetime.datetime.fromisoformat(candidate.checked_at);
        expires = datetime.datetime.fromisoformat(candidate.expires_at);
        if checked.tzinfo is None or expires.tzinfo is None { return "Evidence needs timezone-aware instants"; }
        if checked > now or expires <= now or expires <= checked { return "Evidence is stale or invalid"; }
    } except ValueError { return "Invalid evidence timestamp"; }
    return "";
}

def prepare(trip: dict[str, any], items: list[dict[str, any]], item_id: str, trigger: str,
    now: datetime.datetime) -> BackupPreview {
    if now.tzinfo is None { raise ValueError("Clock must be timezone-aware"); }
    if trigger not in ["rain", "arrival_delay"] { raise ValueError("Choose rain or arrival_delay"); }
    matched = [item for item in items if item["id"] == item_id];
    if not matched { raise ValueError("Choose an item belonging to this trip"); }
    item = matched[0];
    category = "activity" if trigger == "rain" else "food";
    if item["category"] != category { raise ValueError("Rain requires an activity; arrival_delay requires a dining item"); }
    if item["done"] { raise ValueError("Completed items do not need backup suggestions"); }
    if not item["date"] { raise ValueError("Set the item's date before preparing backups"); }
    # A content fingerprint detects changes for future handoff; it is not an application version.
    snapshot = hashlib.sha256(json.dumps({"trip": trip, "items": items}, sort_keys=True).encode()).hexdigest();
    result = BackupPreview(contract_version="person3.backup-preview.v1", mode="mock",
        trip_id=trip["id"], item_id=item_id, base_snapshot=snapshot, trigger=trigger,
        status="no_candidates", message="No matching mock inventory. Demo supports Boston, USD only.",
        options=[], exclusions=[]);
    condition = "If rain makes the original outdoor activity unsuitable" if trigger == "rain" else "If arrival is delayed and the original dinner is missed";
    for candidate in search(trip["destination"], category, now) {
        reason = screen(candidate, trip["currency"], now);
        if reason {
            result.exclusions.append(candidate.id + ": " + reason);
            continue;
        }
        if len(result.options) >= 2 { break; }
        result.options.append(BackupOption(id=snapshot + ":" + item_id + ":" + trigger + ":" + candidate.id,
            label="Plan B" if not result.options else "Plan C", replaced_item_id=item_id,
            candidate=candidate, activation_condition=condition, validation_status="needs_validation",
            validation_notes=[
                "Traveler dietary, pet, child and accessibility requirements are not yet checked.",
                "Full-trip budget, opening hours, travel time and dependencies are not yet checked.",
                "Refund terms and party pricing need evidence. Estimate is synthetic, not additional cash or total trip cost.",
                "Refresh evidence and pass full-trip validation before review or selection."
            ]));
    }
    if result.options {
        result.status = "needs_validation";
        result.message = "Mock suggestions only. Not validated, reserved or applied to your itinerary.";
    }
    return result;
}
