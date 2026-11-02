"""Versioned synthetic backup observations. This store never opens the travel database."""
import os;
import json;
import sqlite3;
import uuid;
import from datetime { datetime, timedelta, timezone }
import from decimal { Decimal }
import from hashlib { sha256 }
import from backup.validation_fixtures { run_fixture }

glob SCHEMA_VERSION = 1;
glob VALIDATOR_VERSION = "backup-selection-v2";

def clock(now: datetime | None = None) -> datetime {
    now = now or datetime.now(timezone.utc);
    if now.utcoffset() is None { raise ValueError("History clock needs a UTC offset"); }
    return now;
}

def identifier(value: str) -> str {
    if not isinstance(value, str) or len(value) != 36 or str(uuid.UUID(value)) != value {
        raise ValueError("Use a canonical UUID for the history session and request");
    }
    return value;
}

def connect_history -> sqlite3.Connection {
    data_dir = os.path.join(os.path.dirname(__file__), "..", ".jac", "data");
    path = os.path.realpath(os.environ.get("BACKUP_HISTORY_DB_PATH") or os.path.join(data_dir, "backup-history.sqlite3"));
    travel = os.path.realpath(os.environ.get("TRAVEL_DB_PATH") or os.path.join(data_dir, "travel.sqlite3"));
    if path == travel { raise ValueError("Backup history needs its own database"); }
    os.makedirs(os.path.dirname(path), exist_ok=True);
    conn = sqlite3.connect(path, timeout=10.0);
    conn.row_factory = sqlite3.Row;
    try {
        version = conn.execute("PRAGMA user_version").fetchone()[0];
        if version not in (0, SCHEMA_VERSION) { raise ValueError("Unsupported backup history database version"); }
        conn.execute("""CREATE TABLE IF NOT EXISTS backup_runs (
            session_id TEXT NOT NULL, revision INTEGER NOT NULL, request_id TEXT NOT NULL,
            request_fingerprint TEXT NOT NULL, schema_version INTEGER NOT NULL,
            validator_version TEXT NOT NULL, payload TEXT NOT NULL,
            PRIMARY KEY(session_id, revision), UNIQUE(session_id, request_id))""");
        conn.execute("PRAGMA user_version = 1");
        conn.commit();
        return conn;
    } except Exception { conn.close(); raise; }
}

def signature(value: dict[str, any]) -> str {
    return sha256(json.dumps(value, sort_keys=True, allow_nan=False).encode()).hexdigest();
}

def default_context(now: datetime) -> dict[str, any] {
    return {"scenario": "rain", "profile_name": "family", "budget": "600",
        "inventory_change": "unchanged",
        "sample_date": (now.astimezone(timezone.utc).date() + timedelta(days=7)).isoformat()};
}

def option_summary(option: dict[str, any]) -> dict[str, any] {
    return {"candidate_id": option["candidate_id"], "title": option["title"],
        "provider_id": option.get("provider_id", option["candidate_id"]), "display_label": option.get("display_label"),
        "status": option["status"], "cost_minor": option["cost"]["projected_total_minor"],
        "source": option["source"], "refresh_state": option["refresh_state"],
        "changes": option.get("changes"),
        "checks": [c for c in option["checks"] if c["status"] != "pass"]};
}

def run_state(row: sqlite3.Row, latest: int, now: datetime,
    expected_context: dict[str, any] | None = None) -> dict[str, any] {
    snapshot = json.loads(row["payload"]);
    result_data = snapshot["report"];
    reasons: list[str] = [];
    if row["revision"] != latest { reasons.append("superseded"); }
    if row["schema_version"] != SCHEMA_VERSION or row["validator_version"] != VALIDATOR_VERSION {
        reasons.append("version_changed");
    }
    if expected_context is not None and signature(snapshot["context"]) != signature(expected_context) {
        reasons.append("inputs_changed");
    }
    checked = datetime.fromisoformat(result_data["checked_at"]);
    expires = datetime.fromisoformat(result_data["expires_at"]);
    if checked.utcoffset() is None or expires.utcoffset() is None or now < checked {
        reasons.append("clock_invalid");
    } elif now >= expires { reasons.append("evidence_expired"); }
    return {"revision": row["revision"], "request_id": row["request_id"],
        "context": snapshot["context"], "checked_at": result_data["checked_at"],
        "expires_at": result_data["expires_at"], "reasons": reasons,
        "recorded_summary": result_data["summary"],
        "recorded_evaluated_summary": result_data.get("evaluated_summary", result_data["summary"]),
        "pipeline": result_data.get("pipeline"),
        "selection": result_data.get("selection"),
        "recorded_options": [option_summary(r) for r in result_data["results"]],
        "recorded_evaluations": [option_summary(r) for r in result_data.get("evaluated_options", result_data["results"])],
        "snapshot": snapshot};
}

def read_history(session_id: str, now: datetime | None = None,
    expected_context: dict[str, any] | None = None) -> dict[str, any] {
    session_id = identifier(session_id); now = clock(now);
    conn = connect_history();
    try {
        # One SELECT fixes the read snapshot even while a different process appends.
        rows = conn.execute("SELECT * FROM backup_runs WHERE session_id=? ORDER BY revision DESC LIMIT 50", (session_id,)).fetchall();
        latest = rows[0]["revision"] if rows else 0;
        entries = [run_state(row, latest, now, expected_context) for row in rows];
        context = entries[0]["context"] if entries else default_context(now);
        for record in entries { record.pop("snapshot"); }
        return {"session_id": session_id, "revision": latest, "entries": entries,
            "context": context, "total": latest, "checked_at": now.isoformat()};
    } finally { conn.close(); }
}

def append_snapshot(session_id: str, request_id: str, expected_revision: int,
    context: dict[str, any], result_data: dict[str, any], now: datetime) -> dict[str, any] {
    session_id = identifier(session_id); request_id = identifier(request_id); now = clock(now);
    if type(expected_revision) is not int or expected_revision < 0 {
        raise ValueError("Expected revision must be a nonnegative integer");
    }
    fingerprint = signature(context);
    payload = json.dumps({"context": context, "report": result_data}, sort_keys=True, allow_nan=False);
    conn = connect_history();
    try {
        conn.execute("BEGIN IMMEDIATE");
        latest = conn.execute("SELECT COALESCE(MAX(revision),0) FROM backup_runs WHERE session_id=?", (session_id,)).fetchone()[0];
        previous = conn.execute("SELECT * FROM backup_runs WHERE session_id=? AND request_id=?", (session_id, request_id)).fetchone();
        if previous is not None {
            if previous["request_fingerprint"] != fingerprint { raise ValueError("Request ID was already used with different inputs"); }
            state = run_state(previous, latest, now, context);
            conn.commit();
            return {"outcome": "saved", "replayed": True, "revision": previous["revision"],
                "report": state["snapshot"]["report"] if not state["reasons"] else None};
        }
        if latest != expected_revision {
            conn.rollback();
            return {"outcome": "conflict", "replayed": False, "revision": latest, "report": None};
        }
        conn.execute("INSERT INTO backup_runs VALUES (?,?,?,?,?,?,?)",
            (session_id, latest + 1, request_id, fingerprint, SCHEMA_VERSION, VALIDATOR_VERSION, payload));
        conn.commit();
        return {"outcome": "saved", "replayed": False, "revision": latest + 1, "report": json.loads(payload)["report"]};
    } except Exception { conn.rollback(); raise; }
    finally { conn.close(); }
}

def save_refresh(session_id: str, request_id: str, expected_revision: int,
    scenario: str = "rain", profile_name: str = "family", budget: str = "600",
    inventory_change: str = "unchanged", sample_date: str = "",
    now: datetime | None = None) -> dict[str, any] {
    now = clock(now); identifier(session_id); identifier(request_id);
    if not sample_date or not inventory_change { raise ValueError("Select a sample date and inventory snapshot"); }
    result_data = run_fixture(scenario, profile_name, budget, now, inventory_change, sample_date, expanded=True);
    context = {"scenario": scenario, "profile_name": profile_name,
        "budget": format(Decimal(budget.strip()).normalize(), "f") if budget.strip() else "",
        "inventory_change": inventory_change, "sample_date": sample_date};
    response = append_snapshot(session_id, request_id, expected_revision, context, result_data, now);
    response["history"] = read_history(session_id, now, context);
    # Another writer may have appended between committing and reading history.
    if response["revision"] != response["history"]["revision"] { response["report"] = None; }
    return response;
}
