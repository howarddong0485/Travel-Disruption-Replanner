"""Bounded synthetic search by requirements, location and time; stable provider IDs.

This catalog supplies explicit whole-party quotes and operating windows. Routes
are supplied only between the demo's fixture venues; arbitrary saved locations
never receive invented routing evidence.
"""
import from dataclasses { replace }
import from datetime { datetime, timedelta }
import from backup.validation { instant }
import from backup.validation_models { Evidence, Moment, Replacement, ScheduledItem, TripContext, Window, Transfer }

glob CATALOG = {
    "activity": [("indoor-gallery", "Indoor discovery gallery", 2000, 60, 0),
        ("science-hall", "Covered botanical hall", 3000, 75, 15),
        ("covered-market", "Covered market visit", 1500, 60, 0),
        ("quiet-library", "Quiet library visit", 500, 60, 0)],
    "food": [("late-bistro", "Late vegetarian dinner", 2000, 60, 0),
        ("evening-cafe", "Hotel dining room", 3000, 60, 30),
        ("late-noodle-house", "Late noodle dinner", 1800, 60, 10),
        ("rooftop-grill", "Rooftop grill dinner", 1200, 60, 0)],
    "transport": [("shuttle", "Accessible shared shuttle", 1000, 45, 0),
        ("taxi", "Accessible direct transfer", 1800, 25, 0),
        ("rail", "Accessible rail transfer", 800, 60, 15)],
    "stay": [("flexible-hotel", "Flexible check-in hotel", 6500, 30, 0),
        ("central-hotel", "Central accessible hotel", 7500, 30, 0),
        ("guesthouse", "Accessible guesthouse", 5500, 30, 15)]
};

def observe(trip: TripContext, target: ScheduledItem, provider_id: str, start: Moment,
    now: datetime, inventory_change: str = "unchanged") -> Replacement {
    rows = CATALOG.get(target.category, []);
    matches = [row for row in rows if row[0] == provider_id];
    if len(matches) != 1 { raise LookupError("Provider inventory is no longer available"); }
    if inventory_change not in ("unchanged", "price_increase", "sold_out", "all_sold_out", "expired_evidence", "provider_failure", "partial_failure") {
        raise ValueError("Unsupported inventory transition");
    }
    first = provider_id == rows[0][0];
    if inventory_change == "provider_failure" or (inventory_change == "partial_failure" and first) { raise TimeoutError("Synthetic provider unavailable"); }
    (key, title, unit, duration, offset) = matches[0];
    beginning = instant(start);
    ending = beginning + timedelta(minutes=duration);
    import from zoneinfo { ZoneInfo }
    local_end = ending.astimezone(ZoneInfo(start.zone));
    end = Moment(local_end.replace(tzinfo=None).isoformat(timespec="minutes"), start.zone, local_end.fold);
    evidence = Evidence("fixture://boston/catalog/" + key, now.isoformat(), (now + timedelta(minutes=15)).isoformat());
    if inventory_change == "expired_evidence" and first {
        evidence = replace(evidence, checked_at=(now - timedelta(minutes=16)).isoformat(), expires_at=now.isoformat());
    }
    party = trip.profile.adults + len(trip.profile.child_ages) if type(trip.profile.adults) is int and trip.profile.adults > 0 else None;
    price = unit * party if party is not None else None;
    if price is not None and inventory_change == "price_increase" and first { price += 20000; }
    rules = {"dietary:vegetarian": True, "pet:dog": True, "accessibility:wheelchair": True, "indoor": True};
    if key == "quiet-library" { rules.update({"pet:dog": False, "accessibility:wheelchair": False}); }
    if key == "rooftop-grill" { rules.update({"dietary:vegetarian": False, "accessibility:wheelchair": False}); }
    day = start.local[:10];
    hours = (Window(Moment(day + ("T18:30" if target.category == "food" else "T00:00"), start.zone), Moment(day + "T23:59", start.zone)),);
    unavailable = inventory_change == "all_sold_out" or (inventory_change == "sold_out" and first);
    item = ScheduledItem(target.id, title, target.category, "fixture:" + key, start, end,
        trip.currency, price, party, True, evidence, "unavailable" if unavailable else "available", hours, rules, 0, 17);
    return Replacement("provider:" + target.id + ":" + key, target.id, item, (), key);
}

def search(trip: TripContext, target: ScheduledItem, earliest: Moment, destination: str,
    now: datetime, inventory_change: str = "unchanged") -> tuple[Replacement, ...] {
    if destination.strip().lower() not in ("boston", "boston, ma", "boston, usa") or trip.currency != "USD" { return (); }
    import from zoneinfo { ZoneInfo }
    result = [];
    for row in CATALOG.get(target.category, []) {
        start_at = instant(earliest) + timedelta(minutes=row[4]);
        if target.category == "food" {
            dinner = instant(Moment(earliest.local[:10] + "T19:00", earliest.zone));
            start_at = max(start_at, dinner + timedelta(minutes=row[4]));
        }
        local = start_at.astimezone(ZoneInfo(earliest.zone));
        start = Moment(local.replace(tzinfo=None).isoformat(timespec="minutes"), earliest.zone, local.fold);
        try { result.append(observe(trip, target, row[0], start, now, inventory_change)); }
        except (LookupError, TimeoutError) { continue; }
    }
    return tuple(result);
}

def routes(trip: TripContext, nodes: tuple[ScheduledItem, ...], now: datetime) -> tuple[Transfer, ...] {
    ordered = sorted([item for item in nodes if item.blocks_time], key=lambda (item: ScheduledItem) -> datetime { instant(item.start); });
    supplied = {(route.from_id, route.to_id, route.from_venue, route.to_venue): route for route in trip.transfers};
    result = [];
    for (left, right) in zip(ordered, ordered[1:]) {
        route = supplied.get((left.id, right.id, left.venue, right.venue));
        if route is None {
            known_venues = {"fixture:arrival", "fixture:activity", "fixture:dinner", "fixture:hotel"} | {"fixture:" + row[0] for rows in CATALOG.values() for row in rows};
            known = left.venue in known_venues and right.venue in known_venues;
            proof = Evidence("fixture://boston/routes/" + left.venue + "/" + right.venue, now.isoformat(),
                (now + timedelta(minutes=15)).isoformat()) if known else None;
            route = Transfer(left.id, right.id, left.venue, right.venue, 20 if known else None, proof);
        }
        result.append(route);
    }
    return tuple(result);
}
