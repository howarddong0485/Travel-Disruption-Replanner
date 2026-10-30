"""Candidate identity and stage transitions through the unified backup workflow."""
import uuid;
import os;
import tempfile;
import from contextlib { contextmanager }
import from datetime { datetime, timezone }
import from dataclasses { replace }
import from unittest.mock { patch }
import from backup.workflow { discover, run_workflow }
import from backup.validation_fixtures { build_fixture, run_fixture }
import from backup.history { save_refresh, read_history }
import from tools.alternatives.mock { search }

@contextmanager
def isolated_workflow_history -> any {
    names = ["BACKUP_HISTORY_DB_PATH", "TRAVEL_DB_PATH"];
    previous = {name: os.environ.get(name) for name in names};
    with tempfile.TemporaryDirectory() as directory {
        os.environ[names[0]] = os.path.join(directory, "backups.sqlite3");
        os.environ[names[1]] = os.path.join(directory, "travel.sqlite3");
        try { yield; }
        finally {
            for name in names {
                if previous[name] is None { os.environ.pop(name, None); }
                else { os.environ[name] = previous[name]; }
            }
        }
    }
}

glob WORKFLOW_CLOCK = datetime(2026, 11, 10, 12, tzinfo=timezone.utc);

test "searched IDs survive initial checks refresh snapshots and recorded history" {
    with isolated_workflow_history() {
        session = str(uuid.uuid4());
        for (revision, scenario, expected) in [(0, "rain", ["indoor-gallery", "science-hall"]),
            (1, "arrival_delay", ["late-bistro", "evening-cafe"])] {
            saved = save_refresh(session, str(uuid.uuid4()), revision, scenario=scenario,
                sample_date="2026-11-17", now=WORKFLOW_CLOCK);
            r = saved["report"];
            assert r["pipeline"]["selected_provider_ids"] == expected;
            assert [i["provider_id"] for i in r["pipeline"]["initial_checks"]] == r["pipeline"]["provider_ids"];
            assert [i["provider_id"] for i in r["results"]] == expected;
            assert [i["provider_id"] for i in r["input_snapshot"]["candidates"]] == r["pipeline"]["provider_ids"];
            assert all(i["source"].endswith(i["provider_id"]) for i in r["results"]);
            latest = read_history(session, WORKFLOW_CLOCK)["entries"][0];
            assert latest["pipeline"] == r["pipeline"];
            assert [i["provider_id"] for i in latest["recorded_options"]] == expected;
        }
    }
}

test "refresh rejection supersedes the initial passing checks for the same candidate" {
    r = run_fixture(now=WORKFLOW_CLOCK, inventory_change="price_increase");
    assert r["pipeline"]["initial_checks"][0]["status"] == "passed_fixture_checks";
    assert r["results"][0]["status"] == "invalid";
    assert r["results"][0]["provider_id"] == "indoor-gallery";
    assert r["pipeline"]["searched_count"] == 4 and r["pipeline"]["selected_count"] == 2;
    assert {e["provider_id"] for e in r["pipeline"]["exclusions"]} == {"sold-out-exhibit", "unconfirmed-tour"};
}

test "unsupported locations and currencies produce honest empty workflow results" {
    (trip, risk, _) = build_fixture("rain", "family", WORKFLOW_CLOCK);
    r = run_workflow(trip, risk, "Kyoto", "unchanged", WORKFLOW_CLOCK);
    assert r["results"] == [] and r["pipeline"]["searched_count"] == 0;
    r = run_workflow(replace(trip, currency="EUR"), risk, "Boston", "unchanged", WORKFLOW_CLOCK);
    assert r["results"] == [] and len(r["pipeline"]["exclusions"]) == 6;
}

test "duplicate search IDs and unsupported details never create invented candidates" {
    (trip, risk, _) = build_fixture("rain", "family", WORKFLOW_CLOCK);
    found = search("Boston", "activity", WORKFLOW_CLOCK);
    with patch("backup.workflow.search", return_value=[found[0], found[0], found[1]]) {
        (candidates, trace) = discover(trip, risk, "Boston", WORKFLOW_CLOCK);
        assert len(candidates) == 2 and len(trace["exclusions"]) == 1;
        assert trace["exclusions"][0]["reason"] == "Duplicate inventory ID";
    }
    found[0].id = "unsupported-detail";
    with patch("backup.workflow.search", return_value=[found[0]]) {
        (candidates, trace) = discover(trip, risk, "Boston", WORKFLOW_CLOCK);
        assert candidates == () and "No detailed fixture" in trace["exclusions"][0]["reason"];
    }
}

test "disappearing provider IDs invalidate evidence without substituting another candidate" {
    (trip, risk, _) = build_fixture("rain", "family", WORKFLOW_CLOCK);
    with patch("backup.refresh.refresh_inventory", return_value=None) {
        r = run_workflow(trip, risk, "Boston", "unchanged", WORKFLOW_CLOCK);
        assert r["evaluated_summary"]["needs_validation"] == 4 and r["results"] == [];
        assert [i["provider_id"] for i in r["evaluated_options"]][:2] == ["indoor-gallery", "science-hall"];
        assert all(i["source"] == "" and i["cost"]["projected_total_minor"] is None for i in r["evaluated_options"]);
    }
}

test "a risk for another trip or wrong target category cannot enter the workflow" {
    (trip, risk, _) = build_fixture("rain", "family", WORKFLOW_CLOCK);
    for changed in [replace(risk, trip_id="other"), replace(risk, item_id="missing"), replace(risk, trigger="arrival_delay")] {
        rejected = False;
        try { run_workflow(trip, changed, "Boston", "unchanged", WORKFLOW_CLOCK); }
        except ValueError { rejected = True; }
        assert rejected;
    }
}
