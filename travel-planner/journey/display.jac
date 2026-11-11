"""City context and chronological ordering for saved and previewed journeys."""
def:pub journeyCity(item: any, fallback: str) -> str {
    if item and item.journey {
        return item.journey.get("city") or item.journey.get("from_city") or fallback;
    }
    return fallback;
}

def:pub itineraryOrder(item: any, preview: any) -> str {
    change: any = preview["changes"].get(item.id) if preview else None;
    local = change["start"]["local"] if change else (item.date or "9999") + "T" + (item.time or "99:99");
    if not item.journey { return local; }
    zone = change["start"].get("zone") if change else item.journey["zone"];
    browser: any = window;
    try {
        # Resolve the wall clock in its IANA zone, independent of browser zone.
        # Saved and proposed route times have already passed DST validation.
        target = browser.Date.parse(local + "Z");
        instant = target;
        formatter = new(browser.Intl.DateTimeFormat, "en-CA", {"timeZone": zone,
            "year": "numeric", "month": "2-digit", "day": "2-digit",
            "hour": "2-digit", "minute": "2-digit", "second": "2-digit", "hourCycle": "h23"});
        for count in range(3) {
            parts: any = {};
            for part in formatter.formatToParts(new(Date, instant)) { parts[part.type] = part.value; }
            wall = browser.Date.parse(parts["year"] + "-" + parts["month"] + "-" + parts["day"] + "T" +
                parts["hour"] + ":" + parts["minute"] + ":" + parts["second"] + "Z");
            instant += target - wall;
        }
        return new(Date, instant).toISOString();
    } except Exception { return local; }
}
