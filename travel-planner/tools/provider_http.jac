"""Small bounded JSON transport; errors never echo URLs or credentials."""
import json;
import urllib.request;
import urllib.error;

def request(url: str, headers: dict[str, str], body: any = None, provider: str = "Provider") -> any {
    payload = json.dumps(body).encode() if body is not None else None;
    req = urllib.request.Request(url, data=payload,
        headers={**headers, "Accept": "application/json", "Content-Type": "application/json"});
    try {
        with urllib.request.urlopen(req, timeout=15) as response {
            raw = response.read(4000001);
            if len(raw) > 4000000 { raise RuntimeError(provider + " returned too much data"); }
            return json.loads(raw);
        }
    } except urllib.error.HTTPError as error {
        raise RuntimeError(provider + " HTTP " + str(error.code) + ". Check your key, quota and access, or retry later.") from None;
    } except (urllib.error.URLError, OSError, ValueError) {
        raise RuntimeError(provider + " is unavailable or returned invalid JSON. Retry later.") from None;
    }
}
