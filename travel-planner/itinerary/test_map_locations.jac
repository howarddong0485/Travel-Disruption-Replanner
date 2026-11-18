"""Airport map lookup must work without a flight listing, network call or saved edits."""
import os;
import tempfile;
import from copy { deepcopy }
import from unittest.mock { patch }
import server.main as api;
import assistant.provider as provider;
import from tools.airports { AIRPORTS, airport }
import from itinerary.map_locations { AIRPORT_NAMES, airport_location, location_points }

test "airport codes and explicit airport labels resolve to the bundled coordinates" {
    expected = airport("DTW");
    for label in ["DTW", "dtw", " DTW ", "Detroit (DTW)", "Detroit (dtw)", "DTW · Detroit Metropolitan Wayne County Airport", "DTW - Detroit", AIRPORTS["DTW"][0], AIRPORTS["DTW"][0].lower()] {
        assert airport_location(label) == expected, label;
    }
    assert expected["lat"] == 42.21377 and expected["lon"] == -83.353786;
}

test "ordinary city words unknown names and ambiguous airport labels are not invented coordinates" {
    for label in ["New York", "New York City", "NEW YORK CITY", "New York City, New York", "Unlisted Departure", "ZZZ", "Detroit (DTW) to New York (JFK)"] {
        assert airport_location(label) is None, label;
    }
    with patch.dict(AIRPORT_NAMES, {"ambiguous airport": ["DTW", "JFK"]}) {
        assert airport_location("Ambiguous Airport") is None;
    }
}

test "map points include exact trip and journey labels without modifying their data" {
    trip = {"departure_location": "dtw", "destination": "New York City", "return_location": "DTW"};
    journey = {"origin": {"city": "Detroit (DTW)", "lat": None, "lon": None},
        "stops": [{"city": "JFK"}, {"city": "Unknown Stop"}], "return_to": {"city": "DTW - Detroit"}};
    original_trip = deepcopy(trip); original_journey = deepcopy(journey);
    points = location_points(trip, journey);
    assert set(points) == {"dtw", "DTW", "Detroit (DTW)", "JFK", "DTW - Detroit"};
    assert points["JFK"] == airport("JFK");
    assert trip == original_trip and journey == original_journey;
}

test "load trip map supplies DTW points before any flights or itinerary are saved" {
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": directory + "/trip.db"}) {
        trip = api.save_trip("Airport-only map", "New York City, New York", "2027-01-01", "2027-01-03", "USD", "5000", departure_location="DTW", return_location="DTW");
        before = api.journey_state(trip.id);
        preview = {"stops": [{"id": "nyc", "city": "LGA", "lat": None, "lon": None}]};
        original_preview = deepcopy(preview);
        with patch.object(provider, "request", side_effect=AssertionError("Map loading must not call AI")) {
            data = api.load_trip_map(trip.id);
            draft_map = api.load_trip_map(trip.id, preview);
        }
        assert data["location_points"]["DTW"] == airport("DTW");
        assert "LGA" not in data["location_points"];
        assert draft_map["location_points"]["LGA"] == airport("LGA");
        assert draft_map["journey"] is None and preview == original_preview;
        assert data["flights"] == {} and data["journey"] is None;
        assert api.journey_state(trip.id) == before and api.list_items(trip.id) == [];
    }
}
