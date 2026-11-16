"""New trips, independent requests, ambiguity and stale edits use the same map lifecycle."""
import os;
import tempfile;
import from unittest.mock { patch }
import server.main as api;
import tools.map_providers as providers;

def new_trip(title: str = "Ordinary new trip") -> any {
    return api.save_trip(title, "Reykjavik, Iceland", "2026-12-10", "2026-12-12");
}

glob MATCH: dict[str, any] = {"label": "Hallgrimskirkja, Reykjavik, Iceland", "lat": 64.1417, "lon": -21.9267};

test "new ordinary trip automatically gets persistent coordinates without changing its plan" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(folder, "travel.sqlite3")}) {
        trip = new_trip();
        item = api.save_item(trip.id, "Hallgrimskirkja", date="2026-12-10", location="Hallgrimskirkja");
        before = api.load_trip_map(trip.id)["trip_version"];
        with patch.object(providers, "search_places", return_value=[MATCH]) as search {
            assert api.resolve_trip_map_places(trip.id)["located"] == 1;
            # Every API call opens a new connection, as a fresh browser would.
            assert api.load_trip_map(trip.id)["pins"][item.id]["lat"] == MATCH["lat"];
            assert api.resolve_trip_map_places(trip.id)["located"] == 0;
            assert search.call_count == 1;
            assert search.call_args.args[0] == "Hallgrimskirkja, Reykjavik, Iceland";
        }
        assert api.load_trip_map(trip.id)["trip_version"] == before;
        assert api.list_items(trip.id)[0].title == item.title;
    }
}

test "ambiguous places persist candidates and only retry on request or address changes" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(folder, "travel.sqlite3")}) {
        trip = new_trip(); item = api.save_item(trip.id, "Cafe", date="2026-12-10", location="Cafe");
        with patch.object(providers, "search_places", return_value=[MATCH, {**MATCH, "lat": 64.15}]) as search {
            api.resolve_trip_map_places(trip.id);
            state = api.load_trip_map(trip.id);
            assert item.id not in state["pins"];
            assert state["lookups"][item.id]["status"] == "needs_confirmation";
            api.resolve_trip_map_places(trip.id); assert search.call_count == 1;
        }
        with patch.object(providers, "search_places", return_value=[MATCH]) {
            assert api.resolve_trip_map_places(trip.id, True)["located"] == 1;
        }
        api.save_item(trip.id, "Different place", item_id=item.id, date="2026-12-10", location="New address");
        assert item.id not in api.load_trip_map(trip.id)["lookups"];
        assert item.id not in api.load_trip_map(trip.id)["pins"];
    }
}

test "bounded geocoding preserves manual coordinates photos and other trips" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(folder, "travel.sqlite3")}) {
        trip = new_trip(); other = new_trip("Another traveler workspace");
        foreign = api.save_item(other.id, "Other place", location="Elsewhere");
        manual = api.save_item(trip.id, "User located place", location="User address");
        api.save_place_details(trip.id, manual.id, manual.location, 0,
            {"latitude": 64.1, "longitude": -21.9, "photo_url": "https://example.com/photo.jpg", "photo_source": "Photographer"});
        for index in range(5) { api.save_item(trip.id, "Stop " + str(index), location="Place " + str(index)); }
        with patch.object(providers, "search_places", return_value=[MATCH]) {
            assert api.resolve_trip_map_places(trip.id)["remaining"] == 1;
            assert api.resolve_trip_map_places(trip.id)["remaining"] == 0;
        }
        assert len(api.load_trip_map(trip.id)["pins"]) == 6;
        assert foreign.id not in api.load_trip_map(other.id)["pins"];
        assert api.get_place_details(trip.id, manual.id)["photo_source"] == "Photographer";
        assert api.get_place_details(trip.id, manual.id)["latitude"] == 64.1;
    }
}

test "flight tracks persist across requests and stale dates or revisions cannot reuse them" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(folder, "travel.sqlite3")}) {
        trip = new_trip(); other = new_trip("Other trip");
        item = api.save_item(trip.id, "FI100", category="transport", date="2026-12-10", location="Flight");
        track = {"id": "observed", "callsign": "ICE100", "registration": "TF-ABC", "segments": [[[-21.9,64.1],[-20.9,63.1]]], "timestamps": [[1,2]], "source": "https://adsb.aero", "start": "2026-12-10T10:00:00Z", "end": "2026-12-10T11:00:00Z", "checked_at": "2026-12-11T00:00:00Z"};
        with patch.object(providers, "recorded_tracks", return_value={"tracks": [track]}) {
            saved = api.save_trip_flight_track(trip.id, item.id, item.title, item.location, item.date, "ICE100", item.date, "observed");
            assert saved["revision"] == 1;
            assert api.load_trip_map(trip.id)["tracks"][item.id]["track"] == track;
            caught = False;
            try { api.save_trip_flight_track(trip.id, item.id, item.title, item.location, item.date, "ICE100", item.date, "observed"); }
            except ValueError { caught = True; }
            assert caught;
            caught = False;
            try { api.save_trip_flight_track(other.id, item.id, item.title, item.location, item.date, "ICE100", item.date, "observed"); }
            except ValueError { caught = True; }
            assert caught;
        }
        api.save_item(trip.id, item.title, category="transport", date="2026-12-11", location=item.location, item_id=item.id);
        assert api.load_trip_map(trip.id)["tracks"][item.id]["track"] is None;
        api.delete_item(trip.id, item.id);
        assert api.load_trip_map(trip.id)["tracks"] == {};
    }
}

test "a place edited during lookup cannot receive the old address coordinates" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(folder, "travel.sqlite3")}) {
        trip = new_trip(); item = api.save_item(trip.id, "Old venue", location="Old address");
        def concurrent_edit(query: str) -> list[any] {
            api.save_item(trip.id, "New venue", item_id=item.id, location="New address");
            return [MATCH];
        }
        with patch.object(providers, "search_places", side_effect=concurrent_edit) {
            assert api.resolve_trip_map_places(trip.id)["located"] == 0;
        }
        assert item.id not in api.load_trip_map(trip.id)["pins"];
        assert item.id not in api.load_trip_map(trip.id)["lookups"];
    }
}

test "provider outages remain visible and do not retry on every page refresh" {
    with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(folder, "travel.sqlite3")}) {
        trip = new_trip(); item = api.save_item(trip.id, "Hallgrimskirkja", location="Hallgrimskirkja");
        with patch.object(providers, "search_places", side_effect=RuntimeError("Provider offline")) as search {
            api.resolve_trip_map_places(trip.id); api.resolve_trip_map_places(trip.id);
            assert search.call_count == 1;
            assert api.load_trip_map(trip.id)["lookups"][item.id]["status"] == "unavailable";
        }
        with patch.object(providers, "search_places", return_value=[MATCH]) {
            assert api.resolve_trip_map_places(trip.id, True)["located"] == 1;
        }
    }
}
