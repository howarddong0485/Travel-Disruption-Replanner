"""Offline provider-boundary checks using synthetic Wikipedia responses."""
import unittest;
import urllib.error;
import from unittest.mock { patch }
import tools.wikipedia as wiki;

test "missing and ambiguous destinations" {
    check = unittest.TestCase();
    with patch.object(wiki, "_request", return_value={"query": {"pages": [{"title": "Missing", "missing": True}]}}) {
        check.assertEqual(wiki.destination_summary("Missing")["status"], "not_found");
    }
    with patch.object(wiki, "_request", return_value={"query": {"pages": [{"title": "Springfield", "pageprops": {"disambiguation": ""}}]}}) {
        check.assertEqual(wiki.destination_summary("Springfield")["status"], "ambiguous");
    }
}

test "rank candidates exclude ambiguity and retain source" {
    check = unittest.TestCase();
    data = {"query": {"pages": [
        {"pageid": 2, "title": "Second Museum", "index": 2},
        {"pageid": 3, "title": "Ambiguous", "index": 0, "pageprops": {"disambiguation": ""}},
        {"pageid": 1, "title": "First Museum", "index": 1, "extract": "Synthetic summary", "fullurl": "https://en.wikipedia.org/wiki/First"}
    ]}};
    with patch.object(wiki, "_request", return_value=data) {
        articles = wiki.search_attractions("Boston", "museum")["articles"];
        check.assertEqual([a["page_id"] for a in articles], [1, 2]);
        check.assertEqual(articles[0]["url"], "https://en.wikipedia.org/wiki/First");
        check.assertIsNone(articles[0]["latitude"]);
        check.assertTrue(articles[0]["retrieved_at"]);
    }
}

test "invalid inputs never query provider" {
    check = unittest.TestCase();
    with patch.object(wiki, "_request") as request {
        with check.assertRaises(ValueError) { wiki.destination_summary("  "); }
        with check.assertRaises(ValueError) { wiki.search_attractions("Boston", "museum", 11); }
        check.assertFalse(request.called);
    }
}

test "provider network and API errors are explicit" {
    check = unittest.TestCase();
    with patch.object(wiki.urllib.request, "urlopen", side_effect=urllib.error.URLError("offline")) {
        with check.assertRaises(RuntimeError) { wiki.destination_summary("Boston"); }
    }
    with patch.object(wiki.urllib.request, "urlopen") as request {
        with patch.object(wiki.json, "load", return_value={"error": {"info": "Server lag"}}) {
            with check.assertRaises(RuntimeError) { wiki.destination_summary("Boston"); }
        }
    }
}
