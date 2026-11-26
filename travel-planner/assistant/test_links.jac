"""Assistant link rendering and citation labels; no model or network calls."""
import from tests.workspace_fixture { TEST_WORKSPACE }
import os;
import tempfile;
import from uuid { uuid4 }
import from unittest.mock { patch }
import assistant.provider as provider;
import server.main as service;
import from assistant.links { segments, cited, safe_url, describe }

def links(parts: list[dict[str, any]]) -> list[str] {
    return [part["url"] for part in parts if "url" in part];
}

def plain(parts: list[dict[str, any]]) -> str {
    return "".join(part["text"] for part in parts);
}

test "markdown citations and bare URLs become links and keep the surrounding text" {
    text = "Take the SL1 ([mbta.com](https://www.mbta.com/schedules/741/line?utm_source=openai)). Wiki: https://en.wikipedia.org/wiki/Logan_(airport), or (https://www.massport.com/logan)."
        + " Angled <https://www.mbta.com/fares> and [Fares](<https://www.mbta.com/fares/subway>).";
    parts = segments(text, [{"url": "https://www.mbta.com/schedules/741/line?utm_source=openai", "title": "SL1"}]);
    assert links(parts) == ["https://www.mbta.com/schedules/741/line?utm_source=openai", "https://en.wikipedia.org/wiki/Logan_(airport)",
        "https://www.massport.com/logan", "https://www.mbta.com/fares", "https://www.mbta.com/fares/subway"];
    assert parts[0] == {"text": "Take the SL1 ("};
    assert parts[1]["text"] == "mbta.com" and parts[1]["cited"] and not parts[1]["show_site"];
    assert parts[2] == {"text": "). Wiki: "};
    assert plain(parts) == "Take the SL1 (mbta.com). Wiki: https://en.wikipedia.org/wiki/Logan_(airport), or (https://www.massport.com/logan). Angled https://www.mbta.com/fares and Fares.";
    assert not any(part.get("cited") for part in parts[2:]);
    assert parts[-2]["text"] == "Fares" and parts[-2]["show_site"] and parts[-2]["site"] == "mbta.com";
}

test "unsafe or non-https links stay literal text and markup is never interpreted" {
    text = "[click](javascript:alert(1)) [old](http://example.com) <script>alert(1)</script> <a href=\"https://evil.example\">x</a> "
        + "[spoof](https://user@evil.example/) https://evil.example\\@good.example/ https://127.0.0.1/admin [data](data:text/html,hi) https://exa mple.com";
    parts = segments(text, []);
    # Rejected links keep the exact text; a URL inside literal markup is only linked as visible text.
    assert plain(parts) == text and links(parts) == ["https://evil.example"];
    for url in ["javascript:alert(1)", "http://example.com", "https://user@evil.example/", "https://evil.example\\@good.example/", "https://127.0.0.1/",
        "https://localhost/", "https://exa mple.com", "https://xn--80ak6aa92e.com/‮", "https://example.com:99999/", "", None, 7] {
        assert safe_url(url) == "", url;
    }
    assert safe_url("https://www.mbta.com/schedules/741") == "https://www.mbta.com/schedules/741";
    assert segments("", []) == [] and segments(None, []) == [];
    assert segments("No links here.", None) == [{"text": "No links here."}];
}

test "link labels show the real destination host when the label does not" {
    parts = segments("[MBTA.com](https://www.mbta.com/x) [official schedule](https://www.mbta.com/y) [mbta.com](https://evil.example/z)", []);
    shown = [(part["text"], part["show_site"], part["site"]) for part in parts if "url" in part];
    assert shown == [("MBTA.com", False, "mbta.com"), ("official schedule", True, "mbta.com"), ("mbta.com", True, "evil.example")];
    proxied = segments("[MBTA](https://r.jina.ai/https://www.mbta.com/x)", [])[0];
    assert proxied["show_site"] and proxied["site"] == "r.jina.ai · third-party proxy" and proxied["url"] == "https://r.jina.ai/https://www.mbta.com/x";
}

test "proxy, redirect and archive citations prefer the primary page and label the cited copy" {
    assert describe("https://www.mbta.com/fares") == {"kind": "direct", "via": "mbta.com", "original": ""};
    assert describe("https://www-mbta-com.translate.goog/fares?_x_tr_sl=auto&_x_tr_tl=en&zone=1")["original"] == "https://www.mbta.com/fares?zone=1";
    assert describe("https://my--site-com.translate.goog/a")["original"] == "https://my-site.com/a";
    assert describe("https://www-mbta-com.cdn.ampproject.org/c/s/www.mbta.com/news")["original"] == "https://www.mbta.com/news";
    assert describe("https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.massport.com%2Flogan&rut=1") == {"kind": "redirect", "via": "duckduckgo.com", "original": "https://www.massport.com/logan"};
    # Nested wrappers unwrap to the page itself; the label names the link that was cited.
    assert describe("https://www.google.com/url?q=https://r.jina.ai/https://www.mbta.com/x") == {"kind": "redirect", "via": "google.com", "original": "https://www.mbta.com/x"};
    assert describe("https://bit.ly/3abc") == {"kind": "redirect", "via": "bit.ly", "original": ""};
    assert describe("https://r.jina.ai/http://plain.example/x") == {"kind": "proxy", "via": "r.jina.ai", "original": ""};
    rows = cited([
        {"url": "https://bit.ly/3abc", "title": "Shortened"},
        {"url": "https://r.jina.ai/https://www.mbta.com/schedules/741", "title": "SL1 | MBTA"},
        {"url": "https://www.google.com/url?q=https://www.massport.com/logan&sa=D", "title": ""},
        {"url": "https://web.archive.org/web/20240101000000/https://www.mbta.com/fares", "title": "Fares"},
        {"url": "https://www.massport.com/logan?utm_source=openai", "title": "Logan Airport"},
        {"url": "http://insecure.example/", "title": "Skipped"}, {"title": "No URL"}, "not a source"]);
    assert [row["url"] for row in rows] == ["https://www.mbta.com/schedules/741", "https://www.massport.com/logan?utm_source=openai", "https://www.mbta.com/fares", "https://bit.ly/3abc"];
    assert rows[0] == {"title": "SL1 | MBTA", "url": "https://www.mbta.com/schedules/741", "site": "mbta.com",
        "copy_url": "https://r.jina.ai/https://www.mbta.com/schedules/741", "copy_label": "Cited through a third-party proxy, r.jina.ai"};
    # The direct Massport citation replaces the redirect to the same page and needs no copy link.
    assert rows[1] == {"title": "Logan Airport", "url": "https://www.massport.com/logan?utm_source=openai", "site": "massport.com", "copy_url": "", "copy_label": ""};
    assert rows[2]["copy_label"] == "Cited from an archived copy on web.archive.org" and rows[2]["site"] == "mbta.com";
    assert rows[3] == {"title": "Shortened", "url": "https://bit.ly/3abc", "site": "bit.ly · redirect link", "copy_url": "", "copy_label": ""};
    assert cited(None) == [] and cited([{"url": "https://www.mbta.com/a"}])[0]["title"] == "mbta.com";
}

test "a primary URL in the answer counts as cited when search only cited a proxy copy of it" {
    parts = segments("Official page: https://www.mbta.com/schedules/741/ and an uncited https://www.mbta.com/other.",
        [{"url": "https://www-mbta-com.translate.goog/schedules/741?_x_tr_sl=auto", "title": "SL1"}]);
    assert [(part["url"], part["cited"]) for part in parts if "url" in part] == [("https://www.mbta.com/schedules/741/", True), ("https://www.mbta.com/other", False)];
}

test "stored assistant replies are read with link segments and labeled sources" {
    reply = {"answer": "See [the MBTA trip page](https://www.mbta.com/schedules/741). <b>not bold</b>",
        "sources": [{"url": "https://r.jina.ai/https://www.mbta.com/schedules/741", "title": "SL1"}], "plans": []};
    with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"TRAVEL_DB_PATH": os.path.join(directory, "trip.sqlite3")}) {
        id = service.save_trip(TEST_WORKSPACE, "Links", "Boston", "2031-03-01", "2031-03-02", "USD", "500").id;
        with patch.object(provider, "generate", return_value=reply) {
            state = service.assistant_chat(TEST_WORKSPACE, id, "Link me https://example.com/mine", "ask", True, str(uuid4()));
        }
        (user, assistant) = state["messages"];
        assert "segments" not in user and user["text"] == "Link me https://example.com/mine";
        assert assistant["text"] == reply["answer"] and assistant["sources"] == reply["sources"];
        assert [part["text"] for part in assistant["segments"]] == ["See ", "the MBTA trip page", ". <b>not bold</b>"];
        assert assistant["segments"][1]["cited"] and assistant["segments"][1]["show_site"];
        assert assistant["source_links"][0]["url"] == "https://www.mbta.com/schedules/741" and assistant["source_links"][0]["copy_url"].startswith("https://r.jina.ai/");
        assert assistant["research_segments"] == [];
        # Derived fields are not stored, so later reads keep the original payload.
        again = service.assistant_state(TEST_WORKSPACE, id)["messages"][1];
        assert again["segments"] == assistant["segments"] and again["sources"] == reply["sources"];
    }
}

test "the model is asked to cite official primary pages directly" {
    plain_reply = {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "Ready"}]}]};
    with patch.object(provider, "request", return_value=plain_reply) as transport {
        provider.generate({}, [], "Official MBTA page for Logan?", "ask", True);
        assert "Prefer official primary sources" in transport.call_args[0][0]["instructions"];
        assert "rather than proxies, caches, archives or redirect links" in transport.call_args[0][0]["instructions"];
    }
}
