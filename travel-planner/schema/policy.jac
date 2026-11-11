"""Booking-specific refund and cancellation terms with evidence.

PROPOSAL (Person 2). A policy is a list of tiers: each tier covers cancellations
made before its deadline, and the first tier whose deadline has not passed applies.
Every None field is unknown and must stay unknown; it is never read as zero,
refundable, or free.
"""
import from schema.common { Origin }

enum RefundForm: str { CASH = "cash", CREDIT = "credit", NONE = "none", UNKNOWN = "unknown" }

"""Terms for cancelling before a deadline.

The deadline is either an absolute local time (deadline_local in the policy's zone)
or relative to the booked service's start (hours_before_start). With neither, the
tier lasts until the service starts.
"""
obj CancellationTier {
    has evidence_id: str;
    has deadline_local: str = "";
    has hours_before_start: int | None = None;
    has refund_percent: int | None = None;
    has fee_minor: int | None = None;
    has refund_form: RefundForm = RefundForm.UNKNOWN;
}

obj RefundPolicy {
    has id: str;
    has booking_node_id: str;
    has scope: str;
    has tz: str;
    has currency: str;
    has retrieved_at: str;
    has tiers: list[CancellationTier] = [];
    has no_show_refund_percent: int | None = None;
    has no_show_evidence_id: str = "";
    has extraction_confidence: float | None = None;
    has origin: Origin = Origin.MOCK;
    has source_text: str = "";
    has unknowns: list[str] = [];
}
