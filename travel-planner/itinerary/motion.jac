"""Animate preview layout changes without changing saved itinerary items."""

def:pub animateTimeline(previous: any, enabled: bool) -> any {
    browser: any = window;
    reduced = browser.matchMedia("(prefers-reduced-motion: reduce)").matches;
    positions: any = {};
    elements: any = document.querySelectorAll(".itinerary-row .travel-item");
    for element in elements {
        old = previous[element.id];
        if old and old.get("animation") { old["animation"].cancel(); }
        rect = element.getBoundingClientRect();
        position: any = {"top": rect.top + browser.scrollY, "left": rect.left + browser.scrollX};
        if enabled and not reduced and old {
            x = old["left"] - position["left"]; y = old["top"] - position["top"];
            if abs(x) > 1 or abs(y) > 1 {
                position["animation"] = element.animate(
                    [{"transform": "translate(" + str(x) + "px, " + str(y) + "px)"}, {"transform": "translate(0, 0)"}],
                    {"duration": 240, "easing": "cubic-bezier(.2,.7,.2,1)"});
            }
        }
        positions[element.id] = position;
    }
    return positions;
}
