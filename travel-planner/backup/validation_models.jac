"""Private-to-module validation inputs; no dependency on other owners' schemas.

Quotes cover the entire party including known taxes/fees. One node represents
one scheduled event; a nonblocking stay can represent an overnight reservation.
"""
import from dataclasses { dataclass, field }
@dataclass(frozen=True)
class Moment {
    with entry {
        local: str;
        zone: str;
        fold: (int | None) = None;
    }
}
@dataclass(frozen=True)
class Evidence {
    with entry {
        source: str;
        checked_at: str;
        expires_at: str;
    }
}
@dataclass(frozen=True)
class Window {
    with entry {
        start: Moment;
        end: Moment;
    }
}
@dataclass(frozen=True)
class Profile {
    with entry {
        adults: (int | None);
        child_ages: tuple[int, ...] = ();
        dietary: tuple[str, ...] = ();
        pet: str = "";
        wheelchair: bool = False;
        complete: bool = True;
        interests: tuple[str, ...] = ();
    }
}
@dataclass(frozen=True)
class ScheduledItem {
    with entry {
        id: str;
        title: str;
        category: str;
        venue: str;
        start: Moment;
        end: Moment;
        currency: str;
        cost_minor: (int | None);
        party_size: (int | None);
        fees_included: (bool | None);
        evidence: (Evidence | None);
        availability: str = "unknown";
        hours: (tuple[Window, ...] | None) = None;
        eligibility: dict[str, bool | None] = field(default_factory=`dict);
        child_min_age: (int | None) = None;
        child_max_age: (int | None) = None;
        paid_minor: (int | None) = 0;
        fixed: bool = False;
        completed: bool = False;
        blocks_time: bool = True;
    }
}
@dataclass(frozen=True)
class Transfer {
    with entry {
        from_id: str;
        to_id: str;
        from_venue: str;
        to_venue: str;
        minutes: (int | None);
        evidence: (Evidence | None);
    }
}
@dataclass(frozen=True)
class Dependency {
    with entry {
        from_id: str;
        to_id: str;
        buffer_minutes: int;
    }
}
@dataclass(frozen=True)
class TripContext {
    with entry {
        id: str;
        currency: str;
        zone: str;
        start_date: str;
        end_date: str;
        budget_minor: (int | None);
        reserve_minor: int;
        profile: Profile;
        items: tuple[ScheduledItem, ...];
        transfers: tuple[Transfer, ...];
        dependencies: tuple[Dependency, ...] = ();
    }
}
@dataclass(frozen=True)
class RiskContext {
    with entry {
        id: str;
        trip_id: str;
        item_id: str;
        trigger: str;
        status: str;
        evidence: (Evidence | None);
        not_before: (Moment | None) = None;
    }
}
@dataclass(frozen=True)
class Replacement {
    with entry {
        id: str;
        replaces_id: str;
        item: ScheduledItem;
        transfers: tuple[Transfer, ...];
        provider_id: str = "";
    }
}
