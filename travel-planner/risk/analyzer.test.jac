"""RiskAnalyzer tests against the shared demo fixture and focused variations of it."""
import os;
import json;
import from schema.common { to_plain }
import from schema.bundle { TripBundle, load_bundle, bundle_from_dict }
import from schema.itinerary { BookingStatus }
import from schema.risk { Severity, FlagStatus }

glob FIXTURE: str = os.path.join(os.path.dirname(__file__), "..", "fixtures", "demo-trip.json");
glob NOW: str = "2026-10-27T12:00:00-04:00";

def fixture_data -> dict[str, any] {
    with open(FIXTURE, encoding="utf-8") as handle { return json.load(handle); }
}

def flag_ids(flags: list[RiskFlag]) -> set[str] { return {f.id for f in flags}; }

test "the demo trip raises exactly the expected flags, most severe first" {
    flags = analyze_trip(load_bundle(FIXTURE), NOW);
    assert flag_ids(flags) == {
        "opening_hours:museum-01",
        "tight_connection:flight-01+car-01",
        "weather_exposure:hike-01",
        "long_drive:drive-01",
        "booking_terms:flight-01",
        "booking_terms:hotel-01",
        "booking_terms:car-01",
        "booking_terms:museum-01"
    };
    assert flags[0].id == "opening_hours:museum-01" and flags[0].severity == Severity.HIGH;
    by_id = {f.id: f for f in flags};
    assert by_id["booking_terms:car-01"].status == FlagStatus.UNRESOLVED;
    assert by_id["booking_terms:museum-01"].status == FlagStatus.UNRESOLVED;
    assert by_id["weather_exposure:hike-01"].probability_pct == 70;
    assert by_id["weather_exposure:hike-01"].evidence_ids == ["ev-forecast-1031"];
}

test "a connection across time zones uses real elapsed time" {
    # Flight lands 10:35 Denver time; pickup is 11:00 Denver time: 25 minutes, not hours.
    flag = [f for f in analyze_trip(load_bundle(FIXTURE), NOW) if f.rule_id == "tight_connection"][0];
    assert "Only 25 min" in flag.summary;
    assert flag.severity == Severity.MEDIUM;
}

test "overlapping items are a high-severity timing conflict" {
    data = fixture_data();
    data["itinerary"]["nodes"][1]["start_local"] = "2026-10-30T10:00";
    flag = [f for f in analyze_trip(bundle_from_dict(data), NOW) if f.rule_id == "tight_connection"][0];
    assert flag.severity == Severity.HIGH and "before" in flag.summary;
}

test "a missing time makes the connection unresolved, not safe" {
    data = fixture_data();
    data["itinerary"]["nodes"][0]["end_local"] = "";
    flag = [f for f in analyze_trip(bundle_from_dict(data), NOW) if f.rule_id == "tight_connection"][0];
    assert flag.status == FlagStatus.UNRESOLVED;
}

test "cancelled items are not analyzed" {
    data = fixture_data();
    data["itinerary"]["nodes"][4]["booking_status"] = "cancelled";
    assert "weather_exposure:hike-01" not in flag_ids(analyze_trip(bundle_from_dict(data), NOW));
}

test "without a forecast an outdoor activity is unresolved" {
    data = fixture_data();
    data["forecasts"] = [];
    flag = [f for f in analyze_trip(bundle_from_dict(data), NOW) if f.rule_id == "weather_exposure"][0];
    assert flag.status == FlagStatus.UNRESOLVED and "no forecast" in flag.summary;
}

test "thresholds come from configuration" {
    relaxed = RiskConfig(long_drive_minutes=360, deadline_soon_hours=24);
    ids = flag_ids(analyze_trip(load_bundle(FIXTURE), NOW, relaxed));
    assert "long_drive:drive-01" not in ids;
    assert "booking_terms:hotel-01" not in ids;
}

test "a drive across the DST fall-back hour counts the repeated hour" {
    # 00:30 to 03:30 local on 2026-11-01 in Denver is 4 hours of driving, not 3.
    data = fixture_data();
    drive = data["itinerary"]["nodes"][6];
    drive["start_local"] = "2026-11-01T00:30";
    drive["end_local"] = "2026-11-01T03:30";
    flags = analyze_trip(bundle_from_dict(data), NOW, RiskConfig(long_drive_minutes=210));
    flag = [f for f in flags if f.rule_id == "long_drive"][0];
    assert "takes 4 h," in flag.summary;
}

test "a closed day is a high-severity hours conflict" {
    data = fixture_data();
    data["place_hours"][2]["closed"] = True;
    flag = [f for f in analyze_trip(bundle_from_dict(data), NOW) if f.id == "opening_hours:museum-01"][0];
    assert "closed on 2026-10-31" in flag.summary;
}

test "flags serialize to plain JSON" {
    text = json.dumps(to_plain(analyze_trip(load_bundle(FIXTURE), NOW)));
    first = json.loads(text)[0];
    assert first["severity"] == "high" and first["category"] == "opening_hours";
    assert first["evaluated_at"] == "2026-10-27T16:00:00+00:00";
}
