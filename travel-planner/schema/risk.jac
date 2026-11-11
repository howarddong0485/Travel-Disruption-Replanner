"""Risk flags produced by the RiskAnalyzer.

PROPOSAL (Person 2). A FLAGGED risk was detected from evidence; an UNRESOLVED one
could not be evaluated because evidence is missing, and is never reported as safe.
"""

enum RiskCategory: str {
    TIMING = "timing",
    WEATHER = "weather",
    LONG_DRIVE = "long_drive",
    OPENING_HOURS = "opening_hours",
    BOOKING_TERMS = "booking_terms"
}

enum Severity: str { LOW = "low", MEDIUM = "medium", HIGH = "high" }

enum FlagStatus: str { FLAGGED = "flagged", UNRESOLVED = "unresolved" }

obj RiskFlag {
    has id: str;
    has rule_id: str;
    has category: RiskCategory;
    has severity: Severity;
    has status: FlagStatus;
    has node_ids: list[str];
    has summary: str;
    has mitigation: str;
    has evaluated_at: str;
    has evidence_ids: list[str] = [];
    has probability_pct: int | None = None;
}

glob SEVERITY_RANK: dict[str, int] = {"high": 0, "medium": 1, "low": 2};
