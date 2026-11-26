"""Safe, labeled links for assistant replies and web-search citations.

Model text is never rendered as HTML. It is split into plain-text and link
segments that the chat renders as text nodes and anchors. Only https links to an
ordinary host name become clickable; anything else is shown exactly as written.
Citations that pass through a redirect, proxy or archive are labeled as such.
When the original page can be read from the cited link itself, that primary
page is linked first and the cited copy is kept as a labeled second link.
"""
import re;
import unicodedata;
import from urllib.parse { urlsplit, parse_qsl, urlencode, unquote }

glob MAX_URL = 2048;
glob HOST = re.compile(r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?");
# A Markdown link (optionally <angled> or with a "title"), an <autolink>, or a bare URL.
glob LINK = re.compile(r"\[(?P<label>[^\[\]\n]{1,300})\]\((?:<(?P<angled>[^<>\s]{1,2048})>|(?P<target>(?:[^\s()<>]|\([^\s()<>]{0,200}\)){1,2048}))(?:[ \t]+\"[^\"\n]{0,200}\")?\)"
    + r"|<(?P<auto>https?://[^<>\s]+)>"
    + r"|(?P<bare>https?://[^\s<>\"`]+)");
glob TRAILING = ".,;:!?*'\"”’»。，、；：！？";
glob ARCHIVES = ("web.archive.org", "archive.org", "archive.ph", "archive.today", "archive.is", "archive.li", "archive.md", "archive.vn", "webcache.googleusercontent.com");
glob PROXIES = ("translate.goog", "cdn.ampproject.org", "r.jina.ai", "12ft.io", "translate.google.com", "proxy.duckduckgo.com");
glob SHORTENERS = ("t.co", "bit.ly", "tinyurl.com", "goo.gl", "ow.ly", "buff.ly", "lnkd.in", "is.gd");
glob REDIRECT_KEYS = ("url", "u", "q", "uddg", "target", "dest", "destination", "redirect", "redirect_url", "redirect_to", "link", "out");
glob KIND_NOTES = {"proxy": "third-party proxy", "redirect": "redirect link", "archive": "archived copy"};

"""Return the URL when it is an https link to a normal host name, otherwise an empty string."""
def safe_url(value: any) -> str {
    if not isinstance(value, str) { return ""; }
    url = value.strip();
    if not url or len(url) > MAX_URL or "\\" in url or any(char in "<>\"`" or unicodedata.category(char)[0] in "CZ" for char in url) { return ""; }
    try { link = urlsplit(url); link.port; }
    except ValueError { return ""; }
    if link.scheme != "https" or "@" in link.netloc or not HOST.fullmatch(link.hostname or "") { return ""; }
    return url;
}

def site(url: str) -> str {
    host = urlsplit(url).hostname or "";
    return host[4:] if host.startswith("www.") else host;
}

def under(host: str, domains: tuple[str, ...]) -> bool {
    return any(host == domain or host.endswith("." + domain) for domain in domains);
}

"""A comparison key: the same page regardless of case in the host, tracking parameters, fragment or trailing slash."""
def page_key(url: str) -> str {
    link = urlsplit(url);
    query = sorted((key, value) for (key, value) in parse_qsl(link.query, keep_blank_values=True) if not key.lower().startswith("utm_"));
    port = ":" + str(link.port) if link.port and link.port != 443 else "";
    return (link.hostname or "") + port + (link.path.rstrip("/") or "/") + ("?" + urlencode(query) if query else "");
}

"""One level of unwrapping: the page a redirect, proxy or cache link points at, and how it does so."""
def embedded(url: str) -> tuple[str, str] {
    link = urlsplit(url); host = link.hostname or "";
    if host.endswith(".translate.goog") {
        # Google encodes the original host's dots as "-" and its hyphens as "--".
        name = host[:-len(".translate.goog")].replace("--", "\x00").replace("-", ".").replace("\x00", "-");
        query = [(key, value) for (key, value) in parse_qsl(link.query, keep_blank_values=True) if not key.startswith("_x_tr_")];
        return ("https://" + name + (link.path or "/") + ("?" + urlencode(query) if query else ""), "proxy");
    }
    if under(host, ("cdn.ampproject.org",)) {
        found = re.fullmatch(r"/[a-z]{1,2}/(s/)?([^/?#]+.*)", link.path);
        if found { return (("https://" if found[1] else "http://") + found[2] + ("?" + link.query if link.query else ""), "proxy"); }
    }
    for (key, value) in parse_qsl(link.query) {
        if key.lower() not in REDIRECT_KEYS { continue; }
        value = value.strip();
        if value.startswith("cache:") {
            value = re.sub(r"^[\w-]{1,24}:(?!//)", "", value[6:]).split()[0] if value[6:].split() else "";
            if value and not re.match(r"https?://", value, re.IGNORECASE) { value = "https://" + value; }
        }
        if re.match(r"https?://", value, re.IGNORECASE) { return (value, "redirect"); }
    }
    found = re.search(r"/(https?):/{1,2}(.+)", unquote(link.path), re.IGNORECASE);
    if found { return (found[1].lower() + "://" + found[2] + ("?" + link.query if link.query else ""), "proxy"); }
    return ("", "");
}

"""How a safe URL reaches its page: kind is direct, redirect, proxy or archive; original is the recovered primary page when it is itself a safe link."""
def describe(url: str) -> dict[str, str] {
    host = urlsplit(url).hostname or ""; current = url; kind = "";
    for depth in range(3) {
        (inner, how) = embedded(current);
        if not inner { break; }
        current = inner; kind = kind or how;
    }
    if under(host, ARCHIVES) { kind = "archive"; }
    elif not kind { kind = "redirect" if under(host, SHORTENERS) else "proxy" if under(host, PROXIES) else "direct"; }
    return {"kind": kind, "via": site(url), "original": safe_url(current) if current != url else ""};
}

def copy_label(info: dict[str, str]) -> str {
    return "Cited from an archived copy on " + info["via"] if info["kind"] == "archive"
        else "Cited through a redirect on " + info["via"] if info["kind"] == "redirect"
        else "Cited through a third-party proxy, " + info["via"];
}

"""Display entries for an answer's web citations, preferring primary pages over redirects, proxies and archived copies."""
def cited(sources: any) -> list[dict[str, str]] {
    primary: list[dict[str, str]] = []; unresolved: list[dict[str, str]] = []; seen: dict[str, dict[str, str]] = {};
    for source in (sources if isinstance(sources, list) else [])[:16] {
        url = safe_url(source.get("url")) if isinstance(source, dict) else "";
        if not url { continue; }
        info = describe(url); main = info["original"] or url;
        title = source.get("title"); title = title.strip()[:200] if isinstance(title, str) else "";
        row = {"title": title if title and title != url else site(main), "url": main, "site": site(main), "copy_url": "", "copy_label": ""};
        if info["original"] { row["copy_url"] = url; row["copy_label"] = copy_label(info); }
        elif info["kind"] != "direct" { row["site"] = info["via"] + " · " + KIND_NOTES[info["kind"]]; }
        key = page_key(main);
        if key in seen {
            # One entry per page: a direct citation replaces a cited copy of the same page.
            if seen[key]["copy_url"] and info["kind"] == "direct" { seen[key].update(row); }
            continue;
        }
        seen[key] = row;
        # Links whose primary page cannot be recovered are listed after primary pages.
        if info["kind"] == "direct" or info["original"] { primary.append(row); }
        else { unresolved.append(row); }
    }
    return primary + unresolved;
}

def trim_bare(url: str) -> str {
    while url {
        if url[-1] in TRAILING { url = url[:-1]; }
        elif url[-1] == ")" and url.count("(") < url.count(")") { url = url[:-1]; }
        else { break; }
    }
    return url;
}

def link_part(label: str, url: str, cited_keys: any) -> dict[str, any] {
    info = describe(url); host = site(url);
    note = "" if info["kind"] == "direct" else KIND_NOTES[info["kind"]];
    shown = label.strip("*_` ") or url;
    return {"text": shown, "url": url, "site": host + (" · " + note if note else ""),
        "show_site": bool(note) or host not in shown.lower(), "cited": page_key(url) in cited_keys};
}

"""Split text into plain and link segments. Unsafe or non-https links stay as the literal text the model wrote."""
def segments(text: any, sources: any = None) -> list[dict[str, any]] {
    if not isinstance(text, str) or not text { return []; }
    cited_keys = `set();
    for source in (sources if isinstance(sources, list) else []) {
        url = safe_url(source.get("url")) if isinstance(source, dict) else "";
        if not url { continue; }
        cited_keys.add(page_key(url));
        original = describe(url)["original"];
        if original { cited_keys.add(page_key(original)); }
    }
    parts: list[dict[str, any]] = []; plain = ""; position = 0;
    for found in LINK.finditer(text) {
        plain += text[position:found.start()]; position = found.end();
        if found["bare"] {
            url = trim_bare(found["bare"]);
            position = found.start() + len(url);
            label = url;
        } else {
            url = found["auto"] or found["angled"] or found["target"];
            label = found["label"] or url;
        }
        url = safe_url(url);
        if not url { plain += text[found.start():position]; continue; }
        if plain { parts.append({"text": plain}); plain = ""; }
        parts.append(link_part(label, url, cited_keys));
    }
    plain += text[position:];
    if plain { parts.append({"text": plain}); }
    return parts;
}

"""Link display fields added to a stored assistant message when it is read."""
def message_links(message: dict[str, any]) -> dict[str, any] {
    sources = message.get("sources", []);
    return {"segments": segments(message.get("text", ""), sources),
        "research_segments": segments(message.get("research", ""), sources),
        "source_links": cited(sources)};
}
