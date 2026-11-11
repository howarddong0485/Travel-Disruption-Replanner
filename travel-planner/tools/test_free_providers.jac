"""Offline LiteAPI and Geoapify contract tests; all returned places/rates are synthetic."""
import os;
import json;
import unittest;
import urllib.error;
import from copy { deepcopy }
import from unittest.mock { patch }
import tools.alternatives.liteapi as lite;
import tools.geoapify as geo;
import tools.provider_http as transport;
import replan.expedia as planner;
import from replan.test_expedia { state_fixture }

def rates_fixture -> dict[str, any] {
    return {"sandbox": True, "hotels": [{"id": "hotel-1", "name": "Synthetic City Hotel"}],
        "data": [{"hotelId": "hotel-1", "roomTypes": [{"offerId": "private-offer-token",
            "rates": [{"name": "Synthetic Queen", "adultCount": 2, "childCount": 0,
                "retailRate": {"total": [{"amount": "110.00", "currency": "USD"}],
                    "taxesAndFees": [{"included": True, "amount": "10.00", "currency": "USD"},
                        {"included": False, "amount": "12.34", "currency": "USD"}]},
                "cancellationPolicies": {"refundableTag": "NRFN"}}]}]}]};
}

test "LiteAPI adds excluded fees once and preserves sandbox source" {
    result = lite.normalize(rates_fixture(), "USD", "2", "sandbox", "2027-01-01", "2027-01-03");
    offer = result["offers"][0];
    assert offer["cost_cents"] == 12234;
    assert offer["title"] == "Synthetic City Hotel" and offer["origin"] == "provider_test";
    assert offer["current_refundability"] == "NRFN";
    assert "private-offer-token" not in json.dumps(result);
}

test "LiteAPI excludes unknown fees currency mismatch nonfinite totals and wrong party" {
    base = rates_fixture();
    for changes in [
        {"total": [{"amount": "NaN", "currency": "USD"}], "taxesAndFees": None},
        {"total": [{"amount": "10", "currency": "EUR"}], "taxesAndFees": None},
        {"total": [{"amount": "10", "currency": "USD"}]},
        {"total": [{"amount": "10", "currency": "USD"}], "taxesAndFees": [{"included": False, "amount": "1", "currency": "EUR"}]}
    ] {
        data = deepcopy(base); data["data"][0]["roomTypes"][0]["rates"][0]["retailRate"] = changes;
        assert not lite.normalize(data, "USD", "2", "sandbox", "2027-01-01", "2027-01-03")["offers"];
    }
    assert not lite.normalize(base, "USD", "3", "sandbox", "2027-01-01", "2027-01-03")["offers"];
}

test "LiteAPI city search sends structured guests and never Expedia IDs" {
    with patch.dict(os.environ, {"LITEAPI_API_KEY": "sand_example"}) {
        with patch.object(lite, "request", return_value={"sandbox": True, "data": []}) as request {
            result = lite.search_hotels("2027-01-01", "2027-01-03", "Boston", "US", "2-9,4");
            body = request.call_args.args[2];
            assert body["occupancies"] == [{"adults": 2, "children": [9, 4]}];
            assert body["cityName"] == "Boston" and "hotelIds" not in body;
            assert result["offers"] == [];
        }
    }
}

test "missing keys and mode mismatches do not call providers or claim live inventory" {
    check = unittest.TestCase();
    with patch.dict(os.environ, {}, clear=True) {
        assert lite.configuration() == {"configured": False, "mode": "sandbox"};
        with patch.object(lite, "request") as request {
            with check.assertRaises(ValueError) { lite.search_hotels("2027-01-01", "2027-01-03", "Boston", "US"); }
            request.assert_not_called();
        }
        with check.assertRaises(ValueError) { geo.search("Boston"); }
    }
    data = rates_fixture(); data["sandbox"] = False;
    with check.assertRaises(RuntimeError) { lite.normalize(data, "USD", "2", "sandbox", "2027-01-01", "2027-01-03"); }
}

test "Geoapify resolves destination then searches by category without inventing price" {
    location = {"features": [{"properties": {"lon": -71.06, "lat": 42.36, "formatted": "Boston, MA, USA"}}]};
    places = {"features": [{"properties": {"place_id": "geo-1", "name": "Synthetic Restaurant", "formatted": "Boston", "lon": -71.05, "lat": 42.35}}]};
    with patch.dict(os.environ, {"GEOAPIFY_API_KEY": "example-geo-secret"}) {
        with patch.object(geo, "request", side_effect=[location, places]) as request {
            result = geo.search("Boston", "US", "restaurants");
            assert "catering.restaurant" in request.call_args.args[0];
            assert "circle%3A-71.06%2C42.36%2C5000" in request.call_args.args[0];
            assert result["resolved_destination"] == "Boston, MA, USA";
            assert result["places"][0]["cost_cents"] is None;
            assert result["places"][0]["availability"] == "unknown";
            assert "example-geo-secret" not in json.dumps(result);
        }
        with patch.object(geo, "request", return_value={"features": []}) as request {
            assert geo.search("Unknown", "US", "hotels")["status"] == "not_found";
            assert request.call_count == 1;
        }
    }
}

test "transport errors redact URL keys" {
    with patch.object(transport.urllib.request, "urlopen", side_effect=urllib.error.URLError("apiKey=secret-value")) {
        try { transport.request("https://api.geoapify.com/v2/places?apiKey=secret-value", {}, provider="Geoapify"); assert False; }
        except RuntimeError as error { assert "secret-value" not in str(error); }
    }
}

test "LiteAPI backup uses provider quotes and unchanged state with downstream scheduling" {
    state = state_fixture(); original = deepcopy(state);
    shopping = lite.normalize(rates_fixture(), "USD", "2", "sandbox", "2027-01-01", "2027-01-03");
    with patch.object(planner, "search_liteapi", return_value=shopping) {
        result = planner.plans(state, "hotel", "2027-01-03", [], mode="replan", kind="delayed", delay_minutes=120,
            provider="liteapi", city="Boston", destination_country="US");
        proposal = result["proposals"][0];
        assert proposal["projected_total_cents"] == 35234;
        assert proposal["retained_paid_cents"] == 20000;
        assert proposal["mode"] == "liteapi_sandbox";
        assert proposal["changes"][1]["after"]["time"] == "20:00";
        assert state == original;
    }
}
