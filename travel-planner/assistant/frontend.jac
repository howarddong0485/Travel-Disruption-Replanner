"""Persistent trip conversation sidebar and the unified AI plan review workspace."""
import from browser_ids { request_id }
import from server.main { assistant_state, assistant_chat, assistant_review }
import from journey.frontend { journeyLabel }

def:pub ChatSidebar(trip_id: str, destination: str, onUpdate: any, reload: int = 0,
    compose: int = 0, composeMode: str = "ask", composeText: str = "", externalBusy: bool = False) -> JsxElement {
    browser: any = window;
    has data: dict[str, any] = {}, text: str = "", mode: str = "ask", search: bool = True,
        apiKey: str = "", keyInput: str = "", keyError: str = "",
        busy: bool = False, loading: bool = True, failure: str = "", pendingText: str = "",
        alive: Ref[bool] = Ref(True), sequence: Ref[int] = Ref(0), scrollTarget: Ref[any] = Ref(None);
    async def load -> None {
        if busy { return; }
        request = sequence.current;
        try {
            fresh = await assistant_state(trip_id=trip_id);
            if alive.current and request == sequence.current { data = fresh; onUpdate(fresh, False); failure = ""; }
        } except Exception { if alive.current { failure = "Could not load this conversation. Try Reload."; } }
        finally { if alive.current { loading = False; } }
    }
    can with entry { alive.current = True; }
    can with [trip_id, reload] entry { load(); }
    can with exit { alive.current = False; sequence.current += 1; }
    can with [compose] entry {
        if compose > 0 {
            mode = composeMode; text = composeText;
            field: any = document.getElementById("ai-message");
            if field { field.focus(); }
        }
    }
    can with [data, busy] entry {
        if scrollTarget.current { scrollTarget.current.scrollIntoView({"block": "nearest", "behavior": "smooth"}); }
    }
    async def send(e: FormEvent) -> None {
        e.preventDefault(); if busy or externalBusy or loading or not text.strip() { return; }
        busy = True; failure = ""; pendingText = text.strip(); request = sequence.current;
        try {
            fresh = await assistant_chat(trip_id=trip_id, message=pendingText, mode=mode,
                search=search, request_id=request_id(browser), api_key=apiKey);
            if alive.current and request == sequence.current {
                previous = [draft["id"] for draft in data.get("drafts", [])];
                created = len([draft for draft in fresh.get("drafts", []) if draft["id"] not in previous and draft["status"] == "pending"]) > 0;
                data = fresh; text = ""; pendingText = ""; onUpdate(fresh, mode != "ask" or created);
            }
        } except Exception as error {
            if alive.current and request == sequence.current { failure = str(error); pendingText = ""; }
        } finally { if alive.current and request == sequence.current { busy = False; } }
    }
    def useKey(e: FormEvent) -> None {
        e.preventDefault();
        value = keyInput.strip();
        if not value.startswith("sk-") or len(value) > 512 or not browser.RegExp("^sk-[!-~]+$").test(value) {
            keyError = "Enter an OpenAI API key beginning with sk- and without spaces."; return;
        }
        apiKey = value; keyInput = ""; keyError = ""; failure = "";
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
                    {(<button type="button" className="text-button" disabled={busy} onClick={lambda { apiKey = ""; keyInput = ""; keyError = ""; failure = ""; }}>Clear key</button>) if apiKey else None}</div>
                {(<p className="chat-error" role="alert">{keyError}</p>) if keyError else None}
            </form>
            <small>Your key is used for your AI requests and kept in memory while this assistant is open. Refreshing clears it. API usage is billed to your OpenAI account.</small>
            <p role="status">{"Using your key. It will be checked when you send a message." if apiKey else "Using the app owner’s key. Add yours to use your own account." if data.get("config", {}).get("configured", False) else "Add your key to start chatting."}</p>
        </details>
        <div className="chat-messages" role="log" aria-label="Conversation" aria-busy={busy or loading}>
            {(<div className="chat-welcome"><span className="chat-spark">✦</span><h3>A little help for every turn.</h3>
                <p>Ask about your destination, build an itinerary, or tell me what changed. I’ll help you find a way forward.</p>
                <small>Answers use your active trip and recent conversation.</small></div>) if len(data.get("messages", [])) == 0 else None}
            {[
                <article key={message["id"]} className={"chat-message " + message["role"]}>
                    <p className="message-author">{"YOU" if message["role"] == "user" else "JACPLAN ASSISTANT"}
                        <span>{message.get("mode", "ask")}</span></p>
                    <div className="message-text">{message["text"]}</div>
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
                    placeholder="Tell me what you have in mind…" onChange={lambda (e: ChangeEvent) { text = e.target.value; }}/>
                <div className="composer-actions"><label className="search-toggle"><input type="checkbox" checked={search} disabled={busy}
                    onChange={lambda (e: ChangeEvent) { search = e.target.checked; }}/> Search the web</label>
                    <button className="primary" type="submit" disabled={busy or externalBusy or loading or not text.strip() or not (apiKey or data.get("config", {}).get("configured", False))}>
                        {"Working…" if busy else "Send ↗"}</button></div>
            </form>
            <small>Turn off web search for a faster draft using estimates. Your pet and pace preferences still apply.</small>
            <small>AI suggestions need review. Nothing is booked or changed by a chat message.</small>
        </div>
    </aside>
}

def:pub AIPlanner(data: dict[str, any], currency: str, onCompose: any, onReview: any, onPrices: any, onPreferences: any, busy: bool) -> JsxElement {
    has acknowledged: dict[str, bool] = {}, prices: dict[str, str] = {}, priceErrors: dict[str, str] = {};
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
    pending = [draft for draft in data.get("drafts", []) if draft["status"] == "pending"];
    history = [draft for draft in data.get("drafts", []) if draft["status"] != "pending"];
    preferences = data.get("preferences", {"pet_friendly": False, "pace": "balanced"});
    <section className="ai-planner" aria-label="AI planning workspace">
        <div className="card ai-planner-intro"><p className="eyebrow">ONE TRIP. MORE POSSIBILITIES.</p><h2>Make room for a better plan.</h2>
            <p>Build your itinerary, prepare a backup, or adjust when life happens. Your assistant works with the same trip, budget and conversation.</p>
            <div className="planning-preferences" aria-label="Trip planning preferences">
                <div className="pet-preference"><button type="button" className="pet-toggle" aria-pressed={preferences["pet_friendly"]}
                    disabled={busy or not data.get("trip_version", 0)} onClick={lambda { onPreferences(not preferences["pet_friendly"], preferences["pace"]); }}>
                    {"✓ Pet-friendly" if preferences["pet_friendly"] else "Pet-friendly"}<span>{"On" if preferences["pet_friendly"] else "Off"}</span></button>
                    <small>Plan stays, meals and activities with a pet in mind. Venue policies still need confirmation.</small></div>
                <fieldset className="pace-preference"><legend>Trip pace</legend><div className="pace-buttons">{[
                    <button key={pace} type="button" aria-pressed={preferences["pace"] == pace} disabled={busy or not data.get("trip_version", 0)}
                        onClick={lambda { onPreferences(preferences["pet_friendly"], pace); }}>{"Intense" if pace == "intense" else "Balanced" if pace == "balanced" else "Relax"}</button>
                    for pace in ["intense", "balanced", "relax"]
                ]}</div><small>{"Fuller days with 4–6 main activities" if preferences["pace"] == "intense" else "1–2 main activities with plenty of free time" if preferences["pace"] == "relax" else "2–3 main activities with time to unwind"}</small></fieldset>
                <p className="preference-note">Saved for this trip and used automatically in AI planning, alternatives and replanning.</p>
            </div>
            <div className="ai-quick-actions">
                <button type="button" disabled={busy} onClick={lambda { onCompose("plan", "Build an itinerary for my trip using my saved preferences. Keep my existing arrangements and stay within my budget."); }}><span>◎</span><strong>Plan my trip</strong><small>Turn ideas into an itinerary</small></button>
                <button type="button" disabled={busy} onClick={lambda { onCompose("backup", "Prepare two different backup plans for the vulnerable parts of my itinerary. Explain when I would use each one."); }}><span>⇄</span><strong>Find alternatives</strong><small>Have another way to go</small></button>
                <button type="button" disabled={busy} onClick={lambda { onCompose("replan", "My plans changed: "); }}><span>↗</span><strong>Something changed</strong><small>Repair the affected plans</small></button>
            </div>
            <button type="button" className="text-button" disabled={busy} onClick={lambda { onCompose("edit", "Change my trip details: "); }}>Edit dates, destination, budget or other trip details ↗</button>
        </div>
        <div className="section-heading ai-draft-heading"><div><p className="eyebrow">REVIEW BEFORE YOU SAVE</p><h2>Your proposed plans</h2></div><span className="count-pill">{str(len(pending)) + " to review"}</span></div>
        {(<div className="card ai-drafts-empty"><span>✦</span><h3>Good plans start with a conversation.</h3><p>Choose an action above, or select a planning mode in the conversation sidebar. Your proposals will appear here.</p></div>) if not pending else None}
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
                <div className="ai-cost-comparison"><div><small>Current + reserve</small><strong>{money(draft["original_total_cents"], draft.get("trip_before", {}).get("currency", currency))}</strong></div><span>→</span><div><small>Proposed + reserve</small><strong>{money(draft["total_cents"], draft.get("trip_after", {}).get("currency", currency))}</strong></div></div>
                <p className="ai-checks">✓ {draft["checks"].join(" · ")}</p>
                {(<form className="ai-price-form" onSubmit={lambda (e: FormEvent) { savePrices(e, draft); }}>
                    <h4>This older draft has missing estimates</h4>
                    <button type="button" className="secondary" disabled={busy} onClick={lambda { onCompose(draft["mode"], "Complete the exact draft titled " + draft["title"] + " with realistic numeric whole-party cost estimates for every item. Preserve its schedule and stay within my budget. Clearly mark approximate prices. I want a complete plan I can save and then edit."); }}>Complete this plan with GPT ↗</button>
                    <p>Or enter your own whole-party estimates in {currency}, including fees. Use 0 only for a free item.</p>
                    {[
                        <div key={str(index)}><label htmlFor={"estimate-" + draft["id"] + "-" + str(index)}>{change["after"]["title"] + " · " + change["after"]["date"]}</label>
                            <input id={"estimate-" + draft["id"] + "-" + str(index)} type="number" min="0" max="100000000" step="0.01" required={True}
                                value={prices.get(draft["id"] + ":" + str(index), "")} placeholder={currency + " 0.00"} disabled={busy}
                                onChange={lambda (e: ChangeEvent) { prices = {**prices, draft["id"] + ":" + str(index): e.target.value}; }}/></div>
                        for (index, change) in enumerate(draft["changes"]) if change["price_unknown"]
                    ]}
                    {(<p className="chat-error" role="alert">{priceErrors[draft["id"]]}</p>) if priceErrors.get(draft["id"], "") else None}
                    <button className="secondary" type="submit" disabled={busy}>Check estimates & budget</button>
                </form>) if not draft["can_apply"] else None}
                <div className="ai-changes">{[
                    <div key={str(index)} className="ai-change"><span className="change-type">{"EDIT" if change["item_id"] else "ADD"}</span><div>
                        {(<p className="ai-before">{change["before"]["title"] + " · " + change["before"]["date"] + " " + change["before"]["time"] + " · " + money(change["before"]["cost_cents"])}</p>) if change["before"] else None}
                        <h4>{change["after"]["title"]}</h4><p>{change["after"]["date"] + " · " + change["after"]["time"] + " · " + str(change["after"]["duration_minutes"]) + " min"}</p>
                        {(<p>{change["after"]["journey"]["zone"] + " → " + change["after"]["journey"]["arrival_date"] + " " + change["after"]["journey"]["arrival_time"] + " " + change["after"]["journey"]["end_zone"]}</p>) if change["after"].get("journey") else None}
                        <p>{change["after"]["location"]}</p><strong>{"Unknown price" if change["price_unknown"] else money(change["after"]["cost_cents"], draft.get("trip_after", {}).get("currency", currency))}</strong>
                        {(<p className="ai-change-notes">{change["after"]["notes"]}</p>) if change["after"]["notes"] else None}
                    </div></div> for (index, change) in enumerate(draft["changes"])
                ]}</div>
                <div className="ai-draft-warning">{[<p key={warning}>{warning}</p> for warning in draft["warnings"]]}{[<p key={issue}>{issue}</p> for issue in draft["issues"]]}</div>
                <label className="ai-ack"><input type="checkbox" checked={acknowledged.get(draft["id"], False)} disabled={busy or not draft["can_apply"]}
                    onChange={lambda (e: ChangeEvent) { acknowledged = {**acknowledged, draft["id"]: e.target.checked}; }}/>
                    <span>I reviewed the proposed changes and understand that estimates and travel details need confirmation.</span></label>
                <div className="ai-review-actions"><button type="button" className="primary" disabled={busy or not draft["can_apply"] or not acknowledged.get(draft["id"], False)}
                    onClick={lambda { onReview(draft["id"], True, acknowledged.get(draft["id"], False)); }}>Save this plan</button>
                    <button type="button" className="secondary" disabled={busy} onClick={lambda { onReview(draft["id"], False, False); }}>Keep current plan</button>
                    <button type="button" className="text-button" disabled={busy} onClick={lambda { onCompose(draft["mode"], "Please revise the proposal titled " + draft["title"] + ". I would prefer: "); }}>Refine in chat ↗</button></div>
                <small className="ai-expiry">Drafts expire after 30 minutes and become unavailable when your trip changes.</small>
            </article> for draft in pending
        ]}</div>
        {(<details className="card ai-draft-history"><summary>Previous proposals ({str(len(history))})</summary>{[
            <div key={draft["id"]}><strong>{draft["title"]}</strong><span>{draft["status"]}</span>
                {(<small>Ask for a new draft based on your current trip.</small>) if draft["status"] in ["stale", "expired"] else None}</div> for draft in history
        ]}</details>) if history else None}
    </section>
}
