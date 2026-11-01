"""Deterministic storage-free proof using the actual P1/P2/P3 integration."""
import json;
import from datetime { datetime, timezone }
import from planning.fixtures { sample_state }
import from planning.context { build_context }
import from planning.engine { generate_plans }

with entry {
    now = datetime(2026, 10, 30, 12, tzinfo=timezone.utc);
    for scenario in ("rain", "arrival_delay", "connected_closures") {
        (state, facts) = sample_state(now, "arrival_delay" if scenario == "arrival_delay" else "rain");
        if scenario == "connected_closures" {
            facts["manual_risks"].append({"id": "dinner-closure", "category": "closure", "node_ids": ["dinner"],
                "summary": "Restaurant reported closed", "evidence": facts["items"]["dinner"]["evidence"]});
        }
        context = build_context(state, facts, now); result = generate_plans(context, now, max_plans=5);
        print(json.dumps({"scenario": scenario, "base_version": result["base_version"], "evaluated_count": result["evaluated_count"],
            "plans": [{"id": plan["id"], "strategy": plan["strategy"], "changed_nodes": [c["replaces_id"] for c in plan["replacements"]],
                "status": plan["validation"]["status"], "total_minor": plan["comparison"]["projected_total_minor"],
                "new_purchase_quotes_minor": plan["comparison"]["new_purchase_quotes_minor"]} for plan in result["plans"]]}, sort_keys=True));
    }
}
