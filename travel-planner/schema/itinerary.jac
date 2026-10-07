"""Itinerary graph and the context evidence that risk rules check against.

PROPOSAL (Person 2): the minimum ItineraryNode/Edge/Graph fields that policy and
risk analysis read. The shared-schema owner should extend these rather than fork
them. Times are "YYYY-MM-DDTHH:MM" in the node's IANA zone; "" means unknown.
"""

enum NodeKind: str {
    FLIGHT = "flight",
    TRANSIT = "transit",
    DRIVE = "drive",
    CAR_RENTAL = "car_rental",
    STAY = "stay",
    FOOD = "food",
    ACTIVITY = "activity"
}

enum BookingStatus: str {
    PLANNED = "planned",
    BOOKED = "booked",
    COMPLETED = "completed",
    CANCELLED = "cancelled"
}

enum EdgeRelation: str {
    PRECEDES = "precedes",
    DEPENDS_ON = "depends_on",
    ALTERNATIVE = "alternative"
}

"""One itinerary item. end_tz differs from tz only for items that cross zones, such as flights."""
obj ItineraryNode {
    has id: str;
    has kind: NodeKind;
    has title: str;
    has tz: str = "";
    has start_local: str = "";
    has end_local: str = "";
    has end_tz: str = "";
    has location: str = "";
    has area: str = "";
    has booking_status: BookingStatus = BookingStatus.PLANNED;
    has fixed: bool = False;
    has policy_id: str = "";
    has currency: str = "";
    has price_minor: int | None = None;
    has paid_minor: int | None = None;
    has tags: list[str] = [];
    has evidence_ids: list[str] = [];

    def end_zone -> str { return self.end_tz or self.tz; }
}

"""A time or dependency relation. min_transition_minutes is None when the source has no stated minimum."""
obj ItineraryEdge {
    has source_id: str;
    has target_id: str;
    has relation: EdgeRelation;
    has min_transition_minutes: int | None = None;
}

obj ItineraryGraph {
    has trip_id: str;
    has version: int;
    has nodes: list[ItineraryNode] = [];
    has edges: list[ItineraryEdge] = [];

    def find_node(node_id: str) -> ItineraryNode | None {
        for n in self.nodes { if n.id == node_id { return n; } }
        return None;
    }
}

"""Opening hours for the place a node visits on one local date. close_local before open_local means past midnight."""
obj PlaceHours {
    has node_id: str;
    has date: str;
    has evidence_id: str;
    has closed: bool = False;
    has open_local: str = "";
    has close_local: str = "";
}

"""A forecast window for an area. Precipitation probability is None when the source does not provide it."""
obj WeatherForecast {
    has id: str;
    has area: str;
    has tz: str;
    has start_local: str;
    has end_local: str;
    has condition: str;
    has evidence_id: str;
    has precip_probability_pct: int | None = None;
}

"""Estimated door-to-door time between the end of one node and the start of another."""
obj TravelEstimate {
    has from_node_id: str;
    has to_node_id: str;
    has mode: str;
    has minutes: int;
    has evidence_id: str;
}
