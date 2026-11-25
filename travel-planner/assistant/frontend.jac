"""Persistent trip conversation sidebar and the unified AI plan review workspace."""
import from workspace { workspaceKey }
import from browser_ids { request_id }
import from itinerary.flight_card { FlightCard }
import from server.main { assistant_state, assistant_chat, assistant_review, assistant_confirm_map }
import from journey.frontend { journeyLabel }
import from itinerary.policy_review { PolicyReview }

def:pub assistantError(error: any) -> str {
    browser: any = window;
    text = str(error); offset = text.find("{");
    if offset >= 0 {
        try {
            payload = browser.JSON.parse(text[offset:]);
            if payload.get("error", {}).get("message", "") { return payload["error"]["message"]; }
        } except Exception { return "The request could not be completed. Reload the conversation and try again."; }
    }
    return "The request could not be completed. Reload the conversation and try again." if "Function " in text else text;
}

def:pub ChatSidebar(trip_id: str, destination: str, onUpdate: any, reload: int = 0,
    compose: int = 0, composeMode: str = "ask", composeText: str = "", externalBusy: bool = False, onKeyChange: any = None) -> JsxElement {
    browser: any = window;
    has data: dict[str, any] = {}, text: str = "", mode: str = "ask", search: bool = True,
        apiKey: str = "", keyInput: str = "", keyError: str = "",
        busy: bool = False, loading: bool = True, failure: str = "", pendingText: str = "",
        alive: Ref[bool] = Ref(True), sequence: Ref[int] = Ref(0), scrollTarget: Ref[any] = Ref(None),
        poll: Ref[any] = Ref(None), reloadAction: Ref[any] = Ref(None), focusAction: Ref[any] = Ref(None);
    composerKey = "jacroam.composer." + trip_id;
    # Saved apart from the composer, which is cleared whenever the text is empty.
    searchKey = "jacroam.search." + trip_id;
    def rememberComposer(value: str) -> None {
        try {
            if value { browser.sessionStorage.setItem(composerKey, browser.JSON.stringify({"text":value, "mode":mode, "search":search})); }
            else { browser.sessionStorage.removeItem(composerKey); }
        } except Exception {}
    }
    async def load -> None {
        if busy { return; }
        request = sequence.current;
        try {
            fresh = await assistant_state(workspace_key=await workspaceKey(), trip_id=trip_id);
            if alive.current and request == sequence.current and fresh.get("trip_id") == trip_id { data = fresh; onUpdate(fresh, False); failure = ""; }
        } except Exception { if alive.current { failure = "Could not load this conversation. Try Reload."; } }
        finally { if alive.current { loading = False; } }
    }
    reloadAction.current = lambda { load(); };
    can with entry {
        alive.current = True;
        try {
            saved = browser.JSON.parse(browser.sessionStorage.getItem(composerKey) or "null");
            if saved { mode = saved["mode"]; text = saved["text"]; search = saved["search"]; }
            searching = browser.sessionStorage.getItem(searchKey);
            if searching is not None { search = searching == "on"; }
        } except Exception {}
        focusAction.current = lambda { if not browser.document.hidden { reloadAction.current(); } };
        poll.current = browser.setInterval(focusAction.current, 15000);
        browser.addEventListener("focus", focusAction.current);
        browser.document.addEventListener("visibilitychange", focusAction.current);
    }
    can with [trip_id, reload] entry { load(); }
    can with exit {
        browser.clearInterval(poll.current);
        browser.removeEventListener("focus", focusAction.current);
        browser.document.removeEventListener("visibilitychange", focusAction.current);
        if not busy { rememberComposer(text); }
        if onKeyChange { onKeyChange(""); } alive.current = False; sequence.current += 1;
    }
    can with [text, mode, search] entry { if not busy { rememberComposer(text); } }
    can with [compose] entry {
        if compose > 0 {
            mode = composeMode; text = composeText;
            field: any = document.getElementById("ai-message");
            if field { field.focus(); }
        }
    }
    messageCount = len(data.get("messages", []));
    can with [messageCount, busy] entry {
        if scrollTarget.current { scrollTarget.current.scrollIntoView({"block": "nearest", "behavior": "smooth"}); }
    }
    async def send(e: FormEvent) -> None {
        e.preventDefault(); if busy or externalBusy or loading or not text.strip() { return; }
        sequence.current += 1; busy = True; failure = ""; pendingText = text.strip(); request = sequence.current;
        try {
            rememberComposer("");
            fresh = await assistant_chat(workspace_key=await workspaceKey(), trip_id=trip_id, message=pendingText, mode=mode,
                search=search, request_id=request_id(browser), api_key=apiKey);
            if alive.current and request == sequence.current {
                previous = [draft["id"] for draft in data.get("drafts", [])];
                created = len([draft for draft in fresh.get("drafts", []) if draft["id"] not in previous and draft["status"] == "pending"]) > 0;
                data = fresh; text = ""; pendingText = ""; onUpdate(fresh, mode != "ask" or created);
            }
        } except Exception as error {
            if alive.current and request == sequence.current { failure = assistantError(error); rememberComposer(pendingText); pendingText = ""; }
            elif not browser.sessionStorage.getItem(composerKey) { rememberComposer(pendingText); }
        } finally { if alive.current and request == sequence.current { busy = False; } }
    }
    async def confirmMap(messageId: str, actionIndex: int, choiceIndex: int) -> None {
        sequence.current += 1; request = sequence.current; busy = True; failure = "";
        try {
            fresh = await assistant_confirm_map(workspace_key=await workspaceKey(), trip_id=trip_id, message_id=messageId, action_index=actionIndex, choice_index=choiceIndex);
            if alive.current and request == sequence.current and fresh.get("trip_id") == trip_id { data = fresh; onUpdate(fresh, False); }
        } except Exception as error { if alive.current and request == sequence.current { failure = assistantError(error); } }
        finally { if alive.current and request == sequence.current { busy = False; } }
    }
    def useKey(e: FormEvent) -> None {
        e.preventDefault();
        value = keyInput.strip();
        if not value.startswith("sk-") or len(value) > 512 or not browser.RegExp("^sk-[!-~]+$").test(value) {
            keyError = "Enter an OpenAI API key beginning with sk- and without spaces."; return;
        }
        apiKey = value; if onKeyChange { onKeyChange(value); } keyInput = ""; keyError = ""; failure = "";
    }
    <aside className="chat-sidebar" aria-label="Travel assistant">
        <header className="chat-heading"><div className="ai-monogram" aria-hidden="true">✦</div><div><h2>Travel assistant</h2>
            <p>{destination}</p></div>
            <button className="text-button" type="button" onClick={load} disabled={busy} aria-label="Reload conversation">↻</button></header>
        <details className="ai-key-settings">
            <summary>{"Your OpenAI key is in use" if apiKey else "OpenAI API key"}</summary>
            <form onSubmit={useKey}>
                <label htmlFor="ai-api-key">Your OpenAI API key</label>
                <input id="ai-api-key" type="password" value={keyInput} autoComplete="off" spellCheck={False}
                    maxLength={512} placeholder="sk-…" disabled={busy} required={True}
                    onChange={lambda (e: ChangeEvent) { keyInput = e.target.value; keyError = ""; }}/>
                <div className="ai-key-actions"><button type="submit" className="secondary" disabled={busy or not keyInput.strip()}>Use key</button>
                    {(<button type="button" className="text-button" disabled={busy} onClick={lambda { apiKey = ""; if onKeyChange { onKeyChange(""); } keyInput = ""; keyError = ""; failure = ""; }}>Clear key</button>) if apiKey else None}</div>
                {(<p className="chat-error" role="alert">{keyError}</p>) if keyError else None}
            </form>
            <small>Your key stays in this tab's memory and is cleared when you refresh. Usage is billed to your OpenAI account.</small>
            <p role="status">{"Using your key. It will be checked when you send a message." if apiKey else "Using the app owner’s key. Add yours to use your own account." if data.get("config", {}).get("configured", False) else "Add your key to start chatting."}</p>
        </details>
        <div className="chat-messages" role="log" aria-label="Conversation" aria-busy={busy or loading}>
            {(<div className="chat-welcome"><span className="chat-spark">✦</span><h3>Ask about this trip</h3>
                <p>Ask a question, request an itinerary, or describe a disruption to get a revised plan.</p>
                <small>Answers use this trip's details and your recent messages.</small></div>) if len(data.get("messages", [])) == 0 else None}
            {[
                <article key={message["id"]} className={"chat-message " + message["role"]}>
                    <p className="message-author">{"YOU" if message["role"] == "user" else "JACROAM ASSISTANT"}
                        <span>{message.get("mode", "ask")}</span></p>
                    <div className="message-text">{message["text"]}</div>
                    {[<div className="map-saved-flight" key={str(actionIndex)}><strong>{action["title"]}</strong>
                        {(<p role="status">Location / track saved to this trip.</p>) if action.get("confirmed", False) else
                            <div>{[<button type="button" className="map-list-row" disabled={busy or externalBusy or message.get("stale", False)} key={str(choiceIndex)}
                                onClick={lambda { confirmMap(message["id"], actionIndex, choiceIndex); }}><span>
                                <strong>{choice["label"] if action["kind"] == "place" else choice["callsign"] + " · " + choice["registration"]}</strong>
                                {(<small>{choice["start"] + " — " + choice["end"] + " · UTC · adsb.aero"}</small>) if action["kind"] == "flight" else None}
                                <small>Confirm &amp; save to map</small></span></button> for (choiceIndex, choice) in enumerate(action["choices"])]}</div>}
                    </div> for (actionIndex, action) in enumerate(message.get("map_actions", []))]}
                    {(<p className="chat-caution">The trip changed during this request. Ask for a fresh plan before saving.</p>) if message.get("stale", False) else None}
                    {(<div className="chat-caution"><strong>Draft needs another pass</strong>{[<p key={issue}>{issue}</p> for issue in message.get("issues", [])]}</div>) if len(message.get("issues", [])) > 0 else None}
                    {(<div className="chat-sources" aria-label="Sources">{[
                        <a key={source["url"]} href={source["url"]} target="_blank" rel="noopener noreferrer">↗ {source["title"]}</a>
                        for source in message.get("sources", []) if source["url"].startswith("https://")
                    ]}</div>) if len(message.get("sources", [])) > 0 else None}
                    {(<details className="chat-research"><summary>Search notes & citations</summary><p className="message-text">{message["research"]}</p></details>) if message.get("research", "") else None}
                </article> for message in data.get("messages", [])
            ]}
            {(<article className="chat-message user"><p className="message-author">YOU</p><p className="message-text">{pendingText}</p></article>) if pendingText else None}
            {(<p className="thinking" role="status"><span>✦</span> {"Preparing your trip changes…" if mode == "edit" else "Researching options and preparing your draft…" if mode != "ask" and search else "Preparing your draft with estimated costs…" if mode != "ask" else "Thinking and checking sources…" if search else "Thinking…"}</p>) if busy else None}
            <div ref={scrollTarget}/>
        </div>
        <div className="chat-composer">
            {(<p className="chat-error" role="alert">{failure}</p>) if failure else None}
            <form onSubmit={send}>
                <label htmlFor="ai-mode">What would you like to do?</label>
                <select id="ai-mode" value={mode} disabled={busy} onChange={lambda (e: ChangeEvent) { mode = e.target.value; }}>
                    <option value="ask">Ask a question</option><option value="plan">Plan my trip</option>
                    <option value="backup">Prepare alternatives</option><option value="replan">Replan a change</option><option value="edit">Edit trip details</option>
                </select>
                <label className="sr-only" htmlFor="ai-message">Message the travel assistant</label>
                <textarea id="ai-message" value={text} rows={3} maxLength={4000} disabled={busy}
                    placeholder="Type your question or request…" onChange={lambda (e: ChangeEvent) { text = e.target.value; }}/>
                <div className="composer-actions"><label className="search-toggle"><input type="checkbox" checked={search} disabled={busy}
                    onChange={lambda (e: ChangeEvent) {
                        search = e.target.checked;
                        try { browser.sessionStorage.setItem(searchKey, "on" if e.target.checked else "off"); } except Exception {}
                    }}/> Search the web</label>
                    <button className="primary" type="submit" disabled={busy or externalBusy or loading or not text.strip() or not (apiKey or data.get("config", {}).get("configured", False))}>
                        {"Working…" if busy else "Send ↗"}</button></div>
            </form>
            <small>Without web search, drafts are faster but use estimated prices.</small>
            <small>Chat never books or pays. Review plan drafts and track matches; unique place coordinates can be saved automatically.</small>
        </div>
    </aside>
}

def:pub AIPlanner(data: dict[str, any], currency: str, onCompose: any, onReview: any, onPrices: any, onPreferences: any, busy: bool) -> JsxElement {
    browser: any = window;
    has acknowledged: dict[str, bool] = {}, prices: dict[str, str] = {}, priceErrors: dict[str, str] = {},
        tick: float = 0, timer: Ref[any] = Ref(None), clockOffset: Ref[float] = Ref(0);
    can with [data] entry { if data.get("checked_at", "") { clockOffset.current = browser.Date.parse(data["checked_at"]) - browser.Date.now(); } tick = browser.Date.now(); }
    can with entry { tick = browser.Date.now(); timer.current = browser.setInterval(lambda { tick = browser.Date.now(); }, 1000); }
    can with exit { browser.clearInterval(timer.current); }
    def status(draft: dict[str, any]) -> str {
        if draft["status"] == "pending" and browser.Date.parse(draft["expires"]) <= tick + clockOffset.current { return "expired"; }
        return draft["status"];
    }
    async def savePrices(e: FormEvent, draft: dict[str, any]) -> None {
        e.preventDefault();
        values: dict[str, any] = {};
        for (index, change) in enumerate(draft["changes"]) {
            key = draft["id"] + ":" + str(index);
            if change["price_unknown"] and prices.get(key, "").strip() { values[str(index)] = prices[key]; }
        }
        acknowledged = {**acknowledged, draft["id"]: False};
        message = await onPrices(draft["id"], values);
        priceErrors = {**priceErrors, draft["id"]: message};
    }
    def money(value: any, unit: str = "") -> str { return "Unknown" if value is None else (unit or currency) + " " + (value / 100).toFixed(2); }
    def detail(value: any, field: str, unit: str) -> str { return money(value, unit) if field == "budget_cents" else str(value) or "Not set"; }
    def label(mode: str) -> str { return "Trip details" if mode == "edit" else "Trip plan" if mode == "plan" else "Alternative" if mode == "backup" else "Replan"; }
    pending = [draft for draft in data.get("drafts", []) if status(draft) == "pending"];
    history = [draft for draft in data.get("drafts", []) if status(draft) != "pending"];
    preferences = data.get("preferences", {"pet_friendly": False, "pace": "balanced"});
    <section className="ai-planner" aria-label="AI planning workspace">
        <div className="card ai-planner-intro"><h2>Plan with the assistant</h2>
            <p>Set your preferences, then choose a task. The assistant drafts a plan for you to review below.</p>
            <div className="planning-preferences" aria-label="Trip planning preferences">
                <div className="pet-preference"><button type="button" className="pet-toggle" aria-pressed={preferences["pet_friendly"]}
                    disabled={busy or not data.get("trip_version", 0)} onClick={lambda { onPreferences(not preferences["pet_friendly"], preferences["pace"]); }}>
                    {"✓ Pet-friendly" if preferences["pet_friendly"] else "Pet-friendly"}<span>{"On" if preferences["pet_friendly"] else "Off"}</span></button>
                    <small>Prefer pet-friendly stays, meals and activities. Confirm pet policies with each venue.</small></div>
                <fieldset className="pace-preference"><legend>Trip pace</legend><div className="pace-buttons">{[
                    <button key={pace} type="button" aria-pressed={preferences["pace"] == pace} disabled={busy or not data.get("trip_version", 0)}
                        onClick={lambda { onPreferences(preferences["pet_friendly"], pace); }}>{"Intense" if pace == "intense" else "Balanced" if pace == "balanced" else "Relax"}</button>
                    for pace in ["intense", "balanced", "relax"]
                ]}</div><small>{"Fuller days with 4–6 main activities" if preferences["pace"] == "intense" else "1–2 main activities with plenty of free time" if preferences["pace"] == "relax" else "2–3 main activities with time to unwind"}</small></fieldset>
                <p className="preference-note">Saved for this trip and used in every AI draft.</p>
            </div>
            <div className="ai-quick-actions">
                <button type="button" disabled={busy} onClick={lambda { onCompose("plan", "Build an itinerary for my trip using my saved preferences. Keep my existing arrangements and stay within my budget."); }}><span>◎</span><strong>Plan my trip</strong><small>Draft a full itinerary</small></button>
                <button type="button" disabled={busy} onClick={lambda { onCompose("backup", "Prepare two different backup plans for the vulnerable parts of my itinerary. Explain when I would use each one."); }}><span>⇄</span><strong>Find alternatives</strong><small>Backups for parts that could go wrong</small></button>
                <button type="button" disabled={busy} onClick={lambda { onCompose("replan", "My plans changed: "); }}><span>↗</span><strong>Something changed</strong><small>Fix the plans a disruption affects</small></button>
            </div>
            <button type="button" className="text-button" disabled={busy} onClick={lambda { onCompose("edit", "Change my trip details: "); }}>Change dates, destination, budget or other trip details ↗</button>
        </div>
        <div className="section-heading ai-draft-heading"><div><h2>Drafts to review</h2></div><span className="count-pill">{str(len(pending)) + " to review"}</span></div>
        {(<div className="card ai-drafts-empty"><span>✦</span><h3>No drafts yet</h3><p>Choose a task above or send a request in the assistant panel. Drafts appear here.</p></div>) if not pending else None}
        <div className="ai-drafts">{[
            <article key={draft["id"]} className="card ai-draft"><div className="ai-draft-top"><span className="ai-mode-tag">{label(draft["mode"])}</span><span className="ai-estimate-tag">Estimated costs</span></div>
                <h3>{draft["title"]}</h3><p>{draft["summary"]}</p>
                {(<div className="ai-trip-edits" aria-label="Proposed journey route"><h4>{journeyLabel(draft["journey"])}</h4>
                    <ul>{[<li key={stop["id"]}>{stop["city"] + " · " + stop["arrival_date"] + " – " + stop["departure_date"] + " · " + stop["zone"]}</li> for stop in draft["journey"]["stops"]]}</ul>
                    <p>{str(len(draft["journey"]["legs"])) + " intercity transport legs, including departure and any return travel."}</p>
                </div>) if draft.get("journey") else None}
                {(<div className="ai-trip-edits" aria-label="Proposed trip details"><h4>Trip details</h4>{[
                    <div key={edit["field"]}><strong>{edit["label"]}</strong><span>{detail(edit["before"], edit["field"], draft["trip_before"]["currency"])}</span><span aria-hidden="true">→</span><span>{detail(edit["after"], edit["field"], draft["trip_after"]["currency"])}</span></div>
                    for edit in draft.get("trip_edits", [])
                ]}</div>) if len(draft.get("trip_edits", [])) > 0 else None}
                <div className="ai-cost-comparison"><div><small>Current total, with reserve</small><strong>{money(draft["original_total_cents"], draft.get("trip_before", {}).get("currency", currency))}</strong></div><span>→</span><div><small>Proposed total, with reserve</small><strong>{money(draft["total_cents"], draft.get("trip_after", {}).get("currency", currency))}</strong></div></div>
                <p className="ai-checks">✓ {draft["checks"].join(" · ")}</p>
                {(<form className="ai-price-form" onSubmit={lambda (e: FormEvent) { savePrices(e, draft); }}>
                    <h4>Some prices are missing</h4>
                    <button type="button" className="secondary" disabled={busy} onClick={lambda { onCompose(draft["mode"], "Complete the exact draft titled " + draft["title"] + " with realistic numeric whole-party cost estimates for every item. Preserve its schedule and stay within my budget. Clearly mark approximate prices. I want a complete plan I can save and then edit."); }}>Ask AI to fill in prices ↗</button>
                    <p>Or enter each price yourself: the total for your whole group in {currency}, including fees. Enter 0 only if the item is free.</p>
                    {[
                        <div key={str(index)}><label htmlFor={"estimate-" + draft["id"] + "-" + str(index)}>{change["after"]["title"] + " · " + change["after"]["date"]}</label>
                            <input id={"estimate-" + draft["id"] + "-" + str(index)} type="number" min="0" max="100000000" step="0.01" required={True}
                                value={prices.get(draft["id"] + ":" + str(index), "")} placeholder={currency + " 0.00"} disabled={busy}
                                onChange={lambda (e: ChangeEvent) { prices = {**prices, draft["id"] + ":" + str(index): e.target.value}; }}/></div>
                        for (index, change) in enumerate(draft["changes"]) if change["price_unknown"]
                    ]}
                    {(<p className="chat-error" role="alert">{priceErrors[draft["id"]]}</p>) if priceErrors.get(draft["id"], "") else None}
                    <button className="secondary" type="submit" disabled={busy}>Check prices and budget</button>
                </form>) if not draft["can_apply"] else None}
                <div className="ai-changes">{[
                    <div key={str(index)} className="ai-change"><span className="change-type">{"EDIT" if change["item_id"] else "ADD"}</span><div>
                        {(<p className="ai-before">{change["before"]["title"] + " · " + change["before"]["date"] + " " + change["before"]["time"] + " · " + money(change["before"]["cost_cents"])}</p>) if change["before"] else None}
                        <h4>{change["after"]["title"]}</h4><p>{change["after"]["date"] + " · " + change["after"]["time"] + " · " + str(change["after"]["duration_minutes"]) + " min"}</p>
                        {(<p>{change["after"]["journey"]["zone"] + " → " + change["after"]["journey"]["arrival_date"] + " " + change["after"]["journey"]["arrival_time"] + " " + change["after"]["journey"]["end_zone"]}</p>) if change["after"].get("journey", {}).get("zone", "") and change["after"].get("journey", {}).get("arrival_date", "") and change["after"].get("journey", {}).get("arrival_time", "") and change["after"].get("journey", {}).get("end_zone", "") else None}
                        {(<FlightCard flight={change["after"]["flight"]}/>) if change["after"].get("flight", {}).get("source_url") else None}
                        <p>{change["after"]["location"]}</p><strong>{"Unknown price" if change["price_unknown"] else money(change["after"]["cost_cents"], draft.get("trip_after", {}).get("currency", currency))}</strong>
                        {(<p className="ai-change-notes">{change["after"]["notes"]}</p>) if change["after"]["notes"] else None}
                    </div></div> for (index, change) in enumerate(draft["changes"])
                ]}</div>
                <PolicyReview rows={draft.get("policy_reviews", [])}/>
                <div className="ai-draft-warning">{[<p key={warning}>{warning}</p> for warning in draft["warnings"]]}{[<p key={issue}>{issue}</p> for issue in draft["issues"]]}</div>
                <label className="ai-ack"><input type="checkbox" checked={acknowledged.get(draft["id"], False)} disabled={busy or not draft["can_apply"]}
                    onChange={lambda (e: ChangeEvent) { acknowledged = {**acknowledged, draft["id"]: e.target.checked}; }}/>
                    <span>I've reviewed these changes. Prices and travel details are estimates until confirmed.</span></label>
                <div className="ai-review-actions"><button type="button" className="primary" disabled={busy or not draft["can_apply"] or not acknowledged.get(draft["id"], False)}
                    onClick={lambda { onReview(draft["id"], True, acknowledged.get(draft["id"], False)); }}>Save this plan</button>
                    <button type="button" className="secondary" disabled={busy} onClick={lambda { onReview(draft["id"], False, False); }}>Keep current plan</button>
                    <button type="button" className="text-button" disabled={busy} onClick={lambda { onCompose(draft["mode"], "Please revise the proposal titled " + draft["title"] + ". I would prefer: "); }}>Refine in chat ↗</button></div>
                <small className="ai-expiry">Drafts expire after 30 minutes, or sooner if the trip changes.</small>
            </article> for draft in pending
        ]}</div>
        {(<details className="card ai-draft-history"><summary>Previous proposals ({str(len(history))})</summary>{[
            <div key={draft["id"]}><strong>{draft["title"]}</strong><span>{status(draft)}</span>
                {(<small>Ask for a new draft based on your current trip.</small>) if status(draft) in ["stale", "expired"] else None}</div> for draft in history
        ]}</details>) if history else None}
    </section>
}
