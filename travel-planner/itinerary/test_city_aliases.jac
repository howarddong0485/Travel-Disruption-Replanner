"""City alias rules used by the trip map's markers and filters."""
import from itinerary.city_aliases { cityParts, sameCity, mergedCity }

glob BOSTON: dict[str, any] = {"label": "Boston", "lat": 42.36, "lon": -71.06};
glob BOSTON_MA: dict[str, any] = {"label": "Boston, MA", "lat": 42.3601, "lon": -71.0589};

test "a state suffix, letter case and New York aliases name the same city" {
    assert cityParts(" Boston, MA ") == ["boston", "ma"];
    assert sameCity(BOSTON, BOSTON_MA);
    assert sameCity({"label": "boston"}, {"label": "Boston, MA"});
    assert sameCity({"label": "NYC", "lat": 40.71, "lon": -74.01}, {"label": "New York City", "lat": 40.71, "lon": -74.0});
}

test "same-name cities in different places stay separate" {
    portland_or = {"label": "Portland, OR", "lat": 45.52, "lon": -122.68};
    portland_me = {"label": "Portland, ME", "lat": 43.66, "lon": -70.26};
    assert not sameCity(portland_or, portland_me);
    assert not sameCity({"label": "Portland"} | {"lat": 43.66, "lon": -70.26}, portland_or);
    assert not sameCity({"label": "Portland, OR"}, {"label": "Portland, ME"});
    assert not sameCity(BOSTON, {"label": "Providence, RI", "lat": 41.82, "lon": -71.41});
}

test "a merged city keeps its coordinates and shows the more specific label" {
    assert mergedCity(BOSTON, BOSTON_MA) == {"label": "Boston, MA", "lat": 42.36, "lon": -71.06};
    assert mergedCity(BOSTON_MA, BOSTON) == BOSTON_MA;
    assert mergedCity({"label": "Boston, MA"}, BOSTON) == {"label": "Boston, MA", "lat": 42.36, "lon": -71.06};
}
