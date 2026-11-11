"""Trip-scoped conversations and reviewable AI drafts; models never write items."""
import json;
import journey.model as journey_model;
import re;
import hashlib;
import copy;
import from decimal { Decimal }
import from uuid { uuid4, UUID }
import from datetime { datetime, timedelta, timezone }
import from replan.engine { snapshot, validate }
import from planning.context { read_facts }
import from assistant.provider { configuration }
import assistant.preferences as preferences;

def now -> str { return datetime.now(timezone.utc).isoformat(); }

def install(conn: any) -> None {
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS assistant_requests (
            id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            signature TEXT NOT NULL, status TEXT NOT NULL, created TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS assistant_messages (
            id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            role TEXT NOT NULL, text TEXT NOT NULL, payload TEXT NOT NULL, created TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS assistant_drafts (
            id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            request_id TEXT NOT NULL REFERENCES assistant_requests(id) ON DELETE CASCADE,
            base_version INTEGER NOT NULL, fingerprint TEXT NOT NULL, payload TEXT NOT NULL,
            status TEXT NOT NULL, expires TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS assistant_messages_trip ON assistant_messages(trip_id);
        CREATE INDEX IF NOT EXISTS assistant_drafts_trip ON assistant_drafts(trip_id);
    """);
    preferences.install(conn);
}

def planning_facts(conn: any, trip_id: str) -> dict[str, any] {
    facts = read_facts(conn, trip_id);
    facts["trip_preferences"] = preferences.read(conn, trip_id);
    return facts;
}

def fingerprint(state: dict[str, any], facts: dict[str, any]) -> str {
    return hashlib.sha256(json.dumps({"state": state, "facts": facts}, sort_keys=True).encode()).hexdigest();
}

def read(conn: any, trip_id: str) -> dict[str, any] {
    state = snapshot(conn, trip_id); facts = planning_facts(conn, trip_id);
    signature = fingerprint(state, facts); messages = [];
    rows = conn.execute("SELECT * FROM assistant_messages WHERE trip_id=? ORDER BY rowid DESC LIMIT 80", (trip_id,)).fetchall();
    for row in reversed(rows) {
        messages.append({"id": row["id"], "role": row["role"], "text": row["text"],
            "created": row["created"], **json.loads(row["payload"])});
    }
    drafts = [];
    for row in conn.execute("SELECT * FROM assistant_drafts WHERE trip_id=? ORDER BY rowid DESC LIMIT 15", (trip_id,)) {
        draft = json.loads(row["payload"]); status = row["status"];
        if status == "pending" {
            if row["fingerprint"] != signature { status = "stale"; }
            elif row["expires"] <= now() { status = "expired"; }
        }
        draft.update({"id": row["id"], "status": status, "expires": row["expires"]});
        drafts.append(draft);
    }
    pending = conn.execute("SELECT count(*) FROM assistant_requests WHERE trip_id=? AND status='pending' AND created>?",
        (trip_id, (datetime.now(timezone.utc) - timedelta(minutes=4)).isoformat())).fetchone()[0];
    return {"config": configuration(), "messages": messages, "drafts": drafts, "preferences": facts["trip_preferences"],
        "trip_version": state["version"], "pending": bool(pending), "checked_at": now()};
}

def begin(conn: any, trip_id: str, request_id: str, message: str, mode: str, search: bool) -> dict[str, any] {
    if not isinstance(message, str) or not message.strip() or len(message) > 4000 { raise ValueError("Enter a message of 1–4000 characters."); }
    if mode not in ["ask", "plan", "backup", "replan", "edit"] { raise ValueError("Choose a supported planning mode."); }
    if type(search) is not bool { raise ValueError("Web search must be true or false."); }
    try { valid_id = str(UUID(request_id)); }
    except (ValueError, TypeError, AttributeError) { raise ValueError("Invalid request ID. Reload and retry.") from None; }
    if valid_id != request_id { raise ValueError("Invalid request ID. Reload and retry."); }
    conn.execute("BEGIN IMMEDIATE");
    state = snapshot(conn, trip_id); facts = planning_facts(conn, trip_id);
    signature = hashlib.sha256(json.dumps([trip_id, message, mode, search]).encode()).hexdigest();
    prior = conn.execute("SELECT * FROM assistant_requests WHERE id=?", (request_id,)).fetchone();
    if prior {
        if prior["trip_id"] != trip_id or prior["signature"] != signature { raise ValueError("Request ID was already used for a different message."); }
        if prior["status"] == "complete" { conn.commit(); return {"replay": True}; }
        raise ValueError("This request is already running or failed. Wait, then send a new message to retry.");
    }
    pending = conn.execute("SELECT id FROM assistant_requests WHERE trip_id=? AND status='pending' AND created>?",
        (trip_id, (datetime.now(timezone.utc) - timedelta(minutes=4)).isoformat())).fetchone();
    if pending { raise ValueError("Another message for this trip is still running. Please wait."); }
    history = read(conn, trip_id)["messages"];
    conn.execute("INSERT INTO assistant_requests VALUES (?,?,?,?,?)", (request_id, trip_id, signature, "pending", now()));
    conn.commit();
    context = copy.deepcopy(state);
    # Confirmation numbers are unnecessary for planning and never leave the server.
    for item in context["items"] {
        item["locked"] = bool(item["protected"] or item["paid"] or item["done"] or item.get("reference"));
        item.pop("reference", None);
    }
    context["traveler_facts"] = facts; context["current_time_utc"] = now();
    context["planning_preferences"] = facts["trip_preferences"];
    context["recent_drafts"] = [];
    for row in conn.execute("SELECT payload FROM assistant_drafts WHERE trip_id=? AND status='pending' ORDER BY rowid DESC LIMIT 2", (trip_id,)) {
        draft = json.loads(row["payload"]); proposed = [];
        for change in draft["changes"] {
            item = copy.deepcopy(change["after"]); item.pop("reference", None);
            item["item_id"] = change["item_id"]; item["price_unknown"] = change["price_unknown"];
            proposed.append(item);
        }
        context["recent_drafts"].append({"title": draft["title"], "summary": draft["summary"], "changes": proposed, "trip_changes": draft.get("trip_changes", {}), "journey": draft.get("journey")});
    }
    return {"replay": False, "state": state, "facts": facts, "context": context,
        "history": history, "fingerprint": fingerprint(state, facts)};
}

def trip_patch(state: dict[str, any], facts: dict[str, any], patch: any) -> dict[str, any] {
    allowed = {"title": 160, "destination": 160, "departure_location": 160, "return_location": 160, "start_date": 10, "end_date": 10, "currency": 3, "notes": 5000, "budget_cents": 0};
    if not isinstance(patch, dict) or any(key not in allowed for key in patch) { raise ValueError("Only the active trip's name, destination, departure and return locations, dates, currency, budget and notes can be edited."); }
    after = copy.deepcopy(state["trip"]);
    for (key, value) in patch.items() {
        if value is None { continue; }
        if key == "budget_cents" {
            if type(value) is not int or not 0 <= value <= 10000000000 { raise ValueError("Trip budget must be a nonnegative integer amount."); }
        } else {
            if not isinstance(value, str) or len(value) > allowed[key] { raise ValueError("Invalid trip " + key + "."); }
            value = value.strip();
            if key == "currency" { value = value.upper(); }
            if key not in ["notes", "departure_location", "return_location"] and not value { raise ValueError("Trip " + key + " cannot be blank."); }
        }
        after[key] = value;
    }
    for key in ["start_date", "end_date"] {
        if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", after[key]) { raise ValueError("Trip dates must use YYYY-MM-DD."); }
        datetime.fromisoformat(after[key]);
    }
    if after["end_date"] < after["start_date"] { raise ValueError("Trip return date must be on or after departure."); }
    if after["currency"] not in ["USD", "EUR", "GBP", "CAD", "JPY", "CNY", "AUD", "CHF", "KRW", "INR"] { raise ValueError("Choose a supported trip currency."); }
    if after["currency"] != state["trip"]["currency"] and (any(i["cost_cents"] > 0 for i in state["items"]) or facts.get("reserve_minor", 0)) {
        raise ValueError("Currency cannot change while the trip has costs or a reserve; no exchange conversion is performed.");
    }
    return after;
}

def check_plan(state: dict[str, any], facts: dict[str, any], plan: dict[str, any]) -> dict[str, any] {
    if not isinstance(plan, dict) or not isinstance(plan.get("changes"), list) or len(plan["changes"]) > 40 {
        raise ValueError("A plan can have at most 40 itinerary changes.");
    }
    after_trip = trip_patch(state, facts, plan.get("trip_changes", {}));
    journey = journey_model.normalize(plan["journey"], after_trip) if plan.get("journey") is not None else state.get("journey");
    journey_changed = journey != state.get("journey");
    if journey is not None {
        journey = journey_model.normalize(journey, after_trip);
        endpoints = {"departure_location": journey["origin"]["city"], "return_location": journey["return_to"]["city"] if journey["return_to"] else "", "destination": journey["stops"][0]["city"]};
        for (key, value) in endpoints.items() {
            if key in plan.get("trip_changes", {}) and after_trip[key] != value { raise ValueError("Trip cities must match the proposed journey route. Update the route and affected items together."); }
        }
        after_trip.update(endpoints);
    }
    delta = {key: after_trip[key] for key in after_trip if after_trip[key] != state["trip"][key]};
    if not plan["changes"] and not delta and not journey_changed { raise ValueError("The proposal contains no changes."); }
    if not isinstance(plan.get("title"), str) or not plan["title"].strip() or len(plan["title"]) > 160 { raise ValueError("Invalid plan title."); }
    if not isinstance(plan.get("summary"), str) or len(plan["summary"]) > 5000 { raise ValueError("Invalid plan explanation."); }
    original = {i["id"]: i for i in state["items"]}; nodes = copy.deepcopy(original);
    augmented = copy.deepcopy(state); augmented["trip"] = after_trip; augmented["journey"] = journey;
    changes = []; displayed = []; seen = `set(); missing_price = False;
    for (index, raw) in enumerate(plan["changes"]) {
        if not isinstance(raw, dict) { raise ValueError("Invalid itinerary change."); }
        item_id = raw.get("item_id");
        if not isinstance(item_id, str) or item_id in seen { raise ValueError("Each existing item can only change once per plan."); }
        if item_id { seen.add(item_id); }
        before = original.get(item_id);
        if item_id and before is None { raise ValueError("The plan refers to an item outside this trip."); }
        if before and (before["protected"] or before["done"] or before["paid"] or before.get("reference")) { raise ValueError("Paid, confirmed, completed, referenced and fixed items must be kept unchanged."); }
        if before and before["category"] in ["packing", "expense"] { raise ValueError("AI plans cannot replace packing items or expenses."); }
        for (field, maximum) in [("title", 160), ("location", 300), ("notes", 2500)] {
            if not isinstance(raw.get(field), str) or len(raw[field]) > maximum { raise ValueError("Invalid " + field + " in draft."); }
        }
        if not raw["title"].strip() or raw.get("category") not in ["activity", "food", "transport", "stay"] { raise ValueError("Invalid item title or category."); }
        if before and before["category"] != raw["category"] { raise ValueError("An edit must preserve the item's category."); }
        if not isinstance(raw.get("date"), str) or not isinstance(raw.get("time"), str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", raw["date"]) or not re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", raw["time"]) {
            raise ValueError("Every proposed item needs a valid date and time.");
        }
        datetime.fromisoformat(raw["date"] + "T" + raw["time"]);
        duration: any = raw.get("duration_minutes"); cost: any = raw.get("cost_cents");
        if type(duration) is not int or not 1 <= duration <= 1440 { raise ValueError("Item durations must be between 1 and 1440 minutes."); }
        if cost is None { missing_price = True; }
        elif type(cost) is not int or not 0 <= cost <= 10000000000 { raise ValueError("Item estimates must be nonnegative integer amounts."); }
        key = item_id or "new-" + str(index);
        base: any = copy.deepcopy(before) if before else {"id": key, "trip_id": state["trip"]["id"], "protected": False,
            "fixed": False, "done": False, "paid": False, "reference": "", "latest_start": ""};
        base.update({k: raw[k] for k in ["title", "category", "date", "time", "location", "duration_minutes", "notes"]});
        base["cost_cents"] = cost if cost is not None else 0;
        if journey is not None {
            detail = raw.get("journey") or {key: raw.get(key, "") for key in ["stop_id", "leg_id", "arrival_date", "arrival_time"]};
            base["journey"] = journey_model.bind(base, detail, journey);
        }
        if not before { augmented["items"].append(copy.deepcopy(base)); }
        nodes[key] = base; changes.append({"item_id": key});
        displayed.append({"item_id": item_id, "before": before, "after": base, "price_unknown": cost is None});
    }
    # Reuse the existing graph, fixed-item, overlap, latest-start and budget rules.
    reserve = facts.get("reserve_minor", 0);
    if type(reserve) is not int or reserve < 0 { raise ValueError("Invalid contingency reserve."); }
    for item in nodes.values() {
        if item["date"] and not after_trip["start_date"] <= item["date"] <= after_trip["end_date"] {
            raise ValueError("Move " + item["title"] + " into the proposed trip dates in this same plan, or keep dates that include it.");
        }
        if not journey and item["date"] and item["time"] and (datetime.fromisoformat(item["date"] + "T" + item["time"]) + timedelta(minutes=item["duration_minutes"])).date().isoformat() > after_trip["end_date"] {
            raise ValueError("An item ends after the proposed trip return date.");
        }
    }
    journey_issues = journey_model.validate(journey, after_trip, list(nodes.values()), complete=bool(changes)) if journey else [];
    total = validate(augmented, nodes, changes, reserve) if changes else sum(i["cost_cents"] for i in nodes.values()) + reserve;
    if "budget_cents" in delta and after_trip["budget_cents"] and total > after_trip["budget_cents"] { raise ValueError("Existing costs exceed the proposed budget. Include lower-cost item changes or choose a larger budget."); }
    labels = {"title": "Trip name", "destination": "Destination", "departure_location": "Departing from", "return_location": "Return to", "start_date": "Departure date", "end_date": "Return date", "currency": "Currency", "budget_cents": "Budget", "notes": "Trip notes"};
    return {"title": plan["title"].strip(), "summary": plan["summary"], "changes": displayed,
        "journey": journey, "journey_changed": journey_changed,
        "trip_changes": delta, "trip_before": state["trip"], "trip_after": after_trip,
        "trip_edits": [{"field": key, "label": labels[key], "before": state["trip"][key], "after": value} for (key, value) in delta.items()],
        "original_total_cents": sum(i["cost_cents"] for i in original.values()) + reserve,
        "total_cents": None if missing_price else total, "reserve_cents": reserve,
        "checks": (["City order, transport coverage, local time zones and transfer buffers"] if journey and changes else []) + (["Trip details"] if delta else []) + (["Trip dates", "Schedule overlaps", "Dependencies and fixed items"] if changes else ["Itinerary date bounds"]) + (["Budget and reserve"] if not missing_price and (changes or "budget_cents" in delta) else []),
        "issues": ["Some prices are unknown. Ask for a revised estimate before saving."] if missing_price else [],
        "warnings": journey_issues + ["AI prices are estimates, not live quotes. Confirm availability, opening hours, travel times and traveler eligibility before booking."] + (["Changing trip dates or locations requires fresh checks of hours, routes and reservations."] if any(key in delta for key in ["start_date", "end_date", "destination", "departure_location", "return_location"]) else []),
        "can_apply": not missing_price};
}

def finish(conn: any, trip_id: str, request_id: str, message: str, mode: str,
    captured: dict[str, any], result: dict[str, any]) -> dict[str, any] {
    drafts = []; issues = [];
    for plan in result.get("plans", []) {
        try { drafts.append(check_plan(captured["state"], captured["facts"], plan)); }
        except (ValueError, KeyError, TypeError) as error { issues.append(str(error)); }
    }
    conn.execute("BEGIN IMMEDIATE");
    state = snapshot(conn, trip_id); facts = planning_facts(conn, trip_id);
    stale = fingerprint(state, facts) != captured["fingerprint"];
    stamp = now(); expires = (datetime.now(timezone.utc) + timedelta(minutes=30)).isoformat();
    for draft in drafts {
        draft["mode"] = result.get("mode", mode);
        conn.execute("INSERT INTO assistant_drafts VALUES (?,?,?,?,?,?,?,?)",
            (str(uuid4()), trip_id, request_id, captured["state"]["version"], captured["fingerprint"],
                json.dumps(draft), "stale" if stale else "pending", expires));
    }
    payload = {"sources": result.get("sources", []), "research": result.get("research", ""),
        "mode": mode, "issues": issues, "stale": stale};
    for (role, text, data) in [("user", message, {"mode": mode}), ("assistant", result["answer"], payload)] {
        conn.execute("INSERT INTO assistant_messages VALUES (?,?,?,?,?,?)", (str(uuid4()), trip_id, role, text, json.dumps(data), stamp));
    }
    conn.execute("UPDATE assistant_requests SET status='complete' WHERE id=? AND trip_id=?", (request_id, trip_id));
    conn.commit(); return read(conn, trip_id);
}

def update_prices(conn: any, trip_id: str, draft_id: str, prices: dict[str, any]) -> dict[str, any] {
    if not isinstance(prices, dict) or not prices { raise ValueError("Enter at least one missing price estimate."); }
    conn.execute("BEGIN IMMEDIATE");
    state = snapshot(conn, trip_id); facts = planning_facts(conn, trip_id);
    row = conn.execute("SELECT * FROM assistant_drafts WHERE id=? AND trip_id=?", (draft_id, trip_id)).fetchone();
    if row is None or row["status"] != "pending" { raise ValueError("This draft is no longer available for editing."); }
    if row["expires"] <= now() or row["fingerprint"] != fingerprint(state, facts) { raise ValueError("This draft expired or your trip changed. Ask for a fresh plan."); }
    draft = json.loads(row["payload"]);
    for (key, value) in prices.items() {
        if not isinstance(key, str) or not key.isdigit() or str(int(key)) != key or int(key) >= len(draft["changes"]) { raise ValueError("Invalid draft item."); }
        change = draft["changes"][int(key)];
        if not change["price_unknown"] { raise ValueError("Only missing prices can be filled in here."); }
        if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,9}(?:\.[0-9]{1,2})?", value.strip()) { raise ValueError("Enter nonnegative prices with at most two decimal places."); }
        amount = Decimal(value.strip()) * 100;
        if amount > 10000000000 { raise ValueError("Price estimate is too large."); }
        change["after"]["cost_cents"] = int(amount); change["price_unknown"] = False;
        change["after"]["notes"] = (change["after"]["notes"][:2400] + "\nPrice supplied by traveler as an unverified estimate.");
    }
    raw = {"title": draft["title"], "summary": draft["summary"], "trip_changes": draft.get("trip_changes", {}), "journey": draft.get("journey"), "changes": [
        {**change["after"], "item_id": change["item_id"], "cost_cents": None if change["price_unknown"] else change["after"]["cost_cents"]}
        for change in draft["changes"]]};
    checked = check_plan(state, facts, raw); checked["mode"] = draft["mode"];
    conn.execute("UPDATE assistant_drafts SET payload=? WHERE id=? AND trip_id=?", (json.dumps(checked), draft_id, trip_id));
    conn.commit(); return read(conn, trip_id);
}

def review(conn: any, trip_id: str, draft_id: str, accept: bool, acknowledged: bool) -> dict[str, any] {
    if type(accept) is not bool or type(acknowledged) is not bool { raise ValueError("Review choices must be true or false."); }
    conn.execute("BEGIN IMMEDIATE");
    state = snapshot(conn, trip_id); facts = planning_facts(conn, trip_id);
    row = conn.execute("SELECT * FROM assistant_drafts WHERE id=? AND trip_id=?", (draft_id, trip_id)).fetchone();
    if row is None { raise ValueError("This draft does not belong to this trip."); }
    desired = "accepted" if accept else "rejected";
    if row["status"] == desired { conn.commit(); return read(conn, trip_id); }
    if row["status"] != "pending" { raise ValueError("This draft has already been reviewed or is stale."); }
    if accept {
        if not acknowledged { raise ValueError("Acknowledge the estimates and unverified travel details before saving."); }
        if row["expires"] <= now() or row["fingerprint"] != fingerprint(state, facts) { raise ValueError("Your trip or this draft changed. Ask for a fresh plan before saving."); }
        draft = json.loads(row["payload"]);
        raw = {"title": draft["title"], "summary": draft["summary"], "trip_changes": draft.get("trip_changes", {}), "journey": draft.get("journey"), "changes": [
            {**change["after"], "item_id": change["item_id"], "cost_cents": None if change["price_unknown"] else change["after"]["cost_cents"]}
            for change in draft["changes"]]};
        checked = check_plan(state, facts, raw);
        if not checked["can_apply"] { raise ValueError("Resolve unknown prices before saving this draft."); }
        if checked["trip_changes"] {
            trip = checked["trip_after"];
            conn.execute("UPDATE trips SET title=?,destination=?,start_date=?,end_date=?,currency=?,budget_cents=?,notes=?,departure_location=?,return_location=? WHERE id=?",
                (trip["title"], trip["destination"], trip["start_date"], trip["end_date"], trip["currency"], trip["budget_cents"], trip["notes"], trip["departure_location"], trip["return_location"], trip_id));
            if any(key in checked["trip_changes"] for key in ["destination", "departure_location", "return_location", "start_date", "end_date", "currency"]) {
                retained = {key: facts[key] for key in ["profile", "reserve_minor", "zone"] if key in facts};
                if "destination" in checked["trip_changes"] { retained.pop("zone", None); }
                conn.execute("UPDATE planning_contexts SET payload=? WHERE trip_id=?", (json.dumps(retained), trip_id));
            }
        }
        if checked.get("journey") is not None and checked.get("journey_changed") { journey_model.write(conn, trip_id, checked["journey"]); }
        for change in checked["changes"] {
            item = change["after"]; item_id = change["item_id"] or str(uuid4());
            note = (item["notes"] + "\nAI planning estimate. Verify details before booking.")[:3000];
            if change["item_id"] {
                conn.execute("UPDATE items SET title=?,category=?,date=?,time=?,location=?,notes=?,cost_cents=? WHERE id=? AND trip_id=?",
                    (item["title"], item["category"], item["date"], item["time"], item["location"], note, item["cost_cents"], item_id, trip_id));
            } else {
                conn.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?,0,0)",
                    (item_id, trip_id, item["title"], item["category"], item["date"], item["time"], item["location"], "", note, item["cost_cents"]));
            }
            journey_model.write_item(conn, item_id, item.get("journey", {}));
            conn.execute("INSERT INTO replan_rules(item_id,duration_minutes) VALUES (?,?) ON CONFLICT(item_id) DO UPDATE SET duration_minutes=excluded.duration_minutes",
                (item_id, item["duration_minutes"]));
        }
        conn.execute("UPDATE assistant_drafts SET status='stale' WHERE trip_id=? AND status='pending' AND id!=?", (trip_id, draft_id));
    }
    conn.execute("UPDATE assistant_drafts SET status=? WHERE id=?", (desired, draft_id));
    conn.commit(); return read(conn, trip_id);
}
