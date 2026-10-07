"""Shared evidence record, time conversion, and serialization helpers.

PROPOSAL (Person 2): not yet agreed by the team. Conventions follow
docs/ARCHITECTURE.md: money is integer minor units with an explicit currency,
local times carry an IANA zone, and missing information is None, never zero.
"""
import re;
import from datetime { datetime, timezone }
import from enum { Enum }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }

enum Origin: str { MOCK = "mock", LIVE = "live", USER = "user" }

"""A source supporting one or more facts: a policy excerpt, a forecast, opening hours."""
obj Evidence {
    has id: str;
    has source_ref: str;
    has excerpt: str;
    has retrieved_at: str;
    has origin: Origin = Origin.MOCK;
}

glob LOCAL_PATTERN: str = r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}";

def valid_zone(tz: str) -> bool {
    if not tz { return False; }
    try { ZoneInfo(tz); return True; }
    except (ZoneInfoNotFoundError, ValueError) { return False; }
}

def valid_local(local: str) -> bool {
    if re.fullmatch(LOCAL_PATTERN, local) is None { return False; }
    try { datetime.fromisoformat(local); return True; }
    except ValueError { return False; }
}

"""Convert a destination-local time to a UTC instant, or None when either part is unknown.

An ambiguous local time (the repeated hour when daylight saving ends) resolves to
its earlier occurrence, which is the stricter reading for a deadline. Results are
UTC so that comparisons and durations are correct across offset changes.
"""
def local_to_instant(local: str, tz: str) -> datetime | None {
    if not local or not tz { return None; }
    return datetime.fromisoformat(local).replace(tzinfo=ZoneInfo(tz)).astimezone(timezone.utc);
}

"""Parse an ISO 8601 instant; an explicit UTC offset is required."""
def parse_instant(text: str) -> datetime {
    value = datetime.fromisoformat(text);
    if value.tzinfo is None { raise ValueError(f"Instant needs a UTC offset: {text}"); }
    return value.astimezone(timezone.utc);
}

def minutes_between(start: datetime, end: datetime) -> int {
    return int((end - start).total_seconds() // 60);
}

def to_local_text(instant: datetime, tz: str) -> str {
    return instant.astimezone(ZoneInfo(tz)).isoformat(timespec="minutes");
}

glob ZERO_DECIMAL_CURRENCIES: list[str] = ["JPY", "KRW"];

"""Parse a written amount such as "260", "260.00" or "1,250.5" into minor units; None if malformed."""
def parse_amount_minor(text: str, currency: str) -> int | None {
    cleaned = text.strip().replace(",", "");
    if re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", cleaned) is None { return None; }
    whole = cleaned.split(".")[0];
    fraction = cleaned.split(".")[1] if "." in cleaned else "";
    if currency in ZERO_DECIMAL_CURRENCIES {
        return int(whole) if fraction.strip("0") == "" else None;
    }
    if len(fraction.rstrip("0")) > 2 { return None; }
    return int(whole) * 100 + int((fraction + "00")[:2]);
}

def format_money(minor: int | None, currency: str) -> str {
    if minor is None { return "unknown amount"; }
    if currency in ZERO_DECIMAL_CURRENCIES { return f"{minor:,} {currency}"; }
    return f"{minor // 100:,}.{minor % 100:02d} {currency}";
}

"""Recursively convert objs, enums, lists and dicts into JSON-ready values."""
def to_plain(value: any) -> any {
    if isinstance(value, Enum) { return value.value; }
    if isinstance(value, list) { return [to_plain(v) for v in value]; }
    if isinstance(value, dict) { return {str(k): to_plain(v) for (k, v) in value.items()}; }
    if hasattr(value, "__dict__") { return {k: to_plain(v) for (k, v) in vars(value).items()}; }
    return value;
}
