"""Travel endpoint tests use isolated temporary databases, never saved trip data."""
import os;
import tempfile;
import sqlite3;
import from jaclang.testing.testing { JacTestClient }

glob SERVER: str = os.path.join(os.path.dirname(__file__), "main.jac");

test "trip lifecycle, editing, exact currency amounts, state and cascade deletion" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
        try {
            trip = client.post("/function/save_trip", json={"title": "Kyoto week", "destination": "Kyoto, Japan", "start_date": "2026-11-01", "end_date": "2026-11-07", "budget": "2500.10"}).data["result"];
            assert trip["budget_cents"] == 250010;
            booking = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Hotel", "category": "stay", "date": "2026-11-01", "reference": "ABC123", "cost": "900.99"}).data["result"];
            assert booking["cost_cents"] == 90099;
            updated = client.post("/function/set_item_state", json={"trip_id": trip["id"], "item_id": booking["id"], "done": True, "paid": True}).data["result"];
            assert updated["done"] and updated["paid"];
            edited = client.post("/function/save_item", json={"trip_id": trip["id"], "item_id": booking["id"], "title": "Hotel, updated", "category": "stay", "date": "2026-11-02", "cost": "950.50"}).data["result"];
            assert edited["id"] == booking["id"] and edited["cost_cents"] == 95050;
            assert edited["done"] and edited["paid"];
            cleared = client.post("/function/save_item", json={"trip_id": trip["id"], "item_id": booking["id"], "title": "Hotel, free", "category": "stay", "cost": "0"}).data["result"];
            assert cleared["paid"] is False;
            packed = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Passport", "category": "packing"}).data["result"];
            assert packed["cost_cents"] == 0;
            assert client.post("/function/delete_item", json={"trip_id": trip["id"], "item_id": packed["id"]}).data["result"] is True;
            assert client.post("/function/delete_item", json={"trip_id": trip["id"], "item_id": packed["id"]}).data["result"] is False;
            assert client.post("/function/delete_trip", json={"trip_id": trip["id"]}).data["result"] is True;
            assert client.post("/function/list_trips", json={}).data["result"] == [];
            conn = sqlite3.connect(os.environ["TRAVEL_DB_PATH"]);
            try { assert conn.execute("SELECT count(*) FROM items").fetchone()[0] == 0; }
            finally { conn.close(); }
        } finally { client.close(); }
    }
}

test "validation rejects invalid dates amounts trip bounds and foreign item IDs" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "store"));
        try {
            base = {"title": "Autumn trip", "destination": "Boston", "start_date": "2026-10-10", "end_date": "2026-10-15"};
            for invalid in [
                {"title": " "}, {"start_date": "2026-02-30"}, {"end_date": "2026-10-01"},
                {"budget": "-1"}, {"budget": "1.234"}, {"budget": "NaN"}, {"currency": "XYZ"}
            ] {
                body = base.copy(); body.update(invalid);
                response = client.post("/function/save_trip", json=body);
                assert not response.ok, str(body);
            }
            trip = client.post("/function/save_trip", json=base).data["result"];
            second = client.post("/function/save_trip", json=base).data["result"];
            for invalid_item in [
                {"date": "2026-10-16"}, {"date": "2026-10-09"}, {"time": "09:00"},
                {"date": "2026-10-10", "time": "24:00"}, {"cost": "-1"},
                {"category": "packing", "cost": "10"}, {"category": "packing", "date": "2026-10-10"},
                {"category": "unknown"}, {"title": " "}, {"trip_id": "missing"}
            ] {
                body = {"trip_id": trip["id"], "title": "An item"}; body.update(invalid_item);
                assert not client.post("/function/save_item", json=body).ok, str(body);
            }
            item = client.post("/function/save_item", json={"trip_id": trip["id"], "title": "Museum", "date": "2026-10-14", "cost": "0.10"}).data["result"];
            assert not client.post("/function/set_item_state", json={"trip_id": second["id"], "item_id": item["id"], "done": True, "paid": True}).ok;
            assert not client.post("/function/save_item", json={"trip_id": second["id"], "item_id": item["id"], "title": "Moved"}).ok;
            edit_trip = base.copy(); edit_trip.update({"trip_id": trip["id"], "end_date": "2026-10-12"});
            assert not client.post("/function/save_trip", json=edit_trip).ok;
            edit_trip["end_date"] = "2026-10-15"; edit_trip["currency"] = "EUR";
            assert not client.post("/function/save_trip", json=edit_trip).ok;
            assert client.post("/function/delete_item", json={"trip_id": second["id"], "item_id": item["id"]}).data["result"] is False;
            assert len(client.post("/function/list_items", json={"trip_id": trip["id"]}).data["result"]) == 1;
        } finally { client.close(); }
    }
}

test "independent server sessions preserve data and itinerary ordering" {
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        first = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "first"));
        try {
            trip = first.post("/function/save_trip", json={"title": "Weekend", "destination": "Chicago", "start_date": "2026-12-01", "end_date": "2026-12-03", "notes": "Remember the train tickets"}).data["result"];
            for (title, date, time) in [("Undated idea", "", ""), ("Flexible", "2026-12-02", ""), ("Morning", "2026-12-02", "09:00"), ("Earlier", "2026-12-01", "18:00")] {
                first.post("/function/save_item", json={"trip_id": trip["id"], "title": title, "date": date, "time": time});
            }
        } finally { first.close(); }
        second = JacTestClient.from_file(SERVER, base_path=os.path.join(directory, "second"));
        try {
            assert second.post("/function/list_trips", json={}).data["result"][0]["notes"] == "Remember the train tickets";
            items = second.post("/function/list_items", json={"trip_id": trip["id"]}).data["result"];
            assert [item["title"] for item in items] == ["Earlier", "Morning", "Flexible", "Undated idea"];
        } finally { second.close(); }
    }
}
