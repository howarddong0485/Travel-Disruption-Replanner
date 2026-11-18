"""Delay impact tests on the shared demo trip (flight DTW to DEN, car pickup, hotel, dinner)."""
import os;
import json;
import from schema.bundle { load_bundle, bundle_from_dict }

glob FIXTURE: str = os.path.join(os.path.dirname(__file__), "..", "fixtures", "demo-trip.json");

def fixture_data -> dict[str, any] {
    with open(FIXTURE, encoding="utf-8") as handle { return json.load(handle); }
}

def by_id(impact: DelayImpact) -> dict[str, DelayEffect] { return {e.node_id: e for e in impact.effects}; }

test "a three-hour flight delay pushes the car pickup and the hotel check-in" {
    impact = delay_impact(load_bundle(FIXTURE), "flight-01", 180);
    effects = by_id(impact);
    assert impact.new_end_local == "2026-10-30T13:35";
    # The flight now lands 13:35 Denver time and the pickup needs 45 min after landing.
    car = effects["car-01"];
    assert car.status == "pushed" and car.minutes_late == 200 and car.new_start_local == "2026-10-30T14:20";
    # The car is returned at 14:50 instead of 11:30, and the drive to the hotel takes 40 min.
    hotel = effects["hotel-01"];
    assert hotel.status == "pushed" and hotel.minutes_late == 30 and hotel.after_id == "car-01";
    assert hotel.evidence_ids == ["ev-est-car-hotel"];
}

test "a late check-in keeps the checkout, so the drive after the stay is unaffected" {
    effects = by_id(delay_impact(load_bundle(FIXTURE), "flight-01", 180));
    assert effects["drive-01"].status == "on_time" and effects["drive-01"].spare_minutes == 0;
}

test "dinner has no link to the flight, so it is listed as unchecked rather than fine" {
    effects = by_id(delay_impact(load_bundle(FIXTURE), "flight-01", 180));
    assert effects["dinner-01"].status == "not_linked";
    assert "hike-01" not in effects and "museum-01" not in effects;
}

test "a short delay is absorbed by the hotel's slack" {
    effects = by_id(delay_impact(load_bundle(FIXTURE), "flight-01", 60));
    assert effects["car-01"].status == "pushed" and effects["car-01"].minutes_late == 80;
    assert effects["hotel-01"].status == "on_time" and effects["hotel-01"].spare_minutes == 90;
}

test "even an on-time flight leaves the pickup 20 minutes short" {
    effects = by_id(delay_impact(load_bundle(FIXTURE), "flight-01", 0));
    assert effects["car-01"].status == "pushed" and effects["car-01"].minutes_late == 20;
}

test "a missing end time leaves every later linked item unresolved" {
    data = fixture_data();
    data["itinerary"]["nodes"][1]["end_local"] = "";
    effects = by_id(delay_impact(bundle_from_dict(data), "flight-01", 180));
    assert effects["car-01"].status == "pushed";
    assert effects["hotel-01"].status == "unresolved" and "no known end time" in effects["hotel-01"].reason;
    assert effects["drive-01"].status == "unresolved";
}

test "a cancelled pickup is skipped and the hotel is no longer reached through it" {
    data = fixture_data();
    data["itinerary"]["nodes"][1]["booking_status"] = "cancelled";
    effects = by_id(delay_impact(bundle_from_dict(data), "flight-01", 180));
    assert "car-01" not in effects;
    assert effects["hotel-01"].status == "not_linked";
}

test "unknown items and negative delays are rejected" {
    with testraises(ValueError) { delay_impact(load_bundle(FIXTURE), "ghost", 30); }
    with testraises(ValueError) { delay_impact(load_bundle(FIXTURE), "flight-01", -5); }
}

test "a shared successor waits for its latest predecessor regardless of edge order" {
    data = fixture_data();
    direct = {"source_id":"flight-01", "target_id":"hotel-01", "relation":"depends_on", "min_transition_minutes":0};
    data["itinerary"]["edges"].insert(0, direct);
    first = by_id(delay_impact(bundle_from_dict(data), "flight-01", 180))["hotel-01"];
    data["itinerary"]["edges"].reverse();
    second = by_id(delay_impact(bundle_from_dict(data), "flight-01", 180))["hotel-01"];
    assert first.status == "pushed" and first.new_start_local == "2026-10-30T15:30";
    assert first.after_id == "car-01" and second.after_id == "car-01";
    assert first.new_start_local == second.new_start_local and first.minutes_late == second.minutes_late;
    assert first.status == second.status and first.evidence_ids == second.evidence_ids;
}
