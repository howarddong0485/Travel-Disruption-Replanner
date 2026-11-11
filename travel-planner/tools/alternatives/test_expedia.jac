"""Offline tests against synthetic Rapid-schema responses; no credentials/network."""
import os;
import json;
import gzip;
import hashlib;
import urllib.error;
import from unittest.mock { patch }
import unittest;
import from copy { deepcopy }
import tools.alternatives.expedia as provider;

def fixture(price: str = "123.45", currency: str = "USD", occupancy: str = "2") -> list[dict[str, any]] {
    return [{"property_id": "19248", "status": "available", "rooms": [{"id": "room", "room_name": "Synthetic Queen",
        "rates": [{"id": "rate", "status": "available", "refundable": False,
            "current_refundability": "non_refundable", "occupancy_pricing": {occupancy: {"totals": {
                "inclusive": {"request_currency": {"value": "100.00", "currency": currency}},
                "property_inclusive": {"request_currency": {"value": price, "currency": currency}}
            }}}, "bed_groups": {"bed": {"links": {"price_check": {"href": "/private?token=do-not-return"}}}}
        }]}]}];
}

test "signature matches the documented concatenation" {
    expected = hashlib.sha512(b"example-keyexample-secret1700000000").hexdigest();
    assert provider.authorization("example-key", "example-secret", "1700000000") == "EAN APIKey=example-key,Signature=" + expected + ",timestamp=1700000000";
}

test "whole stay property fees exact money policies and test provenance" {
    result = provider.normalize(fixture(), {"19248": {"name": "Synthetic Hotel"}}, "2", "USD", "test", "2027-01-01", "2027-01-03", ["19248"]);
    offer = result["offers"][0];
    assert offer["cost_cents"] == 12345;
    assert offer["origin"] == "provider_test" and offer["refundable"] is False;
    assert offer["current_refundability"] == "non_refundable";
    assert offer["requires_price_check"] is True;
    assert "do-not-return" not in json.dumps(result);
}

test "missing fees wrong currency malformed price and wrong occupancy are excluded" {
    for rows in [fixture(currency="EUR"), fixture(price="NaN"), fixture(price="-1"), fixture(price="1.234"), fixture(occupancy="3")] {
        result = provider.normalize(rows, {}, "2", "USD", "live", "2027-01-01", "2027-01-03", ["19248"]);
        assert not result["offers"] and result["exclusions"];
    }
    rows = fixture(); del rows[0]["rooms"][0]["rates"][0]["occupancy_pricing"]["2"]["totals"]["property_inclusive"];
    assert not provider.normalize(rows, {}, "2", "USD", "test", "2027-01-01", "2027-01-03", ["19248"])["offers"];
}

test "rank distinct properties by total and ignore commissions" {
    rows = fixture("200.00") + fixture("100.00"); rows[1]["property_id"] = "20321";
    rows[0]["rooms"][0]["rates"][0]["marketing_fee"] = "900";
    result = provider.normalize(rows, {}, "2", "USD", "live", "2027-01-01", "2027-01-03", ["19248", "20321"]);
    assert [o["property_id"] for o in result["offers"]] == ["20321", "19248"];
    assert result["offers"][0]["origin"] == "live";
}

test "restricted rates and empty inventory produce no candidates" {
    rows = fixture(); rows[0]["rooms"][0]["rates"][0]["sale_scenario"] = {"member": True};
    result = provider.normalize(rows, {}, "2", "USD", "live", "2027-01-01", "2027-01-03", ["19248"]);
    assert not result["offers"] and result["exclusions"];
    assert provider.normalize([], {}, "2", "USD", "live", "2027-01-01", "2027-01-03", ["19248"])["offers"] == [];
}

test "search validates inputs and never silently falls back without credentials" {
    check = unittest.TestCase();
    with patch.dict(os.environ, {}, clear=True) {
        with patch.object(provider.urllib.request, "urlopen") as request {
            with check.assertRaises(ValueError) { provider.search_hotels("2027-01-01", "2027-01-03", ["19248"]); }
            request.assert_not_called();
        }
        assert provider.configuration() == {"mode": "test", "configured": False};
    }
    for args in [
        ("2027-01-03", "2027-01-01", ["19248"], "2", "USD", "US"),
        ("2027-01-01", "2027-01-03", ["https://example.com"], "2", "USD", "US"),
        ("2027-01-01", "2027-01-03", ["19248"], "2-18", "USD", "US")
    ] {
        with check.assertRaises(ValueError) { provider.validate_search(*args); }
    }
}

test "signed gzip request and error redaction" {
    check = unittest.TestCase();
    with patch.dict(os.environ, {"EXPEDIA_API_KEY": "example-key", "EXPEDIA_SHARED_SECRET": "secret-not-for-output", "EXPEDIA_ENV": "test"}) {
        with patch.object(provider.urllib.request, "urlopen") as opened {
            response = opened.return_value.__enter__.return_value;
            response.headers = {"Content-Encoding": "gzip"};
            response.read.return_value = gzip.compress(b"[]");
            assert provider._get("/v3/properties/availability", {"property_id": ["1", "2"]}) == [];
            request = opened.call_args.args[0];
            assert request.full_url.startswith("https://test.ean.com/v3/properties/availability?");
            assert "property_id=1&property_id=2" in request.full_url;
            assert request.get_header("Authorization").startswith("EAN APIKey=example-key,");
        }
        with patch.object(provider.urllib.request, "urlopen", side_effect=urllib.error.HTTPError("secret-not-for-output", 403, "secret-not-for-output", {}, None)) {
            try { provider._get("/v3/properties/availability", {}); assert False; }
            except RuntimeError as error {
                assert "403" in str(error) and "secret-not-for-output" not in str(error);
            }
        }
    }
}
