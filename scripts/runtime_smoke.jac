"""HTTP/CLI regression for a separately started, disposable localhost server."""
import os;
import re;
import json;
import time;
import uuid;
import subprocess;
import from datetime { date, timedelta }
import from pathlib { Path }
import from urllib.parse { urlparse, urljoin }
import from urllib.request { Request, urlopen }
import from urllib.error { URLError }

def fetch(base: str, path: str, payload: any = None) -> tuple[str, str] {
    data = json.dumps(payload).encode() if payload is not None else None;
    request = Request(urljoin(base + "/", path), data=data,
        headers={"Content-Type": "application/json"} if data is not None else {});
    with urlopen(request, timeout=10) as response {
        assert response.status == 200, str(response.status);
        return (response.read().decode(), response.headers.get("Content-Type", ""));
    }
}

def call(base: str, name: str, payload: dict[str, any]) -> any {
    (body, _) = fetch(base, "/api/server/function/" + name, payload);
    envelope = json.loads(body);
    assert envelope["ok"], body;
    return envelope["data"]["result"];
}

def persisted_items(base: str, trip_id: str) -> list[dict[str, any]] {
    # _jac_id identifies each serialized wire object, not the stored itinerary
    # item. Compare every other field, including the authoritative item id.
    return [{key: value for (key, value) in item.items() if key != "_jac_id"}
        for item in call(base, "list_items", {"trip_id": trip_id})];
}

def generate(base: str, state: dict[str, any], limit: int) -> dict[str, any] {
    return call(base, "generate_backup_plans", {"trip_id": state["trip_id"],
        "expected_version": state["trip_version"], "max_plans": limit,
        "risk_ids": [risk["id"] for risk in state["risks"] if risk["status"] == "flagged"],
        "use_llm": False, "request_id": str(uuid.uuid4())});
}

def cli(jac: str, project: Path, base: str, args: list[str]) -> str {
    env = dict(os.environ); env["JAC_APP_SERVER_URL"] = base + "/api/server";
    result = subprocess.run([jac, "run", "cli", "--"] + args, cwd=project,
        env=env, text=True, capture_output=True, timeout=90);
    assert result.returncode == 0, result.stdout + result.stderr;
    return result.stdout;
}

with entry {
    base = os.environ["ROAM_SMOKE_URL"].rstrip("/");
    assert urlparse(base).hostname in ("127.0.0.1", "localhost"), "Use a disposable localhost server";
    deadline = time.monotonic() + 120;
    while True {
        if os.environ.get("ROAM_SMOKE_PID") { os.kill(int(os.environ["ROAM_SMOKE_PID"]), 0); }
        try { fetch(base, "/healthz/ready"); break; }
        except (URLError, TimeoutError, ConnectionError) {
            if time.monotonic() >= deadline { raise RuntimeError("Server readiness timed out"); }
            time.sleep(0.25);
        }
    }
    (html, content_type) = fetch(base, "/");
    assert "text/html" in content_type and 'id="root"' in html;
    (info, _) = fetch(base, "/function/application_info", {});
    assert json.loads(info)["data"]["result"] == {"application": "roam", "inventory": "synthetic", "external_actions": "disabled"};
    scripts = re.findall(r'<script[^>]+src="([^"]+)"', html);
    styles = re.findall(r'<link[^>]+href="([^"]+\.css[^\"]*)"', html);
    assert scripts and styles, "Root page must reference its built client and styles";
    for asset in scripts + styles {
        assert urlparse(urljoin(base, asset)).netloc == urlparse(base).netloc;
        (body, kind) = fetch(base, asset);
        assert body and "text/html" not in kind, asset;
    }
    assert call(base, "list_trips", {}) == [], "Smoke server must use a new isolated store";

    state = call(base, "create_planning_demo", {"scenario": "rain"});
    trip_id = state["trip_id"];
    before = persisted_items(base, trip_id);
    plans = generate(base, state, 5)["plans"];
    assert len(plans) == 3 and all(plan["selectable"] for plan in plans);
    assert all(plan["comparison"]["original_planned_minor"] == 41000 for plan in plans);
    assert all(plan["comparison"]["cash_needed_now_minor"] is None for plan in plans);
    call(base, "review_backup_plan", {"trip_id": trip_id, "proposal_id": plans[0]["id"], "accept": False});
    assert persisted_items(base, trip_id) == before;
    chosen = plans[1];
    call(base, "review_backup_plan", {"trip_id": trip_id, "proposal_id": chosen["id"], "accept": True});
    after = persisted_items(base, trip_id);
    assert after != before;
    by_id = {item["id"]: item for item in after};
    for change in chosen["replacements"] {
        saved = by_id[change["replaces_id"]]; proposed = change["item"];
        assert saved["title"] == proposed["title"];
        assert saved["date"] + "T" + saved["time"] == proposed["start"]["local"];
        assert saved["cost_cents"] == proposed["cost_minor"];
    }
    fresh = call(base, "planning_state", {"trip_id": trip_id});
    assert fresh["trip_version"] > state["trip_version"];
    assert sum(item["cost_cents"] for item in after) + fresh["facts"]["reserve_minor"] == chosen["comparison"]["projected_total_minor"];
    arrival = call(base, "create_planning_demo", {"scenario": "arrival_delay"});
    arrival_plans = generate(base, arrival, 5)["plans"];
    assert len(arrival_plans) == 5 and all(plan["selectable"] for plan in arrival_plans);

    jac = os.environ["ROAM_SMOKE_JAC"];
    project = Path(__file__).resolve().parent.parent / "travel-planner";
    day = (date.today() + timedelta(days=7)).isoformat();
    title = "CLI smoke " + str(uuid.uuid4())[:8];
    assert "Created" in cli(jac, project, base, ["new", title, "Boston", "--start", day, "--end", day, "--budget", "100"]);
    trip = next(t for t in call(base, "list_trips", {}) if t["title"] == title);
    cli(jac, project, base, ["add", trip["id"], "CLI activity", "--date", day, "--time", "12:00", "--cost", "12.34"]);
    items = call(base, "list_items", {"trip_id": trip["id"]});
    assert len(items) == 1 and items[0]["cost_cents"] == 1234 and items[0]["time"] == "12:00";
    shown = cli(jac, project, base, ["show", trip["id"]]);
    assert "CLI activity" in shown and "USD 12.34" in shown;
    print(json.dumps({"root_and_assets": "passed", "cli_new_add_show": "passed",
        "rejection_preserves_items": "passed", "acceptance_matches_candidate": "passed",
        "weather_plans": len(plans), "arrival_plans": len(arrival_plans)}, sort_keys=True));
}
