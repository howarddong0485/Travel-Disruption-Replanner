"""Detailed synthetic quotes for IDs returned by the Boston search adapter."""
import from dataclasses { replace }
import from datetime { datetime, timedelta }
import from backup.models { BackupCandidate }
import from backup.validation_models { Evidence, Moment, Replacement, RiskContext, ScheduledItem, Transfer, TripContext, Window }

# Search estimates are legacy unqualified estimates. These are separate, explicit
# per-person fixture quotes; only a known party yields a whole-party total.
glob DETAILS = {
    "indoor-gallery": ("plan-b", "Indoor discovery gallery", "11:00", "12:00", 2000),
    "science-hall": ("plan-c", "Covered botanical hall", "11:15", "12:30", 3000),
    "late-bistro": ("plan-b", "Late vegetarian dinner", "19:00", "20:00", 2000),
    "evening-cafe": ("plan-c", "Hotel dining room", "19:30", "20:30", 3000)
};

def materialize(found: BackupCandidate, trip: TripContext, risk: RiskContext,
    now: datetime, scenario: str = "", sample: bool = True) -> Replacement {
    if found.id not in DETAILS { raise ValueError("No detailed fixture for this inventory ID"); }
    target = next(i for i in trip.items if i.id == risk.item_id);
    (label, title, start, end, unit) = DETAILS[found.id];
    day = target.start.local[:10] or trip.start_date;
    def moment(time: str) -> Moment { return Moment(day + "T" + time, "America/New_York"); }
    evidence = Evidence("fixture://boston/details/" + found.id, now.isoformat(),
        (now + timedelta(minutes=15)).isoformat());
    profile = trip.profile;
    party = profile.adults + len(profile.child_ages) if profile.adults is not None and type(profile.adults) is int and
        profile.adults > 0 and all(type(age) is int and 0 <= age <= 17 for age in profile.child_ages) else None;
    rules = {"dietary:vegetarian": True, "pet:dog": True, "accessibility:wheelchair": True, "indoor": True};
    proposal = ScheduledItem(target.id, title, found.category, "fixture:" + found.id,
        moment(start), moment(end), found.currency, unit * party if party is not None else None,
        party, True, evidence, found.availability,
        (Window(moment("00:00"), moment("23:59")),), rules, 0, 17);
    if label == "plan-b" {
        if scenario == "missing_evidence" { proposal = replace(proposal, cost_minor=None, hours=None, eligibility={}); }
        elif scenario == "eligibility_conflict" {
            proposal = replace(proposal, eligibility={**rules, "pet:dog": False, "accessibility:wheelchair": False}, child_min_age=12);
        } elif scenario == "schedule_conflict" {
            proposal = replace(proposal, start=moment("09:45"), end=moment("10:30"));
        } elif scenario == "stale_evidence" {
            proposal = replace(proposal, evidence=replace(evidence,
                checked_at=(now - timedelta(hours=1)).isoformat(), expires_at=now.isoformat()));
        }
    }
    nodes = tuple(proposal if i.id == target.id else i for i in trip.items);
    # Only the isolated sample has evidenced 20-minute fixture routes. Saved
    # itinerary locations never acquire invented transfer estimates.
    edges = tuple(Transfer(a.id, b.id, a.venue, b.venue, 20 if sample else None,
        evidence if sample else None) for (a, b) in zip(nodes, nodes[1:]) if target.id in (a.id, b.id));
    return Replacement(label, target.id, proposal, edges, found.id);
}
