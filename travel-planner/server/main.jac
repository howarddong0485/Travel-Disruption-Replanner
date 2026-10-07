"""Trip records and travel items persisted in an independent SQLite database."""
import os;
import re;
import uuid;
import sqlite3;
import datetime;
import from decimal { Decimal }
import from backup.models { BackupPreview }
import from backup.planner { prepare }

obj TripView {
    has id: str, title: str, destination: str, start_date: str, end_date: str,
        currency: str, budget_cents: int, notes: str;
}
obj ItemView {
    has id: str, trip_id: str, title: str, category: str, date: str, time: str,
        location: str, reference: str, notes: str, cost_cents: int, done: bool, paid: bool;
}

def _connect -> sqlite3.Connection {
    path = os.path.abspath(os.environ.get("TRAVEL_DB_PATH") or os.path.join(
        os.path.dirname(__file__), "..", ".jac", "data", "travel.sqlite3"));
    os.makedirs(os.path.dirname(path), exist_ok=True);
    conn = sqlite3.connect(path, timeout=10.0);
    conn.row_factory = sqlite3.Row;
    conn.execute("PRAGMA foreign_keys = ON");
    conn.execute("PRAGMA journal_mode = WAL");
    conn.execute("CREATE TABLE IF NOT EXISTS trips (id TEXT PRIMARY KEY, title TEXT NOT NULL, destination TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, currency TEXT NOT NULL, budget_cents INTEGER NOT NULL, notes TEXT NOT NULL)");
    conn.execute("CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE, title TEXT NOT NULL, category TEXT NOT NULL, date TEXT NOT NULL, time TEXT NOT NULL, location TEXT NOT NULL, reference TEXT NOT NULL, notes TEXT NOT NULL, cost_cents INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0, paid INTEGER NOT NULL DEFAULT 0)");
    conn.execute("CREATE INDEX IF NOT EXISTS items_trip ON items(trip_id)");
    conn.commit();
    return conn;
}

def _text(value: str, label: str, maximum: int, required: bool = False) -> str {
    cleaned = value.strip();
    if required and not cleaned { raise ValueError(label + " is required"); }
    if len(cleaned) > maximum { raise ValueError(label + " is too long"); }
    return cleaned;
}
def _date(value: str, required: bool = True) -> str {
    cleaned = value.strip();
    if not cleaned and not required { return ""; }
    try {
        if datetime.date.fromisoformat(cleaned).isoformat() == cleaned { return cleaned; }
    } except ValueError { raise ValueError("Use a valid date in YYYY-MM-DD format"); }
    raise ValueError("Use a valid date in YYYY-MM-DD format");
}
def _money(value: str) -> int {
    text = value.strip() or "0";
    if re.fullmatch(r"[0-9]+(?:\.[0-9]{1,2})?", text) is None {
        raise ValueError("Amounts must be nonnegative with at most two decimal places");
    }
    cents = int(Decimal(text) * 100);
    if cents > 10000000000 { raise ValueError("Amount cannot exceed 100,000,000"); }
    return cents;
}
def _trip(row: sqlite3.Row) -> TripView {
    return TripView(id=str(row["id"]), title=str(row["title"]), destination=str(row["destination"]),
        start_date=str(row["start_date"]), end_date=str(row["end_date"]),
        currency=str(row["currency"]), budget_cents=int(row["budget_cents"]), notes=str(row["notes"]));
}
def _item(row: sqlite3.Row) -> ItemView {
    return ItemView(id=str(row["id"]), trip_id=str(row["trip_id"]), title=str(row["title"]),
        category=str(row["category"]), date=str(row["date"]), time=str(row["time"]),
        location=str(row["location"]), reference=str(row["reference"]), notes=str(row["notes"]),
        cost_cents=int(row["cost_cents"]), done=bool(row["done"]), paid=bool(row["paid"]));
}
def _require_trip(conn: sqlite3.Connection, trip_id: str) -> sqlite3.Row {
    row = conn.execute("SELECT * FROM trips WHERE id = ?", (trip_id,)).fetchone();
    if row is None { raise ValueError("Trip no longer exists. Refresh your trips."); }
    return row;
}

def:pub list_trips -> list[TripView] {
    conn = _connect();
    try { return [_trip(row) for row in conn.execute("SELECT * FROM trips ORDER BY start_date, title, id")]; }
    finally { conn.close(); }
}

def:pub save_trip(title: str, destination: str, start_date: str, end_date: str,
    currency: str = "USD", budget: str = "0", notes: str = "", trip_id: str = "") -> TripView {
    title = _text(title, "Trip name", 160, True);
    destination = _text(destination, "Destination", 160, True);
    start_date = _date(start_date);
    end_date = _date(end_date);
    if end_date < start_date { raise ValueError("Return date must be on or after departure"); }
    currency = currency.strip().upper();
    if currency not in ["USD", "EUR", "GBP", "CAD", "JPY", "CNY", "AUD", "CHF", "KRW", "INR"] {
        raise ValueError("Choose a supported trip currency");
    }
    cents = _money(budget);
    notes = _text(notes, "Trip notes", 5000);
    conn = _connect();
    try {
        conn.execute("BEGIN IMMEDIATE");
        if trip_id {
            old = _require_trip(conn, trip_id);
            outside = conn.execute("SELECT id FROM items WHERE trip_id = ? AND date != '' AND (date < ? OR date > ?) LIMIT 1", (trip_id, start_date, end_date)).fetchone();
            if outside is not None { raise ValueError("Move or remove itinerary items outside the new trip dates first"); }
            if str(old["currency"]) != currency and conn.execute("SELECT id FROM items WHERE trip_id = ? AND cost_cents > 0 LIMIT 1", (trip_id,)).fetchone() is not None {
                raise ValueError("Currency cannot change while the trip has costs; no exchange conversion is performed");
            }
            conn.execute("UPDATE trips SET title=?, destination=?, start_date=?, end_date=?, currency=?, budget_cents=?, notes=? WHERE id=?", (title, destination, start_date, end_date, currency, cents, notes, trip_id));
        } else {
            trip_id = str(uuid.uuid4());
            conn.execute("INSERT INTO trips VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (trip_id, title, destination, start_date, end_date, currency, cents, notes));
        }
        conn.commit();
        return _trip(_require_trip(conn, trip_id));
    } finally { conn.close(); }
}

def:pub list_items(trip_id: str) -> list[ItemView] {
    conn = _connect();
    try {
        _require_trip(conn, trip_id);
        return [_item(row) for row in conn.execute("SELECT * FROM items WHERE trip_id = ? ORDER BY date = '', date, time = '', time, title, id", (trip_id,))];
    } finally { conn.close(); }
}

def:pub preview_backups(trip_id: str, item_id: str, trigger: str) -> BackupPreview {
    conn = _connect();
    try {
        # Read trip and items from the same SQLite snapshot; no itinerary writes.
        conn.execute("BEGIN");
        trip = dict(_require_trip(conn, trip_id));
        items = [dict(row) for row in conn.execute("SELECT * FROM items WHERE trip_id=? ORDER BY id", (trip_id,))];
        return prepare(trip, items, item_id, trigger, datetime.datetime.now(datetime.timezone.utc));
    } finally { conn.close(); }
}

def:pub save_item(trip_id: str, title: str, category: str = "activity", date: str = "",
    time: str = "", location: str = "", reference: str = "", notes: str = "",
    cost: str = "0", item_id: str = "") -> ItemView {
    title = _text(title, "Item title", 160, True);
    if category not in ["activity", "transport", "stay", "food", "packing", "expense"] {
        raise ValueError("Unknown travel item category");
    }
    date = _date(date, False);
    time = time.strip();
    if time and re.fullmatch(r"(?:[01][0-9]|2[0-3]):[0-5][0-9]", time) is None {
        raise ValueError("Time must be HH:MM, from 00:00 to 23:59");
    }
    if time and not date { raise ValueError("Choose a date when adding a time"); }
    cents = _money(cost);
    if category == "packing" and (date or time or cents) {
        raise ValueError("Packing items have no date, time, or cost");
    }
    location = _text(location, "Location", 300);
    reference = _text(reference, "Booking reference", 160);
    notes = _text(notes, "Item notes", 3000);
    conn = _connect();
    try {
        conn.execute("BEGIN IMMEDIATE");
        trip = _require_trip(conn, trip_id);
        if date and (date < str(trip["start_date"]) or date > str(trip["end_date"])) {
            raise ValueError("Item date must fall within the trip dates");
        }
        if item_id {
            old = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (item_id, trip_id)).fetchone();
            if old is None { raise ValueError("Item no longer exists. Refresh your plan."); }
            paid = bool(old["paid"]) and cents > 0;
            done = bool(old["done"]) if str(old["category"]) == category else False;
            conn.execute("UPDATE items SET title=?, category=?, date=?, time=?, location=?, reference=?, notes=?, cost_cents=?, done=?, paid=? WHERE id=? AND trip_id=?", (title, category, date, time, location, reference, notes, cents, done, paid, item_id, trip_id));
        } else {
            item_id = str(uuid.uuid4());
            conn.execute("INSERT INTO items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)", (item_id, trip_id, title, category, date, time, location, reference, notes, cents));
        }
        conn.commit();
        return _item(conn.execute("SELECT * FROM items WHERE id=?", (item_id,)).fetchone());
    } finally { conn.close(); }
}

def:pub set_item_state(trip_id: str, item_id: str, done: bool, paid: bool) -> ItemView {
    conn = _connect();
    try {
        conn.execute("BEGIN IMMEDIATE");
        _require_trip(conn, trip_id);
        row = conn.execute("SELECT * FROM items WHERE id=? AND trip_id=?", (item_id, trip_id)).fetchone();
        if row is None { raise ValueError("Item no longer exists. Refresh your plan."); }
        if paid and not int(row["cost_cents"]) { raise ValueError("Only items with a cost can be marked paid"); }
        conn.execute("UPDATE items SET done=?, paid=? WHERE id=? AND trip_id=?", (done, paid, item_id, trip_id));
        conn.commit();
        return _item(conn.execute("SELECT * FROM items WHERE id=?", (item_id,)).fetchone());
    } finally { conn.close(); }
}

def:pub delete_item(trip_id: str, item_id: str) -> bool {
    conn = _connect();
    try {
        _require_trip(conn, trip_id);
        result = conn.execute("DELETE FROM items WHERE id=? AND trip_id=?", (item_id, trip_id));
        conn.commit();
        return result.rowcount > 0;
    } finally { conn.close(); }
}

def:pub delete_trip(trip_id: str) -> bool {
    conn = _connect();
    try {
        result = conn.execute("DELETE FROM trips WHERE id=?", (trip_id,));
        conn.commit();
        return result.rowcount > 0;
    } finally { conn.close(); }
}
