"""Launch-guide failure scenarios, run through the HTTP service on a throwaway database.

The traveler keeps the original trip whenever validation fails or a proposal is
rejected. Covered here: a storm, a fee-bearing cancellation and an itinerary
edited while a plan is waiting. A tight transfer and an unknown fare are covered
in planning/test_service.jac and planning/test_engine.jac (see POLICY_AND_RISK.md).
"""
import os;
import tempfile;
import from contextlib { contextmanager }
import from jaclang.testing.testing { JacTestClient }

glob FEE_TERMS = ("Free cancellation up to 400 hours before entry. "
    + "After that time, a $5.00 fee is charged and the remainder is refunded.");

@contextmanager
def scenario_client -> any {
    old = os.environ.get("TRAVEL_DB_PATH");
    with tempfile.TemporaryDirectory() as directory {
        os.environ["TRAVEL_DB_PATH"] = os.path.join(directory, "travel.sqlite3");
        client = JacTestClient.from_file(os.path.join(os.path.dirname(__file__), "..", "server", "main.jac"), base_path=os.path.join(directory, "runtime"));
        try { yield client; }
        finally {
            client.close();
            if old is None { os.environ.pop("TRAVEL_DB_PATH", None); } else { os.environ["TRAVEL_DB_PATH"] = old; }
        }
    }
}

def call(client: any, name: str, **data: any) -> any {
    response = client.post("/function/" + name, json=data);
    assert response.ok, str(response.data);
    return response.data["result"];
}

def rejected(client: any, name: str, **data: any) -> bool {
    response = client.post("/function/" + name, json=data);
    return not response.ok or not response.data.get("ok", True);
}

"""What the traveler sees as their itinerary, without bookkeeping fields."""
def itinerary(client: any, trip_id: str) -> list[tuple[str, str, str, str, int, bool, bool]] {
    return sorted((i["title"], i["category"], i["date"], i["time"], i["cost_cents"], i["done"], i["paid"])
        for i in call(client, "list_items", trip_id=trip_id));
}

def plans_for(client: any, state: dict[str, any]) -> list[dict[str, any]] {
    risks = [risk["id"] for risk in state["risks"] if risk["status"] == "flagged"];
    assert risks, str(state["risks"]);
    return call(client, "generate_backup_plans", trip_id=state["trip_id"], expected_version=state["trip_version"],
        max_plans=4, risk_ids=risks)["plans"];
}

test "storm: alternatives show the booking's terms and rejecting keeps the original trip" {
    with scenario_client() as client {
        demo = call(client, "create_planning_demo", scenario="rain");
        before = itinerary(client, demo["trip_id"]);
        plans = plans_for(client, call(client, "planning_state", trip_id=demo["trip_id"]));
        assert plans and all(p["selectable"] for p in plans);
        for plan in plans {
            terms = [t for t in plan["comparison"]["cancellation"] if t["title"] == "Outdoor garden visit"];
            assert terms and terms[0]["excerpts"], str(plan["comparison"]["cancellation"]);
        }
        call(client, "review_backup_plan", trip_id=demo["trip_id"], proposal_id=plans[0]["id"], accept=False);
        assert itinerary(client, demo["trip_id"]) == before;
    }
}

test "fee-bearing cancellation: the fee reaches the alternative and no refund is assumed" {
    with scenario_client() as client {
        demo = call(client, "create_planning_demo", scenario="rain");
        garden = next(i for i in call(client, "list_items", trip_id=demo["trip_id"]) if i["title"] == "Outdoor garden visit");
        call(client, "set_item_state", trip_id=demo["trip_id"], item_id=garden["id"], done=False, paid=True);
        state = call(client, "planning_state", trip_id=demo["trip_id"]);
        saved = call(client, "save_cancellation_terms", trip_id=demo["trip_id"], item_id=garden["id"],
            terms=FEE_TERMS, expected_version=state["trip_version"]);
        terms = saved["cancellation"][garden["id"]];
        assert terms["state"] == "fee" and terms["fee_minor"] == 500 and terms["refund_minor"] == terms["paid_minor"] - 500;
        plans = plans_for(client, call(client, "planning_state", trip_id=demo["trip_id"]));
        shown = [t for p in plans for t in p["comparison"]["cancellation"] if t["item_id"] == garden["id"]];
        assert shown and all(t["state"] == "fee" and t["fee_minor"] == 500 for t in shown);
        assert all(p["comparison"]["confirmed_refund_minor"] == 0 for p in plans);
    }
}

test "itinerary edited while a plan waits: the old plan is refused and the edit is kept" {
    with scenario_client() as client {
        demo = call(client, "create_planning_demo", scenario="rain");
        plans = plans_for(client, call(client, "planning_state", trip_id=demo["trip_id"]));
        dinner = next(i for i in call(client, "list_items", trip_id=demo["trip_id"]) if i["category"] == "food");
        call(client, "save_item", trip_id=demo["trip_id"], item_id=dinner["id"], title=dinner["title"], category="food",
            date=dinner["date"], time="19:30", location=dinner["location"], cost=str(dinner["cost_cents"] / 100));
        edited = itinerary(client, demo["trip_id"]);
        assert rejected(client, "review_backup_plan", trip_id=demo["trip_id"], proposal_id=plans[0]["id"], accept=True);
        assert itinerary(client, demo["trip_id"]) == edited;
    }
}
