"""Cancellation tracking: what cancelling a booking now would refund, and when that changes.

Deterministic: the caller supplies `now`, so tests and demos use a fixed clock.
Refund amounts are integer minor units; a percentage refund rounds down, so the
estimate never overstates what comes back.
"""
import from datetime { datetime, timedelta }
import from schema.common { local_to_instant, minutes_between, to_local_text }
import from schema.itinerary { ItineraryNode }
import from schema.policy { RefundPolicy, CancellationTier, RefundForm }

enum CancelState: str {
    FREE_CANCEL_OPEN = "free_cancel_open",
    PARTIAL_REFUND = "partial_refund",
    NO_REFUND = "no_refund",
    UNKNOWN = "unknown",
    SERVICE_STARTED = "service_started"
}

obj CancellationStatus {
    has policy_id: str;
    has node_id: str;
    has state: CancelState;
    has currency: str;
    has paid_minor: int | None = None;
    has refund_if_cancel_now_minor: int | None = None;
    has fee_if_cancel_now_minor: int | None = None;
    has refund_form: RefundForm = RefundForm.UNKNOWN;
    has next_deadline_local: str = "";
    has minutes_to_next_deadline: int | None = None;
    has unknowns: list[str] = [];
    has evidence_ids: list[str] = [];
}

"""The UTC instant a tier stops applying, or None when it lasts until the service starts or cannot be resolved."""
def tier_deadline(tier: CancellationTier, policy: RefundPolicy, start: datetime | None) -> datetime | None {
    if tier.deadline_local { return local_to_instant(tier.deadline_local, policy.tz); }
    if tier.hours_before_start is not None and start is not None {
        return start - timedelta(hours=tier.hours_before_start);
    }
    return None;
}

"""Refund for a percentage and fee; None if either input that matters is unknown."""
def refund_amount(paid: int | None, percent: int | None, fee: int | None) -> int | None {
    if percent == 0 { return 0; }
    if percent is None or paid is None or fee is None { return None; }
    return max(0, (paid * percent) // 100 - fee);
}

def _note(unknowns: list[str], what: str) -> None {
    if what not in unknowns { unknowns.append(what); }
}

def _state(percent: int | None, fee: int | None) -> CancelState {
    if percent is None { return CancelState.UNKNOWN; }
    if percent == 0 { return CancelState.NO_REFUND; }
    if percent == 100 and fee == 0 { return CancelState.FREE_CANCEL_OPEN; }
    if fee is None { return CancelState.UNKNOWN; }
    return CancelState.PARTIAL_REFUND;
}

def evaluate_cancellation(policy: RefundPolicy, booking: ItineraryNode, now: datetime) -> CancellationStatus {
    start = local_to_instant(booking.start_local, booking.tz);
    status = CancellationStatus(policy_id=policy.id, node_id=booking.id,
        state=CancelState.UNKNOWN, currency=policy.currency, paid_minor=booking.paid_minor,
        unknowns=list(dict.fromkeys(policy.unknowns)));
    if booking.paid_minor is None { _note(status.unknowns, "amount paid"); }

    if start is not None and now >= start {
        status.state = CancelState.SERVICE_STARTED;
        status.refund_if_cancel_now_minor = refund_amount(booking.paid_minor, policy.no_show_refund_percent, 0);
        if policy.no_show_refund_percent is None { _note(status.unknowns, "no-show refund"); }
        if policy.no_show_evidence_id { status.evidence_ids.append(policy.no_show_evidence_id); }
        return status;
    }
    if start is None { _note(status.unknowns, "service start time"); }

    timed: list[tuple[datetime | None, CancellationTier]] = [(tier_deadline(t, policy, start), t) for t in policy.tiers];
    unresolved = [t for (d, t) in timed if d is None and (t.deadline_local or t.hours_before_start is not None)];
    if unresolved {
        _note(status.unknowns, "cancellation deadline");
        status.evidence_ids.extend([t.evidence_id for t in unresolved]);
        return status;
    }
    ordered = sorted(timed, key=lambda (pair: tuple[datetime | None, CancellationTier]) -> tuple[int, datetime] {
        return (1, now) if pair[0] is None else (0, pair[0]);
    });
    for (deadline, tier) in ordered {
        if deadline is not None and now >= deadline { continue; }
        status.state = _state(tier.refund_percent, tier.fee_minor);
        status.refund_if_cancel_now_minor = refund_amount(booking.paid_minor, tier.refund_percent, tier.fee_minor);
        status.fee_if_cancel_now_minor = tier.fee_minor;
        status.refund_form = tier.refund_form;
        status.evidence_ids.append(tier.evidence_id);
        if tier.refund_percent is None { _note(status.unknowns, "refund percentage"); }
        if tier.fee_minor is None and tier.refund_percent != 0 { _note(status.unknowns, "cancellation fee"); }
        if deadline is not None {
            status.next_deadline_local = to_local_text(deadline, policy.tz);
            status.minutes_to_next_deadline = minutes_between(now, deadline);
        }
        return status;
    }
    _note(status.unknowns, "terms after the last stated deadline");
    return status;
}
