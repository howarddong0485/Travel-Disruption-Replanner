"""Run with jac run backup/demo.jac. No database or service required."""
import datetime;
import json;
import from jaclang.data.serializer { Serializer }
import from backup.fixtures { demo_trip, demo_items }
import from backup.planner { prepare }

with entry:__main__ {
    clock = datetime.datetime.fromisoformat("2026-10-06T12:00:00+00:00");
    for (item_id, trigger) in [("outdoor-walk", "rain"), ("dinner", "arrival_delay")] {
        print(json.dumps(Serializer.serialize(prepare(demo_trip(), demo_items(), item_id, trigger, clock), api_mode=True), indent=2));
    }
}
