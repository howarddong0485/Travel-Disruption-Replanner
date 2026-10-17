"""Exercise the fixture demo through its Jac boundary without touching a user DB."""
import os;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

test "validation fixtures serialize and never create a trip database" {
    previous = os.environ.get("TRAVEL_DB_PATH");
    with tempfile.TemporaryDirectory() as directory {
        database = os.path.join(directory, "must-not-exist.sqlite3");
        os.environ["TRAVEL_DB_PATH"] = database;
        client = JacTestClient.from_file(os.path.join(os.path.dirname(__file__), "main.jac"), base_path=os.path.join(directory, "store"));
        try {
            for (scenario, expected) in [("rain", "passed_fixture_checks"), ("arrival_delay", "passed_fixture_checks"),
                ("missing_evidence", "needs_validation"), ("schedule_conflict", "invalid"), ("fixed_item", "invalid"),
                ("eligibility_conflict", "invalid"), ("stale_evidence", "needs_validation")] {
                response = client.post("/function/preview_backup_validation", json={"scenario": scenario});
                assert response.ok, str(response.data);
                result = response.data["result"];
                assert len(result["results"]) == 2;
                assert result["results"][0]["status"] == expected;
                assert result["results"][0]["scope"] == "standalone_fixture";
                assert not os.path.exists(database);
            }
            for payload in [{"scenario": "unknown"}, {"profile_name": "unknown"}, {"budget": "-1"}, {"budget": "NaN"}] {
                assert not client.post("/function/preview_backup_validation", json=payload).ok;
            }
            unknown = client.post("/function/preview_backup_validation", json={"budget": ""}).data["result"];
            assert unknown["summary"]["needs_validation"] == 2;
            limited = client.post("/function/preview_backup_validation", json={"budget": "400"}).data["result"];
            assert limited["summary"]["invalid"] == 2;
            assert not os.path.exists(database);
        } finally {
            client.close();
            if previous is None { os.environ.pop("TRAVEL_DB_PATH", None); }
            else { os.environ["TRAVEL_DB_PATH"] = previous; }
        }
    }
}
