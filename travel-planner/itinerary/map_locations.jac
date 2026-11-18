"""Resolve airport labels from the bundled public coordinates, without flight research."""
import re;
import from tools.airports { AIRPORTS, airport }

def name_key(value: str) -> str {
    return re.sub(r"[^\w]+", " ", value.casefold()).strip();
}

def airport_names -> dict[str, list[str]] {
    names: dict[str, list[str]] = {};
    for (code, value) in AIRPORTS.items() {
        key = name_key(value[0]);
        if key not in names { names[key] = []; }
        names[key].append(code);
    }
    return names;
}

glob AIRPORT_NAMES: dict[str, list[str]] = airport_names();

def airport_location(label: str) -> any {
    value = label.strip();
    codes: list[str] = [];
    bare = re.fullmatch(r"[A-Za-z]{3}", value);
    if bare { codes.append(value.upper()); }
    # Only explicit code notation is parsed; words such as New in New York are not IATA codes.
    leading = re.match(r"^([A-Za-z]{3})\s*[·—–-]\s*\S", value);
    if leading { codes.append(leading.group(1).upper()); }
    for code in re.findall(r"\(([A-Za-z]{3})\)", value) { codes.append(code.upper()); }
    resolved: dict[str, any] = {};
    for code in codes {
        point = airport(code);
        if point is not None { resolved[code] = point; }
    }
    if len(resolved) == 1 { return next(iter(resolved.values())); }
    if len(resolved) > 1 { return None; }
    matching = AIRPORT_NAMES.get(name_key(value), []);
    return airport(matching[0]) if len(matching) == 1 else None;
}

def location_points(trip: dict[str, any], journey: any = None) -> dict[str, any] {
    labels = [trip.get(key, "") for key in ["departure_location", "destination", "return_location"]];
    if isinstance(journey, dict) {
        locations = [journey.get("origin"), journey.get("return_to")];
        locations.extend(journey.get("stops", []));
        for location in locations {
            if isinstance(location, dict) { labels.append(location.get("city", "")); }
        }
    }
    result: dict[str, any] = {};
    for label in labels {
        if not isinstance(label, str) or not label.strip() or label in result { continue; }
        point = airport_location(label);
        if point is not None { result[label] = point; }
    }
    return result;
}
