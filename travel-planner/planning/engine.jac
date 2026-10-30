"""Risk-driven, bounded multi-node backup generation with versioned output."""
import json;
import itertools;
import from copy { deepcopy }
import from dataclasses { asdict, replace }
import from datetime { datetime, timedelta }
import from hashlib { sha256 }
import from zoneinfo { ZoneInfo }
import from backup.validation { instant, evidence_problem }
import from backup.validation_models { RiskContext, Evidence, Moment, Replacement, ScheduledItem }
import from planning.context { parse_evidence, parse_moment }
import from planning.validation { validate_plan }
import from planning.comparison { compare_plan }
import from planning.agent { select_backup_plans }
import from tools.alternatives.catalog { search }
import from schema.alternative { ALTERNATIVE_CONTRACT_VERSION as PLAN_CONTRACT, alternative_from_dict }
import from schema.common { to_plain }

glob VALIDATION_VERSION = "roam.planning-validator.v1";
glob SUPPORTED_REASONS = ("weather", "timing", "long_drive", "opening_hours", "booking_terms", "closure", "cancellation", "traveler_change", "budget_change", "inventory_change");

def risk_context(context: dict[str, any], risk: dict[str, any], item_id: str) -> RiskContext {
    proof = parse_evidence(risk.get("evidence"));
    if proof is None {
        sources = {record.id: record for record in context["bundle"].evidence};
        deadlines = dict(context["facts"].get("evidence_deadlines", {}));
        for item in context["trip"].items {
            if item.evidence is not None { deadlines["item-facts:" + item.id] = item.evidence.expires_at; }
        }
        records = [sources[key] for key in risk.get("evidence_ids", []) if key in sources];
        if risk["status"] == "flagged" and records and all(key in deadlines for key in risk["evidence_ids"]) {
            proof = Evidence(";".join(r.source_ref for r in records), max(datetime.fromisoformat(r.retrieved_at) for r in records).isoformat(),
                min(datetime.fromisoformat(deadlines[key]) for key in risk["evidence_ids"]).isoformat());
        }
    }
    before = parse_moment(risk["not_before"]) if risk.get("not_before") else None;
    status = risk["status"];
    if risk["category"] == "timing" and risk.get("source") == "traveler_report" and before is None {
        status = "unresolved";
    }
    return RiskContext(risk["id"], context["trip_id"], item_id, risk["category"], status, proof, before);
}

def at_time(moment: Moment, at: datetime) -> Moment {
    local = at.astimezone(ZoneInfo(moment.zone));
    return Moment(local.replace(tzinfo=None).isoformat(timespec="minutes"), moment.zone, local.fold);
}

def generate_plans(context: dict[str, any], now: datetime, risk_ids: list[str] | None = None,
    max_plans: int = 4, use_llm: bool = False, excluded_ids: set[str] | None = None) -> dict[str, any] {
    if type(max_plans) is not int or not 1 <= max_plans <= 5 { raise ValueError("Choose between one and five plans"); }
    available = {risk["id"]: risk for risk in context["risks"]};
    selected = list(available.values()) if risk_ids is None else [available[key] for key in risk_ids if key in available];
    if risk_ids is not None and (len(set(risk_ids)) != len(risk_ids) or set(risk_ids) - set(available)) { raise ValueError("Choose current risk IDs for this trip"); }
    selected = [risk for risk in selected if risk["category"] in SUPPORTED_REASONS];
    originals = {item.id: item for item in context["trip"].items};
    targets: dict[str, any] = {};
    for risk in selected {
        ids = risk["node_ids"][-1:] if risk["category"] == "timing" else risk["node_ids"];
        for key in ids {
            if key in originals and (key not in targets or targets[key]["status"] != "flagged") { targets[key] = risk; }
        }
    }
    primary_ids = set(targets);
    # Connected flexible items may stay in place, move, or be replaced. Fixed
    # boundaries remain in the whole itinerary and are never relaxed.
    pending_ids = list(targets);
    while pending_ids {
        parent = pending_ids.pop(0);
        if targets[parent]["category"] not in ("timing", "long_drive", "closure", "cancellation", "opening_hours") { continue; }
        for dependency in context["trip"].dependencies {
            child = dependency.to_id;
            if dependency.from_id == parent and child not in targets and child in originals and not originals[child].fixed and not originals[child].completed {
                targets[child] = {**targets[parent], "category": "timing", "summary": "Connected arrangement after " + originals[parent].title};
                pending_ids.append(child);
            }
        }
    }
    warnings = [];
    groups = []; ordered_ids = list(targets);
    if len(ordered_ids) > 8 { raise ValueError("Split requests into at most eight affected nodes"); }
    for key in ordered_ids {
        item = originals[key]; active_risk = risk_context(context, targets[key], key);
        options: list[any] = [None] if key not in primary_ids else [];
        if not item.fixed and not item.completed {
            try {
                earliest = item.start;
                if active_risk.not_before is not None and instant(active_risk.not_before) > instant(earliest) { earliest = active_risk.not_before; }
                for dependency in context["trip"].dependencies {
                    if dependency.to_id == key {
                        boundary = instant(originals[dependency.from_id].end) + timedelta(minutes=dependency.buffer_minutes);
                        if boundary > instant(earliest) { earliest = at_time(earliest, boundary); }
                    }
                }
                options.extend(search(context["trip"], item, earliest, context["state"]["trip"]["destination"], now,
                    context["facts"].get("inventory_change", "unchanged")));
                if active_risk.trigger in ("timing", "opening_hours", "traveler_change", "budget_change") {
                    for minutes in (30, 60) {
                        beginning = max(instant(earliest), instant(item.start) + timedelta(minutes=minutes));
                        if item.hours and active_risk.trigger == "opening_hours" {
                            window = item.hours[0];
                            beginning = instant(window.start) if minutes == 30 else instant(window.end) - (instant(item.end) - instant(item.start));
                        }
                        duration = instant(item.end) - instant(item.start);
                        shifted = replace(item, start=at_time(item.start, beginning), end=at_time(item.end, beginning + duration));
                        options.append(Replacement("reschedule:" + key + ":" + str(minutes), key, shifted, (), "", "reschedule"));
                    }
                }
            } except ValueError { warnings.append("Missing or ambiguous timing prevents searching for " + item.title); }
        } else { warnings.append(item.title + " is fixed or completed and cannot be changed"); }
        groups.append(options);
    }
    plans = []; rejected = []; seen = set(); searched = 0;
    combinations = itertools.product(*groups) if groups and all(groups) else [];
    for combination in itertools.islice(combinations, 256) {
        searched += 1;
        candidates = tuple(candidate for candidate in combination if candidate is not None);
        if not candidates { continue; }
        # Propagate timing through the candidate subgraph before full validation.
        for _ in range(len(candidates)) {
            current_nodes = {**originals, **{candidate.replaces_id: candidate.item for candidate in candidates}};
            adjusted = [];
            for candidate in candidates {
                beginning = instant(candidate.item.start);
                for dependency in context["trip"].dependencies {
                    if dependency.to_id == candidate.replaces_id {
                        beginning = max(beginning, instant(current_nodes[dependency.from_id].end) + timedelta(minutes=dependency.buffer_minutes));
                    }
                }
                duration = instant(candidate.item.end) - instant(candidate.item.start);
                adjusted.append(replace(candidate, item=replace(candidate.item, start=at_time(candidate.item.start, beginning), end=at_time(candidate.item.end, beginning + duration))));
            }
            candidates = tuple(adjusted);
        }
        activations = tuple(risk_context(context, targets[c.replaces_id], c.replaces_id) for c in candidates);
        checked = validate_plan(context["trip"], activations, candidates, now);
        identity: list[dict[str, any]] = [{"item": asdict(c.item), "action": c.action, "provider_id": c.provider_id} for c in candidates];
        # Observation timestamps are excluded from plan identity.
        for item_data in identity { item_data["item"].pop("evidence", None); }
        signature = json.dumps(identity, sort_keys=True);
        if signature in seen { continue; }
        seen.add(signature);
        key = sha256(signature.encode()).hexdigest()[:20];
        plan: dict[str, any] = {"plan_contract": PLAN_CONTRACT, "validator_version": VALIDATION_VERSION, "id": "plan-" + key, "trip_id": context["trip_id"],
            "base_version": context["trip_version"], "base_snapshot": context["base_snapshot"],
            "risk_ids": [r.id for r in activations], "activation_conditions": [targets[c.replaces_id]["summary"] for c in candidates],
            "strategy": "reschedule" if all(c.action == "reschedule" for c in candidates) else "replace_connected_items" if len(candidates) > 1 else "replace_item",
            "replacements": [asdict(c) for c in candidates], "risks": [asdict(r) for r in activations],
            "validation": checked, "checked_at": now.isoformat(), "expires_at": checked["expires_at"],
            "selectable": checked["status"] == "valid", "scope": "integrated_mock",
            "comparison": compare_plan(context, candidates, checked, now)};
        plan = to_plain(alternative_from_dict(plan));
        if excluded_ids and plan["id"] in excluded_ids { continue; }
        if checked["status"] == "invalid" { rejected.append({"plan_id": plan["id"], "checks": [c for c in checked["checks"] if c["status"] == "fail"], "recorded_plan": plan}); }
        else { plans.append(plan); }
    }
    if groups and all(groups) and 256 < __import__("math").prod(len(group) for group in groups) { warnings.append("Search stopped after 256 combinations; more plans may exist"); }
    plans.sort(key=lambda (plan: dict[str, any]) -> tuple[int, int, str] {
        return (0 if plan["selectable"] else 1, plan["comparison"]["changed_item_count"], plan["id"]);
    });
    mode = "deterministic"; explanation = "Distinct strategies and providers, with passing plans shown first.";
    if use_llm and any(plan["selectable"] for plan in plans) {
        try {
            eligible = {plan["id"]: plan for plan in plans if plan["selectable"]};
            choice = select_backup_plans({"limit": max_plans, "interests": list(context["trip"].profile.interests),
                "plans": [{"id": p["id"], "strategy": p["strategy"], "comparison": p["comparison"]} for p in eligible.values()]});
            if not choice.plan_ids or len(choice.plan_ids) > max_plans or len(set(choice.plan_ids)) != len(choice.plan_ids) or set(choice.plan_ids) - set(eligible) {
                raise ValueError("Unsupported model plan IDs");
            }
            plans = [eligible[key] for key in choice.plan_ids]; mode = "llm"; explanation = choice.explanation;
        } except Exception { warnings.append("Model selection unavailable or invalid; showing deterministic validated plans"); }
    }
    message = "Review the proposed changes before accepting." if plans else "No supported plan fits the available facts and constraints.";
    if not plans and context["facts"].get("inventory_change") == "provider_failure" { message = "Availability could not be refreshed. Please try again."; }
    if context["state"]["trip"]["destination"].strip().lower() not in ("boston", "boston, ma", "boston, usa") or context["trip"].currency != "USD" {
        message = "The demo inventory currently supports Boston trips in USD.";
    }
    if not plans and rejected and all(any(c["code"] == "budget" for c in rejection["checks"]) for rejection in rejected) {
        message = "No alternative fits your trip budget. Adjust the budget or itinerary and try again.";
    }
    return {"contract_version": PLAN_CONTRACT, "validator_version": VALIDATION_VERSION, "trip_id": context["trip_id"], "base_version": context["trip_version"],
        "base_snapshot": context["base_snapshot"], "plans": plans[:max_plans], "evaluated_count": searched,
        "rejections": rejected, "warnings": warnings, "mode": mode, "explanation": explanation,
        "input_snapshot": {"state": deepcopy(context["state"]), "facts": deepcopy(context["facts"])}, "message": message};
}
