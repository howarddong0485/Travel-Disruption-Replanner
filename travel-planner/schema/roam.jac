"""Adapter from Roam's trip/item records (server/main.jac TripView/ItemView, as JSON dicts) to ItineraryGraph.

Roam stores no end times, time zones, dependencies or policies, so those stay
unknown here: no edges are invented, and the caller supplies the destination's
IANA zone if it is known. Roam's `done` means confirmed for transport and stays
and completed for activities and dining.
"""
import from schema.itinerary { ItineraryNode, ItineraryGraph, NodeKind, BookingStatus }

glob ROAM_KINDS: dict[str, NodeKind] = {
    "activity": NodeKind.ACTIVITY, "food": NodeKind.FOOD,
    "stay": NodeKind.STAY, "transport": NodeKind.TRANSIT
};

def _status(category: str, done: bool) -> BookingStatus {
    if not done { return BookingStatus.PLANNED; }
    return BookingStatus.BOOKED if category in ["stay", "transport"] else BookingStatus.COMPLETED;
}

def node_from_roam_item(item: dict[str, any], currency: str, tz: str, area: str) -> ItineraryNode | None {
    category = str(item["category"]);
    if category not in ROAM_KINDS { return None; }
    date = str(item.get("date", ""));
    time = str(item.get("time", ""));
    cost = int(item.get("cost_cents", 0));
    return ItineraryNode(id=str(item["id"]), kind=ROAM_KINDS[category], title=str(item["title"]),
        tz=tz, start_local=f"{date}T{time}" if date and time else "",
        location=str(item.get("location", "")), area=area,
        booking_status=_status(category, bool(item.get("done", False))),
        currency=currency,
        price_minor=cost if cost > 0 else None,
        paid_minor=(cost if item.get("paid", False) else 0) if cost > 0 else None);
}

"""Build a version-1 graph from a Roam trip and its items. Packing and standalone expenses are skipped."""
def graph_from_roam(trip: dict[str, any], items: list[dict[str, any]], tz: str = "") -> ItineraryGraph {
    currency = str(trip.get("currency", ""));
    area = str(trip.get("destination", ""));
    converted = [node_from_roam_item(i, currency, tz, area) for i in items];
    return ItineraryGraph(trip_id=str(trip["id"]), version=1, nodes=[n for n in converted if n is not None]);
}
