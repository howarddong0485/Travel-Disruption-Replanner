"""Cancellation tracking tests with a fixed clock and hand-checkable amounts."""
import from schema.common { parse_instant }
import from schema.itinerary { NodeKind, BookingStatus }

def hotel_node(paid: int | None = 52000) -> ItineraryNode {
    return ItineraryNode(id="hotel-01", kind=NodeKind.STAY, title="Hotel", tz="America/Denver",
        start_local="2026-10-30T15:00", end_local="2026-11-01T11:00",
        booking_status=BookingStatus.BOOKED, currency="USD", price_minor=52000, paid_minor=paid);
}

def hotel_policy -> RefundPolicy {
    return RefundPolicy(id="pol-hotel-01", booking_node_id="hotel-01", scope="flexible rate",
        tz="America/Denver", currency="USD", retrieved_at="2026-10-27T09:00:00-04:00",
        tiers=[
            CancellationTier(evidence_id="ev-free", deadline_local="2026-10-28T18:00",
                refund_percent=100, fee_minor=0, refund_form=RefundForm.CASH),
            CancellationTier(evidence_id="ev-late", refund_percent=100, fee_minor=26000,
                refund_form=RefundForm.CASH)
        ],
        no_show_refund_percent=0, no_show_evidence_id="ev-noshow");
}

test "before the free-cancellation deadline the full amount comes back" {
    s = evaluate_cancellation(hotel_policy(), hotel_node(), parse_instant("2026-10-27T12:00:00-04:00"));
    assert s.state == CancelState.FREE_CANCEL_OPEN;
    assert s.refund_if_cancel_now_minor == 52000;
    assert s.next_deadline_local == "2026-10-28T18:00-06:00";
    assert s.minutes_to_next_deadline == 32 * 60;
    assert s.evidence_ids == ["ev-free"];
}

test "after the deadline one night is charged" {
    s = evaluate_cancellation(hotel_policy(), hotel_node(), parse_instant("2026-10-28T18:00:00-06:00"));
    assert s.state == CancelState.PARTIAL_REFUND;
    assert s.fee_if_cancel_now_minor == 26000;
    assert s.refund_if_cancel_now_minor == 26000;
    assert s.next_deadline_local == "" and s.minutes_to_next_deadline is None;
}

test "once the stay has started no-show terms apply" {
    s = evaluate_cancellation(hotel_policy(), hotel_node(), parse_instant("2026-10-30T15:00:00-06:00"));
    assert s.state == CancelState.SERVICE_STARTED;
    assert s.refund_if_cancel_now_minor == 0;
    assert s.evidence_ids == ["ev-noshow"];
}

test "an unknown amount paid leaves the refund unknown but keeps the terms" {
    s = evaluate_cancellation(hotel_policy(), hotel_node(paid=None), parse_instant("2026-10-27T12:00:00-04:00"));
    assert s.state == CancelState.FREE_CANCEL_OPEN;
    assert s.refund_if_cancel_now_minor is None;
    assert "amount paid" in s.unknowns;
}

test "a missing refund percentage is unknown, never assumed" {
    policy = RefundPolicy(id="p", booking_node_id="hotel-01", scope="", tz="America/Denver",
        currency="USD", retrieved_at="2026-10-27T09:00:00-04:00",
        tiers=[CancellationTier(evidence_id="ev-vague")], unknowns=["refund percentage"]);
    s = evaluate_cancellation(policy, hotel_node(), parse_instant("2026-10-27T12:00:00-04:00"));
    assert s.state == CancelState.UNKNOWN;
    assert s.refund_if_cancel_now_minor is None;
    assert s.unknowns.count("refund percentage") == 1;
}

test "a policy with no tiers is unknown" {
    policy = RefundPolicy(id="p", booking_node_id="hotel-01", scope="", tz="America/Denver",
        currency="USD", retrieved_at="2026-10-27T09:00:00-04:00");
    s = evaluate_cancellation(policy, hotel_node(), parse_instant("2026-10-27T12:00:00-04:00"));
    assert s.state == CancelState.UNKNOWN;
    assert "terms after the last stated deadline" in s.unknowns;
}

test "a deadline relative to the start resolves against the booking's start" {
    policy = RefundPolicy(id="p", booking_node_id="hotel-01", scope="", tz="America/Denver",
        currency="USD", retrieved_at="2026-10-27T09:00:00-04:00",
        tiers=[CancellationTier(evidence_id="ev-48h", hours_before_start=48, refund_percent=100, fee_minor=0),
            CancellationTier(evidence_id="ev-late", refund_percent=0)]);
    open_now = evaluate_cancellation(policy, hotel_node(), parse_instant("2026-10-28T14:59:00-06:00"));
    assert open_now.state == CancelState.FREE_CANCEL_OPEN;
    assert open_now.next_deadline_local == "2026-10-28T15:00-06:00";
    assert open_now.minutes_to_next_deadline == 1;
    closed = evaluate_cancellation(policy, hotel_node(), parse_instant("2026-10-28T15:00:00-06:00"));
    assert closed.state == CancelState.NO_REFUND;
}

test "a relative deadline with an unknown start is unknown" {
    booking = hotel_node();
    booking.start_local = "";
    policy = RefundPolicy(id="p", booking_node_id="hotel-01", scope="", tz="America/Denver",
        currency="USD", retrieved_at="2026-10-27T09:00:00-04:00",
        tiers=[CancellationTier(evidence_id="ev-48h", hours_before_start=48, refund_percent=100, fee_minor=0)]);
    s = evaluate_cancellation(policy, booking, parse_instant("2026-10-27T12:00:00-04:00"));
    assert s.state == CancelState.UNKNOWN;
    assert "cancellation deadline" in s.unknowns and "service start time" in s.unknowns;
}

test "an ambiguous deadline during the DST fall-back hour uses the earlier instant" {
    # 01:30 on 2026-11-01 happens twice in Denver: 07:30Z (MDT) and 08:30Z (MST).
    booking = hotel_node();
    booking.start_local = "2026-11-02T15:00";
    policy = RefundPolicy(id="p", booking_node_id="hotel-01", scope="", tz="America/Denver",
        currency="USD", retrieved_at="2026-10-27T09:00:00-04:00",
        tiers=[CancellationTier(evidence_id="ev-free", deadline_local="2026-11-01T01:30", refund_percent=100, fee_minor=0),
            CancellationTier(evidence_id="ev-late", refund_percent=0)]);
    s = evaluate_cancellation(policy, booking, parse_instant("2026-11-01T07:45:00Z"));
    assert s.state == CancelState.NO_REFUND;
}

test "percentage refunds round down to the minor unit" {
    assert refund_amount(999, 50, 0) == 499;
    assert refund_amount(1000, 50, 600) == 0;
    assert refund_amount(None, 0, None) == 0;
    assert refund_amount(1000, 100, None) is None;
}
