"""Normalized, explicitly simulated events. No provider monitoring or bookings."""
from datetime import datetime, timezone
from uuid import uuid4


def simulated_event(trip_id, item_id, kind, delay_minutes=0, event_id=""):
    if kind not in {"delayed", "interrupted"}:
        raise ValueError("Choose delayed or interrupted")
    if not isinstance(delay_minutes, int) or isinstance(delay_minutes, bool):
        raise ValueError("Delay must be an integer number of minutes")
    if kind == "delayed" and not 1 <= delay_minutes <= 1440:
        raise ValueError("Delay must be between 1 and 1440 minutes")
    return {"id": event_id or str(uuid4()), "trip_id": trip_id,
            "item_id": item_id, "type": kind,
            "delay_minutes": delay_minutes if kind == "delayed" else 0,
            "source": "simulator", "observed_at": datetime.now(timezone.utc).isoformat()}
