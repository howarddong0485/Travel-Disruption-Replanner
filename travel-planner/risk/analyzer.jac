"""RiskAnalyzer: runs every rule over a trip and returns flags, most severe first."""
import from schema.common { parse_instant }
import from schema.bundle { TripBundle }
import from schema.risk { RiskFlag, SEVERITY_RANK }
import from risk.config { RiskConfig }
import from risk.rules {
    check_connections, check_weather, check_long_drives, check_opening_hours, check_booking_terms
}

"""Analyze a trip as of `now`, an ISO 8601 instant with a UTC offset."""
def analyze_trip(bundle: TripBundle, now: str, config: RiskConfig | None = None) -> list[RiskFlag] {
    cfg = config or RiskConfig();
    at = parse_instant(now);
    flags = (check_connections(bundle, cfg, at) + check_weather(bundle, cfg, at)
        + check_long_drives(bundle, cfg, at) + check_opening_hours(bundle, cfg, at)
        + check_booking_terms(bundle, cfg, at));
    return sorted(flags, key=lambda (f: RiskFlag) -> tuple[int, str] {
        return (SEVERITY_RANK[f.severity.value], f.id);
    });
}
