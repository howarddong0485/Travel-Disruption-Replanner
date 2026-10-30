"""Synthetic places for filter tests and demos. No real venues.

Every place was "checked" at FIXTURE_NOW and expires 15 minutes later.
Each function returns a new object.
"""
import datetime;
import from filter.models { PlaceFacts }

glob FIXTURE_NOW: str = "2026-10-06T12:00:00+00:00";
glob FIXTURE_EXPIRES: str = "2026-10-06T12:15:00+00:00";

def fixture_clock -> datetime.datetime {
    return datetime.datetime.fromisoformat(FIXTURE_NOW);
}

def _place(id: str, category: str, eligibility: dict[str, bool | None],
    child_min_age: int | None, child_max_age: int | None) -> PlaceFacts {
    return PlaceFacts(id=id, category=category, eligibility=eligibility,
        child_min_age=child_min_age, child_max_age=child_max_age,
        source_ref="mock://filter-v1/" + id, checked_at=FIXTURE_NOW, expires_at=FIXTURE_EXPIRES);
}

"""Serves vegetarian food, allows pets, admits all children."""
def veggie_cafe -> PlaceFacts {
    return _place("veggie-cafe", "food",
        {"dietary:vegetarian": True, "pet:pet_friendly": True}, 0, 17);
}

"""Allows pets but has no vegetarian options."""
def steakhouse -> PlaceFacts {
    return _place("steakhouse", "food",
        {"dietary:vegetarian": False, "pet:pet_friendly": True}, 0, 17);
}

"""A restaurant nobody has checked: no eligibility facts at all."""
def unverified_bistro -> PlaceFacts {
    return _place("unverified-bistro", "food", {}, None, None);
}

"""A museum that allows pets and admits children aged 4 and up."""
def science_museum -> PlaceFacts {
    return _place("science-museum", "activity",
        {"pet:pet_friendly": True, "child:adults_only": False}, 4, 17);
}
