"""Browser capability for this origin's private trip list."""
import from browser_ids { request_id }

async def:pub workspaceKey -> str {
    browser: any = window;
    storage = browser.localStorage;
    name = "jacroam.private-workspace.v1";
    def getOrCreate -> str {
        saved = storage.getItem(name);
        if saved { return saved; }
        value = request_id(browser); storage.setItem(name, value); return value;
    }
    existing = storage.getItem(name);
    if existing { return existing; }
    # Serialize first visits from multiple tabs on HTTPS and localhost.
    if browser.navigator.locks { return await browser.navigator.locks.request(name, getOrCreate); }
    return getOrCreate();
}
