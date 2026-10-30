"""Versioned P3 -> P4 -> P5 integration contract; all amounts are minor units.

Implemented local integration of the owners' draft interfaces. The scope field
keeps simulated validation distinct from provider-confirmed travel inventory.
"""
import from datetime { datetime }

glob ALTERNATIVE_CONTRACT_VERSION = "roam.alternative-plan.v1";

obj PlanValidation {
    has status: str, scope: str, checks: list[dict[str, any]], projected_total_minor: int | None,
        ledger: dict[str, any] | None, expires_at: str, proposed_items: list[dict[str, any]], transfers: list[dict[str, any]];
}

obj ComparisonResult {
    has contract_version: str, currency: str, original_planned_minor: int | None,
        projected_total_minor: int | None, planned_difference_minor: int | None,
        new_purchase_quotes_minor: int | None, cash_needed_now_minor: int | None,
        retained_paid_minor: int | None, eligible_refund_minor: int | None,
        eligible_cash_refund_minor: int | None, eligible_credit_minor: int | None,
        confirmed_refund_minor: int, refund_loss_minor: int | None,
        time_changes: list[dict[str, any]], changed_item_count: int, unknowns: list[str], notice: str;
}

obj AlternativePlan {
    has plan_contract: str, validator_version: str, id: str, trip_id: str, base_version: int,
        base_snapshot: str, risk_ids: list[str], activation_conditions: list[str], strategy: str,
        replacements: list[dict[str, any]], risks: list[dict[str, any]], validation: PlanValidation,
        comparison: ComparisonResult, checked_at: str, expires_at: str, selectable: bool, scope: str;
    has candidate_id: str = "";
    has review_status: str = "";
    has stale: bool = False;
}

def alternative_from_dict(data: dict[str, any]) -> AlternativePlan {
    if data.get("plan_contract") != ALTERNATIVE_CONTRACT_VERSION { raise ValueError("Unsupported alternative contract"); }
    if type(data.get("base_version")) is not int or data["base_version"] < 1 { raise ValueError("Alternative needs a positive trip version"); }
    if type(data.get("selectable")) is not bool { raise ValueError("Selectable must be boolean"); }
    if data.get("scope") != "integrated_mock" { raise ValueError("Unsupported alternative evidence scope"); }
    if data["selectable"] and data["validation"]["status"] != "valid" { raise ValueError("Selection and validation disagree"); }
    checked = datetime.fromisoformat(data["checked_at"]); expires = datetime.fromisoformat(data["expires_at"]);
    if checked.utcoffset() is None or expires.utcoffset() is None or expires < checked { raise ValueError("Invalid alternative evidence window"); }
    for field in ("original_planned_minor", "projected_total_minor", "new_purchase_quotes_minor", "cash_needed_now_minor", "retained_paid_minor",
        "eligible_cash_refund_minor", "eligible_credit_minor", "confirmed_refund_minor", "refund_loss_minor") {
        value = data["comparison"].get(field);
        if value is not None and (type(value) is not int or value < 0) { raise ValueError("Invalid alternative money: " + field); }
    }
    ids = [candidate["replaces_id"] for candidate in data["replacements"]];
    if not ids or len(set(ids)) != len(ids) { raise ValueError("Alternative must change distinct nodes"); }
    return AlternativePlan(**{**data, "validation": PlanValidation(**data["validation"]), "comparison": ComparisonResult(**data["comparison"])});
}
