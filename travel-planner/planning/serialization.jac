"""Lossless JSON round trips for stored alternative plans."""
import from backup.validation_models { ScheduledItem, Replacement, RiskContext, Transfer, Window }
import from planning.context { parse_moment, parse_evidence }

def item_from_data(data: dict[str, any]) -> ScheduledItem {
    return ScheduledItem(**{**data, "start": parse_moment(data["start"]), "end": parse_moment(data["end"]),
        "evidence": parse_evidence(data["evidence"]),
        "hours": tuple(Window(parse_moment(w["start"]), parse_moment(w["end"])) for w in data["hours"]) if data["hours"] is not None else None});
}

def replacement_from_data(data: dict[str, any]) -> Replacement {
    return Replacement(**{**data, "item": item_from_data(data["item"]),
        "transfers": tuple(Transfer(**{**route, "evidence": parse_evidence(route["evidence"])}) for route in data["transfers"])});
}

def risk_from_data(data: dict[str, any]) -> RiskContext {
    return RiskContext(**{**data, "evidence": parse_evidence(data["evidence"]),
        "not_before": parse_moment(data["not_before"]) if data["not_before"] is not None else None});
}
