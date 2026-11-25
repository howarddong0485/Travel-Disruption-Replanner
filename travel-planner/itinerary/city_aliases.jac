"""Decide when two map city labels name the same place, so markers and filters show it once."""

"""The lower-case city name (with common aliases folded) and the optional region after the first comma."""
def:pub cityParts(label: str) -> list[str] {
    parts = [part.strip().lower() for part in label.split(",")];
    city = parts[0] if len(parts) > 0 else "";
    if city in ["nyc", "new york city"] { city = "new york"; }
    region = parts[1] if len(parts) > 1 else "";
    return [city, region];
}

def located(point: any) -> bool {
    return point.get("lat") is not None and point.get("lon") is not None;
}

"""Same city name, and either nearby coordinates or, without coordinates, no conflicting region.

Portland, OR and Portland, ME stay apart: their coordinates are far apart and their regions differ.
"""
def:pub sameCity(left: any, right: any) -> bool {
    a = cityParts(left.get("label", "")); b = cityParts(right.get("label", ""));
    if not a[0] or a[0] != b[0] { return False; }
    if located(left) and located(right) {
        return abs(left["lat"] - right["lat"]) + abs(left["lon"] - right["lon"]) < 1.0;
    }
    return not a[1] or not b[1] or a[1] == b[1];
}

"""Keep the first point's coordinates; show the more specific label, such as Boston, MA over Boston."""
def:pub mergedCity(existing: any, incoming: any) -> any {
    label = existing["label"];
    if not cityParts(label)[1] and cityParts(incoming.get("label", ""))[1] { label = incoming["label"]; }
    if located(existing) { return {**existing, "label": label}; }
    return {**incoming, "label": label};
}
