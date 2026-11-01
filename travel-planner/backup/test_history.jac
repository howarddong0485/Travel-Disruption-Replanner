"""Storage lifecycle, freshness, retries and concurrency for independent backup history."""
import os;
import json;
import uuid;
import tempfile;
import from contextlib { contextmanager }
import from concurrent.futures { ThreadPoolExecutor }
import from datetime { datetime, timedelta, timezone }
import from backup.history { connect_history, save_refresh, read_history }

glob HISTORY_CLOCK = datetime(2026, 11, 10, 12, tzinfo=timezone.utc);

@contextmanager
def isolated_history -> any {
    names = ["BACKUP_HISTORY_DB_PATH", "TRAVEL_DB_PATH"];
    previous = {name: os.environ.get(name) for name in names};
    with tempfile.TemporaryDirectory() as directory {
        os.environ[names[0]] = os.path.join(directory, "backups.sqlite3");
        os.environ[names[1]] = os.path.join(directory, "travel.sqlite3");
        try { yield directory; }
        finally {
            for name in names {
                if previous[name] is None { os.environ.pop(name, None); }
                else { os.environ[name] = previous[name]; }
            }
        }
    }
}

def saved(session_id: str, revision: int = 0, request_id: str = "",
    change: str = "unchanged", now: datetime = HISTORY_CLOCK, budget: str = "600") -> dict[str, any] {
    return save_refresh(session_id, request_id or str(uuid.uuid4()), revision,
        budget=budget, inventory_change=change, sample_date="2026-11-17", now=now);
}

test "history survives new connections with complete input and observation snapshots" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); response = saved(session_id);
        assert response["revision"] == 1 and response["report"]["summary"]["passed_fixture_checks"] == 2;
        conn = connect_history();
        try {
            row = conn.execute("SELECT * FROM backup_runs").fetchone();
            snapshot = json.loads(row["payload"]);
            assert row["schema_version"] == 1 and row["validator_version"] == "backup-selection-v2";
            assert snapshot["report"]["input_snapshot"]["trip"]["budget_minor"] == 60000;
            assert snapshot["report"]["input_snapshot"]["risk"]["evidence"]["source"];
            assert snapshot["report"]["results"][0]["observed_candidate"]["transfers"];
        } finally { conn.close(); }
        restored = read_history(session_id, HISTORY_CLOCK);
        assert restored["revision"] == 1 and restored["context"]["budget"] == "600";
        assert "report" not in restored and "snapshot" not in restored["entries"][0];
        assert not os.path.exists(os.environ["TRAVEL_DB_PATH"]);
    }
}

test "retry is idempotent and never extends the original evidence deadline" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4());
        a = saved(session_id, request_id=request_id);
        b = saved(session_id, request_id=request_id, now=HISTORY_CLOCK + timedelta(minutes=2), budget="600.00");
        assert b["replayed"] and b["report"] == a["report"];
        assert b["history"]["total"] == 1;
    }
}

test "older history without change metrics remains readable and is never backfilled" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4());
        saved(session_id, request_id=request_id);
        conn = connect_history();
        try {
            snapshot = json.loads(conn.execute("SELECT payload FROM backup_runs").fetchone()[0]);
            for option in snapshot["report"]["results"] { option.pop("changes"); }
            old_payload = json.dumps(snapshot, sort_keys=True);
            conn.execute("UPDATE backup_runs SET payload=?", (old_payload,)); conn.commit();
            restored = read_history(session_id, HISTORY_CLOCK);
            assert restored["entries"][0]["recorded_options"][0]["changes"] is None;
            replay = saved(session_id, request_id=request_id);
            assert "changes" not in replay["report"]["results"][0];
            assert conn.execute("SELECT payload FROM backup_runs").fetchone()[0] == old_payload;
        } finally { conn.close(); }
    }
}

test "reusing a request ID with different inputs is rejected" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4()); saved(session_id, request_id=request_id);
        caught = False;
        try { saved(session_id, 1, request_id, budget="400"); } except ValueError { caught = True; }
        assert caught and read_history(session_id, HISTORY_CLOCK)["total"] == 1;
    }
}

test "expired observations and retries cannot return a current passing result" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4()); saved(session_id, request_id=request_id);
        expired = saved(session_id, request_id=request_id, now=HISTORY_CLOCK + timedelta(minutes=15));
        assert expired["report"] is None;
        assert "evidence_expired" in expired["history"]["entries"][0]["reasons"];
        assert expired["history"]["entries"][0]["checked_at"] == HISTORY_CLOCK.isoformat();
    }
}

test "older retries cannot supersede a newer provider failure" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4()); saved(session_id, request_id=request_id);
        saved(session_id, 1, change="provider_failure");
        retry = saved(session_id, request_id=request_id);
        assert retry["report"] is None and retry["history"]["revision"] == 2;
        assert "superseded" in retry["history"]["entries"][1]["reasons"];
        latest = retry["history"]["entries"][0];
        assert latest["recorded_options"] == [] and latest["selection"]["outcome"] == "provider_unavailable";
        assert latest["recorded_evaluated_summary"]["needs_validation"] == 4;
        assert all(option["cost_minor"] is None for option in latest["recorded_evaluations"]);
    }
}

test "changed sample context invalidates earlier observations" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); initial = saved(session_id);
        for (name, value) in [("budget", "400"), ("profile_name", "solo"), ("sample_date", "2026-11-18"), ("scenario", "arrival_delay"), ("inventory_change", "sold_out")] {
            context = dict(initial["history"]["context"]); context[name] = value;
            rows = read_history(session_id, HISTORY_CLOCK, context)["entries"];
            assert "inputs_changed" in rows[0]["reasons"];
        }
    }
}

test "version changes and a backwards clock invalidate reuse" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4()); saved(session_id, request_id=request_id);
        assert "clock_invalid" in read_history(session_id, HISTORY_CLOCK - timedelta(seconds=1))["entries"][0]["reasons"];
        conn = connect_history();
        try { conn.execute("UPDATE backup_runs SET validator_version='older-validator'"); conn.commit(); }
        finally { conn.close(); }
        retry = saved(session_id, request_id=request_id);
        assert retry["report"] is None and "version_changed" in retry["history"]["entries"][0]["reasons"];
    }
}

test "provider failure and recovery are separate immutable revisions" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); a = saved(session_id, change="partial_failure");
        b = saved(session_id, 1, now=HISTORY_CLOCK + timedelta(minutes=1));
        assert a["report"]["evaluated_summary"]["needs_validation"] == 1;
        assert a["report"]["summary"]["passed_fixture_checks"] == 2;
        assert b["report"]["summary"]["passed_fixture_checks"] == 2;
        assert b["history"]["entries"][1]["recorded_evaluations"][0]["cost_minor"] is None;
        b["report"]["results"][0]["title"] = "changed by client";
        assert read_history(session_id, HISTORY_CLOCK)["entries"][0]["recorded_options"][0]["title"] != "changed by client";
    }
}

test "failed database write rolls back without replacing the previous observation" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); saved(session_id);
        conn = connect_history();
        try { conn.execute("CREATE TRIGGER reject_save BEFORE INSERT ON backup_runs BEGIN SELECT RAISE(ABORT, 'test failure'); END"); conn.commit(); }
        finally { conn.close(); }
        caught = False;
        try { saved(session_id, 1); } except Exception { caught = True; }
        assert caught and read_history(session_id, HISTORY_CLOCK)["revision"] == 1;
    }
}

test "concurrent different requests use optimistic revisions and only one wins" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); read_history(session_id, HISTORY_CLOCK);
        with ThreadPoolExecutor(max_workers=4) as pool {
            futures = [pool.submit(saved, session_id) for _ in range(4)];
            responses = [future.result() for future in futures];
        }
        assert sum(r["outcome"] == "saved" for r in responses) == 1;
        assert sum(r["outcome"] == "conflict" for r in responses) == 3;
        assert read_history(session_id, HISTORY_CLOCK)["total"] == 1;
    }
}

test "concurrent retries save one observation" {
    with isolated_history() {
        session_id = str(uuid.uuid4()); request_id = str(uuid.uuid4()); read_history(session_id, HISTORY_CLOCK);
        with ThreadPoolExecutor(max_workers=4) as pool {
            futures = [pool.submit(saved, session_id, 0, request_id) for _ in range(4)];
            responses = [future.result() for future in futures];
        }
        assert all(r["outcome"] == "saved" for r in responses);
        assert sum(not r["replayed"] for r in responses) == 1;
        assert read_history(session_id, HISTORY_CLOCK)["total"] == 1;
    }
}

test "sessions isolate histories even when request IDs match" {
    with isolated_history() {
        a = str(uuid.uuid4()); b = str(uuid.uuid4()); request_id = str(uuid.uuid4());
        saved(a, request_id=request_id); saved(b, request_id=request_id, change="all_sold_out");
        assert read_history(a, HISTORY_CLOCK)["entries"][0]["recorded_summary"]["passed_fixture_checks"] == 2;
        assert read_history(b, HISTORY_CLOCK)["entries"][0]["recorded_evaluated_summary"]["invalid"] == 4;
        assert read_history(b, HISTORY_CLOCK)["entries"][0]["recorded_options"] == [];
        assert read_history(str(uuid.uuid4()), HISTORY_CLOCK)["entries"] == [];
    }
}

test "history is bounded newest first without deleting older snapshots" {
    with isolated_history() {
        session_id = str(uuid.uuid4());
        for revision in range(52) { saved(session_id, revision); }
        restored = read_history(session_id, HISTORY_CLOCK);
        assert restored["total"] == 52 and len(restored["entries"]) == 50;
        assert restored["entries"][0]["revision"] == 52 and restored["entries"][-1]["revision"] == 3;
        conn = connect_history();
        try { assert conn.execute("SELECT COUNT(*) FROM backup_runs").fetchone()[0] == 52; }
        finally { conn.close(); }
    }
}

test "malformed requests and unsupported storage schemas fail without new snapshots" {
    with isolated_history() {
        session_id = str(uuid.uuid4());
        for revision in [True, -1] {
            caught = False;
            try { saved(session_id, revision); } except ValueError { caught = True; }
            assert caught;
        }
        for bad_id in ["bad", "../../travel", ""] {
            caught = False;
            try { read_history(bad_id, HISTORY_CLOCK); } except ValueError { caught = True; }
            assert caught;
        }
        assert read_history(session_id, HISTORY_CLOCK)["total"] == 0;
        conn = connect_history();
        try { conn.execute("PRAGMA user_version = 2"); } finally { conn.close(); }
        caught = False;
        try { read_history(session_id, HISTORY_CLOCK); } except ValueError { caught = True; }
        assert caught;
    }
}

test "history refuses to use the saved travel database" {
    with isolated_history() {
        os.environ["BACKUP_HISTORY_DB_PATH"] = os.environ["TRAVEL_DB_PATH"];
        caught = False;
        try { read_history(str(uuid.uuid4()), HISTORY_CLOCK); } except ValueError { caught = True; }
        assert caught and not os.path.exists(os.environ["TRAVEL_DB_PATH"]);
    }
}

test "fallback selection and rejected evaluations survive storage without rewriting earlier choices" {
    with isolated_history() {
        session = str(uuid.uuid4()); request_id = str(uuid.uuid4());
        first = saved(session, request_id=request_id, change="price_increase");
        assert first["report"]["selection"]["selected_provider_ids"] == ["science-hall", "covered-market"];
        assert first["report"]["evaluated_options"][0]["cost"]["projected_total_minor"] == 64000;
        recovered = saved(session, 1);
        previous = recovered["history"]["entries"][1];
        assert previous["selection"] == first["report"]["selection"];
        assert previous["recorded_evaluations"][0]["status"] == "invalid";
        assert [o["provider_id"] for o in previous["recorded_options"]] == ["science-hall", "covered-market"];
        assert [o["display_label"] for o in previous["recorded_options"]] == ["Plan B", "Plan C"];
        assert recovered["report"]["selection"]["selected_provider_ids"] == ["indoor-gallery", "science-hall"];
        retry = saved(session, request_id=request_id, change="price_increase");
        assert retry["report"] is None and retry["history"]["revision"] == 2;
    }
}

test "pre selection snapshots remain readable but cannot restore current conclusions" {
    with isolated_history() {
        session = str(uuid.uuid4()); request_id = str(uuid.uuid4()); saved(session, request_id=request_id);
        conn = connect_history();
        try {
            row = conn.execute("SELECT payload FROM backup_runs WHERE session_id=?", (session,)).fetchone();
            snapshot = json.loads(row["payload"]);
            for key in ["selection", "evaluated_options", "evaluated_summary"] { snapshot["report"].pop(key); }
            conn.execute("UPDATE backup_runs SET validator_version='backup-fixture-v1', payload=? WHERE session_id=?", (json.dumps(snapshot), session));
            conn.commit();
        } finally { conn.close(); }
        restored = read_history(session, HISTORY_CLOCK);
        assert restored["entries"][0]["selection"] is None;
        assert len(restored["entries"][0]["recorded_options"]) == 2;
        assert "version_changed" in restored["entries"][0]["reasons"];
        assert saved(session, request_id=request_id)["report"] is None;
    }
}
