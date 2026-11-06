"""Read-only English Wikipedia discovery. No booking or feasibility claims."""
import json;
import os;
import datetime;
import urllib.request;
import urllib.parse;
import urllib.error;

glob API = "https://en.wikipedia.org/w/api.php";

def _request(params: dict[str, any]) -> dict[str, any] {
    query = {"action": "query", "format": "json", "formatversion": "2", "maxlag": "5"};
    query.update(params);
    agent = os.environ.get("WIKIPEDIA_USER_AGENT") or "TravelDisruptionReplanner/0.1 (https://github.com/howarddong0485/Travel-Disruption-Replanner)";
    request = urllib.request.Request(API + "?" + urllib.parse.urlencode(query),
        headers={"User-Agent": agent, "Accept": "application/json"});
    try {
        with urllib.request.urlopen(request, timeout=10) as response {
            data = json.load(response);
        }
    } except (urllib.error.URLError, TimeoutError, OSError) as error {
        raise RuntimeError("Wikipedia request failed; try again later: " + str(error)) from error;
    } except ValueError as error {
        raise RuntimeError("Wikipedia returned an invalid JSON response") from error;
    }
    if not isinstance(data, dict) { raise RuntimeError("Wikipedia returned an invalid response"); }
    if "error" in data {
        raise RuntimeError("Wikipedia API error: " + str(data["error"].get("info", "Unknown error")));
    }
    return data;
}

def _text(value: str) -> str {
    value = value.strip();
    if not value or len(value) > 160 {
        raise ValueError("Enter a destination or interest between 1 and 160 characters");
    }
    return value;
}

def _properties -> dict[str, any] {
    return {"prop": "extracts|info|coordinates|pageprops", "inprop": "url",
        "exintro": "1", "explaintext": "1", "exchars": "1200", "exlimit": "max",
        "ppprop": "disambiguation", "colimit": "1"};
}

def _article(page: dict[str, any]) -> dict[str, any] {
    coords = page.get("coordinates", []);
    return {"page_id": page.get("pageid"), "title": page.get("title", ""),
        "summary": page.get("extract", ""), "url": page.get("fullurl", ""),
        "latitude": coords[0]["lat"] if coords else None,
        "longitude": coords[0]["lon"] if coords else None,
        "source": "English Wikipedia",
        "retrieved_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "attribution": "Wikipedia contributors; CC BY-SA. See article history and license at the source URL."};
}

def destination_summary(destination: str) -> dict[str, any] {
    title = _text(destination);
    params = _properties();
    params.update({"titles": title, "redirects": "1"});
    pages = _request(params).get("query", {}).get("pages", []);
    if not pages or "missing" in pages[0] or "invalid" in pages[0] {
        return {"status": "not_found", "article": None, "query": title};
    }
    page = pages[0];
    status = "ambiguous" if "disambiguation" in page.get("pageprops", {}) else "found";
    return {"status": status, "article": _article(page), "query": title};
}

def _rank(page: dict[str, any]) -> int { return int(page.get("index", 0)); }

def search_attractions(destination: str, interest: str = "museum", limit: int = 5) -> dict[str, any] {
    destination = _text(destination);
    interest = _text(interest);
    if isinstance(limit, bool) or not isinstance(limit, int) or limit < 1 or limit > 10 {
        raise ValueError("Limit must be an integer between 1 and 10");
    }
    # Quoted terms keep user input from introducing CirrusSearch operators.
    query = '"' + destination.replace('"', ' ') + '" intitle:"' + interest.replace('"', ' ') + '"';
    params = _properties();
    params.update({"generator": "search", "gsrsearch": query,
        "gsrnamespace": "0", "gsrlimit": str(limit)});
    pages = _request(params).get("query", {}).get("pages", []);
    pages = sorted(pages, key=_rank);
    articles = [_article(page) for page in pages
        if "missing" not in page and "disambiguation" not in page.get("pageprops", {})
        and interest.casefold() in page.get("title", "").casefold()];
    return {"destination": destination, "interest": interest, "articles": articles,
        "status": "found" if articles else "not_found",
        "scope": "Text-search candidates; verify location and relevance. Prices, opening hours, availability and traveler constraints are not checked."};
}
