"""Person 1 draft contract for mandatory filters; not a shared schema.

A filter answers one question for one place: does it meet each of the
traveler's must-haves? Every answer is "pass", "fail" or "unknown", with the
evidence it was based on. Missing or expired evidence is "unknown", never "pass".

Eligibility keys use the same "category:code" form as backup/validation.py,
for example "dietary:vegetarian" or "pet:pet_friendly".
"""

glob FILTER_CONTRACT_VERSION: str = "person1.mandatory-filter.v1";

# "not_applicable" is used only for dietary needs at places that do not serve food.
glob CHECK_STATUSES: list[str] = ["pass", "fail", "unknown", "not_applicable"];

"""What is known about one candidate place, with where and when it was checked."""
obj PlaceFacts {
    has id: str;
    has category: str;                         # for example "food", "activity", "stay"
    has eligibility: dict[str, bool | None];   # True = supported, False = not supported, missing or None = unknown
    has child_min_age: int | None;             # admission limits; None = unknown
    has child_max_age: int | None;
    has source_ref: str;                       # where the facts came from
    has checked_at: str;                       # ISO instant with a UTC offset
    has expires_at: str;                       # ISO instant with a UTC offset
}

"""The answer for one must-have."""
obj RequirementCheck {
    has requirement_id: str;     # the profile requirement id, or "party-child-ages"
    has evidence_key: str;       # the eligibility key that was looked up
    has status: str;             # one of CHECK_STATUSES
    has reason: str;
}

"""All answers for one place. Overall status is the worst of the individual answers."""
obj FilterResult {
    has contract_version: str;
    has profile_id: str;
    has place_id: str;
    has source_ref: str;
    has status: str;             # "pass", "fail" or "unknown"
    has checks: list[RequirementCheck];
}
