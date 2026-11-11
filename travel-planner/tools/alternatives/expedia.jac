"""Expedia Rapid v3 hotel shopping. Read-only; credentials stay server-side."""
import os;
import re;
import time;
import json;
import gzip;
import hashlib;
import urllib.request;
import urllib.parse;
import urllib.error;
import from decimal { Decimal, InvalidOperation }
import from datetime { date, datetime, timezone }

def configuration -> dict[str, any] {
    mode = os.environ.get("EXPEDIA_ENV", "test");
    if mode not in ["test", "live"] { raise ValueError("EXPEDIA_ENV must be test or live"); }
    return {"mode": mode, "configured": bool(os.environ.get("EXPEDIA_API_KEY") and os.environ.get("EXPEDIA_SHARED_SECRET"))};
}

def authorization(key: str, secret: str, timestamp: str) -> str {
    signature = hashlib.sha512((key + secret + timestamp).encode("utf-8")).hexdigest();
    return "EAN APIKey=" + key + ",Signature=" + signature + ",timestamp=" + timestamp;
}

def _get(path: str, params: dict[str, any]) -> any {
    config = configuration();
    if not config["configured"] {
        raise ValueError("Expedia is not configured. Set EXPEDIA_API_KEY and EXPEDIA_SHARED_SECRET on the server.");
    }
    host = "https://test.ean.com" if config["mode"] == "test" else "https://api.ean.com";
    # Fixed hosts and paths; never follow a client-supplied URL or expose provider tokens.
    if path not in ["/v3/properties/availability", "/v3/properties/content"] {
        raise ValueError("Unsupported Expedia operation");
    }
    headers = {"Accept": "application/json", "Accept-Encoding": "gzip",
        "User-Agent": "TravelDisruptionReplanner/0.1",
        "Authorization": authorization(os.environ["EXPEDIA_API_KEY"],
            os.environ["EXPEDIA_SHARED_SECRET"], str(int(time.time())))};
    request = urllib.request.Request(host + path + "?" + urllib.parse.urlencode(params, doseq=True), headers=headers);
    try {
        with urllib.request.urlopen(request, timeout=15) as response {
            body = response.read(4000001);
            if len(body) > 4000000 { raise RuntimeError("Expedia response is too large. Use fewer properties."); }
            if response.headers.get("Content-Encoding", "").lower() == "gzip" { body = gzip.decompress(body); }
            data = json.loads(body);
        }
    } except urllib.error.HTTPError as error {
        # Provider errors may contain request details. Return only a status and actionable category.
        reason = "Check partner credentials and access" if error.code in [401, 403] else "Try again later";
        raise RuntimeError("Expedia HTTP " + str(error.code) + ". " + reason + ".") from None;
    } except (urllib.error.URLError, TimeoutError, OSError, ValueError) {
        raise RuntimeError("Expedia is unavailable or returned invalid data. Please retry.") from None;
    }
    if isinstance(data, dict) and "errors" in data { raise RuntimeError("Expedia rejected the shopping request."); }
    return data;
}

def validate_search(checkin: str, checkout: str, property_ids: list[str], occupancy: str,
    currency: str, country: str) -> None {
    first = date.fromisoformat(checkin); last = date.fromisoformat(checkout);
    if first.isoformat() != checkin or last.isoformat() != checkout or last <= first {
        raise ValueError("Use check-in and later check-out dates in YYYY-MM-DD format");
    }
    if (last - first).days > 28 { raise ValueError("Search up to 28 nights at a time"); }
    if not property_ids or len(property_ids) > 20 or `any(not re.fullmatch(r"[0-9]{1,20}", p) for p in property_ids) {
        raise ValueError("Provide 1–20 numeric Expedia property IDs from a destination shortlist");
    }
    if not re.fullmatch(r"[1-8](?:-[0-9]{1,2}(?:,[0-9]{1,2})*)?", occupancy) {
        raise ValueError("Use one room: adults, optionally followed by child ages, e.g. 2 or 2-9,4");
    }
    if "-" in occupancy {
        ages = occupancy.split("-", 1)[1].split(",");
        if len(ages) > 6 or `any(int(age) > 17 for age in ages) { raise ValueError("Child ages must be 0–17, up to six children"); }
    }
    if not re.fullmatch(r"[A-Z]{3}", currency) or not re.fullmatch(r"[A-Z]{2}", country) {
        raise ValueError("Use a three-letter currency and two-letter traveler country code");
    }
}

def _cents(value: any) -> int {
    try {
        amount = Decimal(str(value));
        if not amount.is_finite() or amount < 0 or amount > 100000000 {
            raise ValueError("Invalid Expedia price");
        }
        cents = amount * 100;
        if cents != cents.to_integral_value() { raise ValueError("Only two-decimal prices are supported"); }
        return int(cents);
    } except InvalidOperation { raise ValueError("Invalid Expedia price"); }
}

def normalize(rows: any, content: any, occupancy: str, currency: str, mode: str,
    checkin: str, checkout: str, property_ids: list[str]) -> dict[str, any] {
    if not isinstance(rows, list) or not isinstance(content, dict) {
        raise RuntimeError("Unexpected Expedia response structure");
    }
    offers = []; exclusions = [];
    checked = datetime.now(timezone.utc).isoformat();
    for property in rows {
        property_id = str(property.get("property_id", ""));
        if property_id not in property_ids { continue; }
        details = content.get(property_id, {});
        if property.get("status", "available") != "available" {
            exclusions.append("Property " + property_id + " is unavailable"); continue;
        }
        for room in property.get("rooms", []) {
            for rate in room.get("rates", []) {
                if rate.get("status", "available") != "available" { continue; }
                if `any(rate.get("sale_scenario", {}).get(flag, False) for flag in ["package", "member", "corporate", "distribution", "mobile_promotion"]) {
                    exclusions.append("Property " + property_id + ": restricted rate requires eligibility evidence"); continue;
                }
                pricing = rate.get("occupancy_pricing", {}).get(occupancy, {});
                # Includes Expedia- and property-collected fees for the entire stay.
                total = pricing.get("totals", {}).get("property_inclusive", {}).get("request_currency", {});
                try {
                    if total.get("currency") != currency { raise ValueError("Missing all-in price in trip currency"); }
                    cents = _cents(total.get("value"));
                } except ValueError {
                    exclusions.append("Property " + property_id + ": missing or unsupported all-in price"); continue;
                }
                if not room.get("id") or not rate.get("id") { continue; }
                offers.append({"id": "expedia:" + property_id + ":" + str(room["id"]) + ":" + str(rate["id"]),
                    "property_id": property_id, "room_id": str(room["id"]), "rate_id": str(rate["id"]),
                    "title": details.get("name", "Expedia property " + property_id),
                    "room_name": room.get("room_name", ""), "cost_cents": cents, "currency": currency,
                    "checkin": checkin, "checkout": checkout, "occupancy": occupancy,
                    "source": "Expedia Rapid", "origin": "live" if mode == "live" else "provider_test",
                    "checked_at": checked, "requires_price_check": True,
                    "refundable": rate.get("refundable"), "current_refundability": rate.get("current_refundability", "unknown"),
                    "cancel_penalties": rate.get("cancel_penalties", []),
                    "nonrefundable_date_ranges": rate.get("nonrefundable_date_ranges", []),
                    "address": details.get("address", {}), "checkin_rules": details.get("checkin", {}),
                    "checkout_rules": details.get("checkout", {}),
                    "source_ref": "expedia-rapid://property/" + property_id + "/room/" + str(room["id"]) + "/rate/" + str(rate["id"])});
            }
        }
    }
    offers.sort(key=lambda (offer: any) { offer["cost_cents"]; });
    # Shortlist distinct properties for Plan B/C; commission has no ranking weight.
    selected = []; seen = `set();
    for offer in offers {
        if offer["property_id"] not in seen {
            seen.add(offer["property_id"]); selected.append(offer);
        }
    }
    return {"offers": selected[:10], "exclusions": exclusions, "mode": mode};
}

def search_hotels(checkin: str, checkout: str, property_ids: list[str], occupancy: str = "2",
    currency: str = "USD", country: str = "US") -> dict[str, any] {
    validate_search(checkin, checkout, property_ids, occupancy, currency, country);
    config = configuration();
    if not config["configured"] { raise ValueError("Set EXPEDIA_API_KEY and EXPEDIA_SHARED_SECRET on the server to use Expedia."); }
    if date.fromisoformat(checkin) < datetime.now(timezone.utc).date() {
        raise ValueError("Expedia searches require a current or future check-in date");
    }
    rows = _get("/v3/properties/availability", {"checkin": checkin, "checkout": checkout,
        "property_id": property_ids, "occupancy": occupancy, "currency": currency,
        "country_code": country, "language": "en-US", "rate_plan_count": "1",
        "sales_channel": "website", "sales_environment": "hotel_only"});
    content = _get("/v3/properties/content", {"property_id": property_ids, "language": "en-US"});
    return normalize(rows, content, occupancy, currency, config["mode"], checkin, checkout, property_ids);
}
