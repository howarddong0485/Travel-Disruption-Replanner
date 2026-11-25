"""Default place-search text and readable place-search failures for the map popup."""

def _words(value: str) -> str {
    return " ".join(value.lower().replace(",", " ").replace(".", " ").split());
}

"""The venue (or title) plus the city, unless the venue already names that city."""
def:pub placeQuery(location: str, title: str, destination: str) -> str {
    venue = location if location and not location.startswith("fixture:") else title;
    city = destination.strip();
    if not city or not venue { return venue or city; }
    return venue if _words(city) in _words(venue) else venue + ", " + city;
}

"""Keep a short service message; never show a gateway's HTML page or a raw HTTP status."""
def:pub placeSearchError(error: str) -> str {
    marker = " failed: ";
    offset = error.find(marker);
    detail = (error[offset + len(marker):] if offset >= 0 else error).strip();
    lowered = detail.lower();
    unreachable = ["<html", "<!doctype", "<body", "gateway", "timed out", "timeout",
        "http 5", "unavailable", "failed to fetch", "networkerror"];
    for hint in unreachable {
        if hint in lowered {
            return ("Place search did not respond. Try again, or shorten the search to the venue and city. "
                + "You can also set the pin yourself under Add or edit photo and map pin in the List view.");
        }
    }
    return detail[:300] if detail else "Place search failed. Try again.";
}
