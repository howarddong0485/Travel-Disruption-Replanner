"""Fixture loading and structural-check tests."""
import os;
import json;

glob FIXTURE: str = os.path.join(os.path.dirname(__file__), "..", "fixtures", "demo-trip.json");

def fixture_data -> dict[str, any] {
    with open(FIXTURE, encoding="utf-8") as handle { return json.load(handle); }
}

test "the demo fixture loads with no structural problems" {
    bundle = load_bundle(FIXTURE);
    assert len(bundle.itinerary.nodes) == 7;
    flight = bundle.itinerary.find_node("flight-01");
    hotel_terms = bundle.policy("pol-hotel-01");
    assert flight is not None and flight.kind == NodeKind.FLIGHT;
    assert hotel_terms is not None and hotel_terms.tiers[1].fee_minor == 26000;
    assert structural_problems(bundle) == [];
}

test "every structural problem is reported together" {
    data = fixture_data();
    nodes = data["itinerary"]["nodes"];
    nodes.append(dict(nodes[0]));
    nodes[1]["tz"] = "Mars/Olympus";
    nodes[2]["start_local"] = "2026-10-30 15:00";
    data["itinerary"]["edges"].append({"source_id": "flight-01", "target_id": "ghost", "relation": "precedes"});
    data["policies"][0]["tiers"][0]["evidence_id"] = "ev-missing";
    message = "";
    try { bundle_from_dict(data); }
    except ValueError as e { message = str(e); }
    assert "duplicate node id 'flight-01'" in message;
    assert "unknown time zone 'Mars/Olympus'" in message;
    assert "'2026-10-30 15:00' is not YYYY-MM-DDTHH:MM" in message;
    assert "unknown node 'ghost'" in message;
    assert "unknown evidence 'ev-missing'" in message;
}

test "unknown enum values are rejected" {
    data = fixture_data();
    data["itinerary"]["nodes"][0]["kind"] = "teleport";
    with testraises(ValueError) { bundle_from_dict(data); }
}
