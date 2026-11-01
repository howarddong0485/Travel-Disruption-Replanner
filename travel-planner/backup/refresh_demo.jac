"""A deterministic refresh sequence, independent of the server and saved trips."""
import json;
import from datetime { datetime, timedelta, timezone }
import from backup.validation_fixtures { run_fixture }

with entry:__main__ {
    now = datetime(2026, 11, 10, 12, tzinfo=timezone.utc);
    day = "2026-11-17";
    for (index, change) in enumerate(["unchanged", "price_increase", "sold_out", "all_sold_out",
        "expired_evidence", "provider_failure", "partial_failure", "unchanged"]) {
        result = run_fixture(now=now + timedelta(minutes=index), inventory_change=change, sample_date=day);
        print(json.dumps({"inventory": change, "date": result["trip_date"], "summary": result["summary"],
            "options": [{"id": r["candidate_id"], "status": r["status"],
                "cost": r["cost"]["projected_total_minor"], "provider": r["refresh_state"],
                "changes": r["changes"]} for r in result["results"]]}));
    }
}
