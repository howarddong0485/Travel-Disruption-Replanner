"""Map popup place-search text and failure messages."""
import from itinerary.place_query { placeQuery, placeSearchError }

test "the destination is appended only when the venue does not already name it" {
    assert placeQuery("Boston Public Garden", "Garden", "Boston, MA") == "Boston Public Garden, Boston, MA";
    assert placeQuery("Boston Public Garden, 4 Charles St, Boston, MA 02116", "Garden", "Boston, MA")
        == "Boston Public Garden, 4 Charles St, Boston, MA 02116";
    assert placeQuery("4 Charles St, Boston MA", "Garden", "Boston, MA") == "4 Charles St, Boston MA";
    assert placeQuery("Fenway Park", "Game", "boston") == "Fenway Park, boston";
}

test "fixture or missing locations fall back to the title, and a missing city adds nothing" {
    assert placeQuery("fixture:garden", "Outdoor garden visit", "Boston, MA") == "Outdoor garden visit, Boston, MA";
    assert placeQuery("", "Museum", "Boston") == "Museum, Boston";
    assert placeQuery("Museum of Fine Arts", "Museum", "") == "Museum of Fine Arts";
}

test "gateway pages and unavailable providers become a short retry message" {
    page = "Error: Function search_map_places failed: <html><head><title>504 Gateway Time-out</title></head><body><center><h1>504 Gateway Time-out</h1></center></body></html>";
    for raw in [page, "Function search_map_places failed: Place search HTTP 504. Check your key, quota and access, or retry later.",
        "Function search_map_places failed: Place search is unavailable or returned invalid JSON. Retry later.", "TypeError: Failed to fetch"] {
        message = placeSearchError(raw);
        assert message.startswith("Place search did not respond.") and "<" not in message, raw;
    }
}

test "a validation message is kept without the RPC prefix" {
    assert placeSearchError("Function search_map_places failed: Enter a place and city, up to 300 characters.")
        == "Enter a place and city, up to 300 characters.";
    assert placeSearchError("") == "Place search failed. Try again.";
}
