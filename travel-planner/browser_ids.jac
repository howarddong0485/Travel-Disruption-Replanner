"""Browser UUIDs for request deduplication, including local HTTP sessions."""

def:pub request_id(browser: any) -> str {
    if browser.crypto and browser.crypto.randomUUID { return browser.crypto.randomUUID(); }
    if not browser.crypto or not browser.crypto.getRandomValues {
        raise Exception("This browser cannot generate a request ID. Open the app in an updated browser and retry.");
    }
    # getRandomValues remains available on HTTP where randomUUID may be absent.
    values: any = new(browser.Uint8Array, 16);
    browser.crypto.getRandomValues(values);
    values[6] = values[6] % 16 + 64;
    values[8] = values[8] % 64 + 128;
    parts: any = [values[i].toString(16).padStart(2, "0") for i in range(16)];
    return parts[:4].join("") + "-" + parts[4:6].join("") + "-" + parts[6:8].join("") + "-" + parts[8:10].join("") + "-" + parts[10:].join("");
}
