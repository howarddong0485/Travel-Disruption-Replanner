"""External map responses must preserve identities, coordinates and coverage gaps."""
import from unittest.mock { patch }
import tools.map_providers as provider;

test "track lookup matches the whole callsign and preserves coverage gaps and timestamps" {
    flight = {"callsign": "ANA117", "flight_id": "abc:2026-11-15T10:00:00Z", "registration": "JA123A",
        "start_ts": "2026-11-15T10:00:00Z", "end_ts": "2026-11-15T11:00:00Z",
        "path": {"type": "MultiLineString", "coordinates": [[[139,35,10000],[140,36,20000]],[[142,37,20000],[143,38,10000]]]},
        "timestamps": [[1794736800,1794736860],[1794739800,1794740400]]};
    with patch.object(provider, "request", return_value={"flights": [flight, {**flight, "callsign": "ANA1170"}], "cursor": None}) as request {
        result = provider.recorded_tracks("ana117", "2026-11-15");
        assert len(result["tracks"]) == 1;
        assert result["tracks"][0]["segments"] == flight["path"]["coordinates"];
        assert result["tracks"][0]["timestamps"] == flight["timestamps"];
        assert request.call_args.kwargs["body"]["start_from"] == "2026-11-15T00:00:00Z";
        assert request.call_args.kwargs["body"]["end_date"] == "2026-11-16T00:00:00Z";
        assert request.call_args.args[1]["User-Agent"].startswith("JacRoam/");
    }
    with patch.object(provider, "request", return_value={"flights": [{**flight, "timestamps": [[1]]}]}) {
        assert provider.recorded_tracks("ANA117", "2026-11-15")["tracks"] == [];
    }
}

test "place search caches repeated queries and excludes invalid coordinates" {
    provider.lookup_cache.clear();
    with patch.object(provider, "request", return_value=[{"display_name": "Kyoto station", "lat": "34.985", "lon": "135.759"},
        {"display_name": "Invalid", "lat": "NaN", "lon": "135"}]) as request {
        result = provider.search_places("Kyoto station");
        assert len(result) == 1;
        assert provider.search_places("KYOTO STATION") == result;
        assert request.call_count == 1;
    }
}

test "flight research uses the request key and search citations without making up a track" {
    with patch.object(provider, "openai_request", return_value={"output": [{"type": "message", "content": [
        {"type": "output_text", "text": "No recorded track available.", "annotations": [
            {"type": "url_citation", "url": "https://example.com/flight", "title": "Flight record"}]}]}]}) as request {
        result = provider.search_flight("CA1210", "2026-11-15", "sk-test-map");
        assert request.call_args.args[1] == "sk-test-map";
        assert request.call_args.args[0]["store"] is False;
        assert result["sources"][0]["url"] == "https://example.com/flight";
        assert result["positions"] == [];
    }
}
