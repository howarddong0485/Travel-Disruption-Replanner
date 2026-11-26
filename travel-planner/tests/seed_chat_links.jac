"""Isolated browser-test seed for chat links, with a synthetic reply and no model calls.
Run with the browser-test server's TRAVEL_DB_PATH: jac run tests/seed_chat_links.jac"""
import from tests.workspace_fixture { TEST_WORKSPACE }
import json;
import from uuid { uuid4 }
import from unittest.mock { patch }
import server.main as api;
import assistant.provider as provider;
with entry {
    id = api.save_trip(TEST_WORKSPACE, "Chat links browser regression", "Boston", "2031-03-01", "2031-03-02", "USD", "500").id;
    reply = {"answer": "Take the Silver Line SL1 ([mbta.com](https://www.mbta.com/schedules/741/line?utm_source=openai)). "
            + "Fares: https://www.mbta.com/fares. Not a link: [run](javascript:alert(1)) and <img src=x onerror=\"document.title='owned'\">.",
        "research": "Logan Express notes: [Massport](https://www.massport.com/logan-airport/to-and-from-logan/transportation-options/logan-express).",
        "sources": [{"url": "https://r.jina.ai/https://www.mbta.com/schedules/741/line", "title": "SL1 schedule"},
            {"url": "https://www.mbta.com/fares?utm_source=openai", "title": "MBTA fares"},
            {"url": "https://bit.ly/3synthetic", "title": "Shortened guide"}], "plans": []};
    with patch.object(provider, "generate", return_value=reply), patch.object(provider, "request", side_effect=RuntimeError("Network disabled in synthetic test")) {
        api.assistant_chat(TEST_WORKSPACE, id, "Official MBTA page from Logan to South Station?", "ask", True, str(uuid4()));
    }
    print(json.dumps({"trip_id": id}));
}
