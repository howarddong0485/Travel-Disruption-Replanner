"""P5-facing deterministic comparison; potential refunds never become available cash."""
import from datetime { datetime }
import from backup.validation { instant, evidence_problem }
import from backup.validation_models { Replacement, Evidence }
import from policy.cancellation { evaluate_cancellation }
import from schema.common { to_plain }
import from backup.changes { quote_problem }

def compare_plan(context: dict[str, any], replacements: tuple[Replacement, ...], checked: dict[str, any], now: datetime) -> dict[str, any] {
    originals = {item.id: item for item in context["trip"].items};
    new_quotes = []; retained = 0; refunds = []; credits = []; unknowns = []; times = [];
    for candidate in replacements {
        old = originals[candidate.replaces_id]; new = candidate.item;
        if candidate.action == "replace" {
            if new.cost_minor is None or evidence_problem(new.evidence, now) { unknowns.append("Replacement quote is incomplete or expired"); }
            else { new_quotes.append(new.cost_minor); }
            if old.paid_minor is None { unknowns.append("Original payment is unknown"); }
            else { retained += old.paid_minor; }
            booking = context["bundle"].itinerary.find_node(old.id);
            policy = context["bundle"].policy(booking.policy_id) if booking and booking.policy_id else None;
            if policy is not None {
                cancel = evaluate_cancellation(policy, booking, now);
                cited = [e for e in context["bundle"].evidence if e.id in cancel.evidence_ids];
                fresh = len(cited) == len(cancel.evidence_ids) and len(cited) > 0;
                for source in cited {
                    proof = Evidence(source.source_ref, source.retrieved_at, context["facts"].get("evidence_deadlines", {}).get(source.id, ""));
                    if evidence_problem(proof, now) { fresh = False; }
                }
                if fresh and not cancel.unknowns and cancel.currency == context["trip"].currency and cancel.refund_if_cancel_now_minor is not None and
                    cancel.refund_form.value in ("cash", "credit", "none") {
                    refunds.append(cancel.refund_if_cancel_now_minor if cancel.refund_form.value == "cash" else 0);
                    credits.append(cancel.refund_if_cancel_now_minor if cancel.refund_form.value == "credit" else 0);
                }
                else { unknowns.append("Refund entitlement needs current policy evidence"); }
            } elif old.paid_minor { unknowns.append("Refund terms for an original payment are unknown"); }
            else { refunds.append(0); }
        }
        try {
            shift = int((instant(new.start) - instant(old.start)).total_seconds() / 60);
            duration = int(((instant(new.end) - instant(new.start)) - (instant(old.end) - instant(old.start))).total_seconds() / 60);
            times.append({"item_id": old.id, "start_shift_minutes": shift, "duration_change_minutes": duration});
        } except ValueError { unknowns.append("Timing comparison needs explicit timezone and duration"); }
    }
    baseline = context["ledger"]["planned_cents"] + context["ledger"]["contingency_cents"]
        if all(not quote_problem(item, context["trip"], now) for item in context["trip"].items) else None;
    total = checked["projected_total_minor"];
    proposed_cash = sum(new_quotes) if len(new_quotes) == sum(c.action == "replace" for c in replacements) else None;
    refund_known = not any("Refund" in reason or "payment" in reason for reason in unknowns);
    eligible = sum(refunds) if refund_known else None;
    return {"contract_version": "roam.comparison.v1", "currency": context["trip"].currency,
        "original_planned_minor": baseline, "projected_total_minor": total,
        "planned_difference_minor": total - baseline if total is not None and baseline is not None else None,
        "new_purchase_quotes_minor": proposed_cash, "cash_needed_now_minor": None,
        "retained_paid_minor": None if any("payment" in reason for reason in unknowns) else retained,
        "eligible_refund_minor": eligible, "eligible_cash_refund_minor": eligible, "eligible_credit_minor": sum(credits) if refund_known else None, "confirmed_refund_minor": 0,
        "refund_loss_minor": retained - eligible if eligible is not None else None,
        "time_changes": times, "changed_item_count": len(replacements), "unknowns": unknowns + ["Payment timing is not supplied; new purchase quotes are not an amount due now"],
        "notice": "Synthetic quotes only. Eligible refunds have not been received and are not deducted from total cost or cash needs."};
}
