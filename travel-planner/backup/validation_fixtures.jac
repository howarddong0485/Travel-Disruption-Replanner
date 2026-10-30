"""Synthetic, module-owned facts. These are not provider or teammate contracts."""
import from dataclasses { replace }
import from datetime { date, datetime, timedelta, timezone }
import from backup.workflow { discover, run_workflow }
import from decimal { Decimal }
import re;
import from backup.validation { validate_replacement }
import from backup.validation_models {
    Dependency,
    Evidence,
    Moment,
    Profile,
    Replacement,
    RiskContext,
    ScheduledItem,
    Transfer,
    TripContext,
    Window
}
glob SCENARIOS = ("rain", "arrival_delay", "missing_evidence", "eligibility_conflict",
    "schedule_conflict", "fixed_item", "stale_evidence");
glob PROFILES = ("family", "solo");

def build_fixture(scenario: str, profile_name: str, now: datetime, sample_date: str = "", include_candidates: bool = True) -> tuple[TripContext, RiskContext, tuple[Replacement, ...]] {
    if (scenario not in SCENARIOS) {
        raise ValueError("Choose a supported fixture scenario");
    }
    if (profile_name not in PROFILES) {
        raise ValueError("Choose family or solo");
    }
    if (now.utcoffset() is None) {
        raise ValueError("Fixture clock needs a UTC offset");
    }
    day = (now.astimezone(timezone.utc).date() + timedelta(days=7)).isoformat();
    if sample_date {
        if len(sample_date) != 10 or date.fromisoformat(sample_date).isoformat() != sample_date {
            raise ValueError("Use a valid sample date in YYYY-MM-DD format");
        }
        day = sample_date;
    }
    def moment(time: str) -> Moment {
        return Moment((day + "T" + time), "America/New_York");
    }
    fresh = Evidence(
        "fixture://boston/synthetic-v2",
        now.isoformat(),
        (now + timedelta(minutes=15)).isoformat()
    );
    profile = Profile(2, (8, ), ("vegetarian", ), "dog", True)
        if (profile_name == "family")
        else Profile(1);
    party_size = profile.adults + len(profile.child_ages);
    rules = {
        "dietary:vegetarian": True,
        "pet:dog": True,
        "accessibility:wheelchair": True,
        "indoor": True
    };
    def item(
        id: any,
        title: any,
        category: any,
        start: any,
        end: any,
        cost: any,
        **kwargs: any
    ) -> ScheduledItem {
        return ScheduledItem(
            id,
            title,
            category,
            ("fixture:" + id),
            moment(start),
            moment(end),
            "USD",
            (cost * party_size),
            party_size,
            True,
            fresh,
            "available",
            (Window(moment("00:00"), moment("23:59")), ),
            `dict(rules),
            0,
            17,
            **kwargs
        );
    }
    def transfer(left: ScheduledItem, right: ScheduledItem, minutes: int = 20) -> Transfer {
        return Transfer(left.id, right.id, left.venue, right.venue, minutes, fresh);
    }
    arrival = item(
        "arrival", "Arrival transfer", "transport", "09:00", "10:00", 2000, fixed=True
    );
    activity = item(
        "activity",
        "Outdoor garden visit",
        "activity",
        "11:00",
        "12:00",
        1500,
        paid_minor=1500
    );
    dinner = item("dinner", "Original dinner", "food", "18:00", "19:00", 2500);
    hotel = item(
        "hotel", "Evening hotel check-in", "stay", "21:00", "21:30", 6000, fixed=True
    );
    delay = scenario == "arrival_delay";
    if delay {
        arrival = replace(arrival, start=moment("16:30"), end=moment("18:15"));
        activity = replace(activity, completed=True);
    }
    target = dinner if delay else activity;
    if (scenario == "fixed_item") {
        target = replace(target, fixed=True);
        activity = target;
    }
    ordered = (activity, arrival, dinner, hotel)
        if delay
        else (arrival, activity, dinner, hotel);
    transfers = `tuple(transfer(a, b) for (a, b) in zip(ordered, ordered[1:]));
    trip = TripContext(
        "fixture-boston",
        "USD",
        "America/New_York",
        day,
        day,
        60000,
        5000,
        profile,
        ordered,
        transfers,
        (Dependency("dinner", "hotel", 30), )
    );
    risk = RiskContext(
        "fixture-risk",
        trip.id,
        target.id,
        "arrival_delay" if delay else "rain",
        "flagged",
        fresh,
        moment("18:45") if delay else None
    );
    candidates = discover(trip, risk, "Boston", now, scenario)[0] if include_candidates else ();
    return (trip, risk, `tuple(candidates));
}
def run_fixture(
    scenario: str = "rain",
    profile_name: str = "family",
    budget: str = "600",
    now: (datetime | None) = None,
    inventory_change: str = "", sample_date: str = "", expanded: bool = False
) -> dict[str, any] {
    now = now or datetime.now(timezone.utc);
    (trip, risk, candidates) = build_fixture(scenario, profile_name, now, sample_date, not bool(inventory_change));
    if (not isinstance(budget, str) or (len(budget) > 24)) {
        raise ValueError("Budget must be a USD decimal string");
    }
    budget = budget.strip();
    amount: int | None = None;
    if budget {
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]{1,2})?", budget) {
            raise ValueError(
                "Budget must be nonnegative with at most two decimal places"
            );
        }
        amount = int((Decimal(budget) * 100));
        if (amount > 10000000000) {
            raise ValueError("Budget cannot exceed 100,000,000 USD");
        }
    } else {
        amount = None;
    }
    trip = replace(trip, budget_minor=amount);
    refreshed: dict[str, any] | None = None;
    if inventory_change { refreshed = run_workflow(trip, risk, "Boston", inventory_change, now, scenario, expanded=expanded); }
    results = refreshed["results"] if refreshed else [
        validate_replacement(trip, risk, candidate, now) for candidate in candidates
    ];
    response = {
        "scenario": scenario,
        "profile": profile_name,
        "trip_date": trip.start_date,
        "expires_at": (now + timedelta(minutes=15)).isoformat(),
        "profile_summary": "2 adults, child age 8, vegetarian meals, dog, wheelchair access"
            if (profile_name == "family")
            else "1 adult, no additional hard requirements",
        "results": results,
        "summary": {
            status: sum((r["status"] == status) for r in results)
            for status in ("passed_fixture_checks", "invalid", "needs_validation")
        }
    };
    if refreshed { response.update(refreshed); }
    return response;
}
