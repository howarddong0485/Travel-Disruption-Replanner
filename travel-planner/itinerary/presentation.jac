"""Display helpers for saved dependencies and validated plan metrics."""

def:pub affectedItemIds(snapshot: any, target: str) -> list[str] {
    if snapshot is None or not target { return []; }
    ids = [item["id"] for item in snapshot["items"]];
    pending = [target]; affected: list[str] = [];
    while len(pending) > 0 {
        id = pending.pop(0);
        if id in ids and id not in affected {
            affected.append(id);
            pending = pending + [edge["dependent_id"] for edge in snapshot["dependencies"]
                if edge["prerequisite_id"] == id and edge["dependent_id"] not in affected];
        }
    }
    return affected;
}

def:pub planTitle(plan: any) -> str {
    changes = plan["replacements"];
    replacements = [change for change in changes if change["action"] != "reschedule"];
    if len(changes) == 1 {
        change = changes[0];
        return ("Move " if change["action"] == "reschedule" else "Switch to ") + change["item"]["title"];
    }
    if len(replacements) == 0 { return "Reschedule " + str(len(changes)) + " connected stops"; }
    return "Replace " + str(len(replacements)) + " and adjust connected stops";
}

def:pub shiftLabel(minutes: int) -> str {
    if minutes == 0 { return "Same start time"; }
    return ("+" if minutes > 0 else "−") + str(abs(minutes)) + " min";
}

def:pub moneyLabel(value: any, currency: str) -> str {
    return "Needs confirmation" if value is None else currency + " " + (value / 100).toFixed(2);
}

def:pub differenceLabel(value: any, currency: str) -> str {
    if value is None { return "Cost change needs confirmation"; }
    if value == 0 { return "Same planned total"; }
    return ("+" if value > 0 else "−") + moneyLabel(abs(value), currency);
}
