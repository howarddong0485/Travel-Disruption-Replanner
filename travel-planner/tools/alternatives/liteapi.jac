"""One-room LiteAPI hotel rates by city, with whole-stay fee accounting."""
import os;
import re;
import hashlib;
import from datetime { date, datetime, timezone }
import from tools.provider_http { request }
import from tools.alternatives.expedia { _cents }

def configuration -> dict[str, any] {
    key = os.environ.get("LITEAPI_API_KEY", "").strip();
    if key and not key.startswith(("sand_", "sandbox_", "prod_")) {
        raise ValueError("Use a LiteAPI sandbox key (sand_ or sandbox_) or production key (prod_)");
    }
    return {"configured": bool(key), "mode": "live" if key.startswith("prod_") else "sandbox"};
}

def guests(occupancy: str) -> dict[str, any] {
    if not re.fullmatch(r"[1-8](?:-[0-9]{1,2}(?:,[0-9]{1,2})*)?", occupancy) {
        raise ValueError("Use one room, e.g. 2 adults or 2-9,4 with child ages");
    }
    parts = occupancy.split("-", 1);
    children = [int(age) for age in parts[1].split(",")] if len(parts) == 2 else [];
    if len(children) > 6 or `any(age > 17 for age in children) { raise ValueError("Use up to six child ages between 0 and 17"); }
    return {"adults": int(parts[0]), "children": children};
}

def normalize(data: any, currency: str, occupancy: str, mode: str, checkin: str, checkout: str) -> dict[str, any] {
    if not isinstance(data, dict) or data.get("error") or data.get("errors") {
        raise RuntimeError("LiteAPI rejected the search or returned an invalid response");
    }
    if "data" not in data or not isinstance(data["data"], list) { raise RuntimeError("LiteAPI returned an unexpected rates structure"); }
    if data.get("sandbox") is True { mode = "sandbox"; }
    if data.get("sandbox") is False and mode == "sandbox" { raise RuntimeError("LiteAPI response does not match sandbox mode"); }
    metadata = {str(h.get("id", h.get("hotelId", ""))): h for h in data.get("hotels", [])};
    offers = []; exclusions = []; party = guests(occupancy);
    for hotel in data["data"] {
        hid = str(hotel.get("hotelId", ""));
        if not hid { continue; }
        for room in hotel.get("roomTypes", []) {
            rates = room.get("rates", []);
            if len(rates) != 1 { exclusions.append(hid + ": one-room quotes only"); continue; }
            rate = rates[0]; retail = rate.get("retailRate", {});
            try {
                totals = retail.get("total", []);
                if len(totals) != 1 or totals[0].get("currency") != currency { raise ValueError("Missing trip-currency total"); }
                total = _cents(totals[0].get("amount"));
                if "taxesAndFees" not in retail { raise ValueError("Missing fee evidence"); }
                for fee in retail.get("taxesAndFees") or [] {
                    if fee.get("included") is False {
                        if fee.get("currency") != currency { raise ValueError("Property fee needs currency conversion"); }
                        total += _cents(fee.get("amount"));
                    } elif fee.get("included") is not True { raise ValueError("Unknown fee inclusion"); }
                }
                if rate.get("adultCount", party["adults"]) != party["adults"] or rate.get("childCount", len(party["children"])) != len(party["children"]) {
                    raise ValueError("Quote occupancy mismatch");
                }
                if not room.get("offerId") { raise ValueError("Missing offer identity"); }
            } except (ValueError, TypeError, KeyError) {
                exclusions.append(hid + ": incomplete price, currency, fee or guest evidence"); continue;
            }
            info = metadata.get(hid, {});
            policies = rate.get("cancellationPolicies") or {};
            identity = hashlib.sha256(str(room["offerId"]).encode()).hexdigest()[:24];
            offers.append({"id": "liteapi:" + hid + ":" + identity, "property_id": hid,
                "title": info.get("name", "Hotel " + hid), "room_name": rate.get("name", "Room"),
                "cost_cents": total, "currency": currency, "checkin": checkin, "checkout": checkout,
                "occupancy": occupancy, "source": "LiteAPI", "origin": "live" if mode == "live" else "provider_test",
                "checked_at": datetime.now(timezone.utc).isoformat(), "requires_price_check": True,
                "current_refundability": policies.get("refundableTag", "unknown"),
                "cancellation_policies": policies, "source_ref": "liteapi://hotel/" + hid});
        }
    }
    offers.sort(key=lambda (offer: any) { offer["cost_cents"]; });
    selected = []; seen = `set();
    for offer in offers {
        if offer["property_id"] not in seen { seen.add(offer["property_id"]); selected.append(offer); }
    }
    return {"offers": selected[:10], "exclusions": exclusions, "mode": mode};
}

def search_hotels(checkin: str, checkout: str, city: str, destination_country: str,
    occupancy: str = "2", currency: str = "USD", nationality: str = "US") -> dict[str, any] {
    config = configuration();
    if not config["configured"] { raise ValueError("Set LITEAPI_API_KEY on the server using your free sandbox key"); }
    first = date.fromisoformat(checkin); last = date.fromisoformat(checkout);
    if first < datetime.now(timezone.utc).date() or not 1 <= (last-first).days <= 28 {
        raise ValueError("Use a current or future check-in and 1–28 nights");
    }
    if not city.strip() or len(city) > 160 { raise ValueError("Enter a destination city"); }
    if not re.fullmatch(r"[A-Z]{2}", destination_country) or not re.fullmatch(r"[A-Z]{2}", nationality) or not re.fullmatch(r"[A-Z]{3}", currency) {
        raise ValueError("Use two-letter country codes and a three-letter currency");
    }
    data = request("https://api.liteapi.travel/v3.0/hotels/rates",
        {"X-API-Key": os.environ["LITEAPI_API_KEY"].strip()},
        {"checkin": checkin, "checkout": checkout, "cityName": city.strip(), "countryCode": destination_country,
            "currency": currency, "guestNationality": nationality, "occupancies": [guests(occupancy)],
            "includeHotelData": True, "maxRatesPerHotel": 1, "limit": 20, "timeout": 6}, "LiteAPI");
    return normalize(data, currency, occupancy, config["mode"], checkin, checkout);
}
