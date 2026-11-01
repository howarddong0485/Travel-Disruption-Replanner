"""Mandatory filter: check one place against a traveler's must-haves.

Pure function: the profile and place are read, never changed. Soft
preferences are ignored here; they never override a must-have.
"""
import datetime;
import from profile.models { TravelerProfile, ProfileRequirement }
import from profile.checks { hard_requirements, require_valid_profile }
import from filter.models { PlaceFacts, RequirementCheck, FilterResult, FILTER_CONTRACT_VERSION }

glob CHILD_AGES_CHECK_ID: str = "party-child-ages";

"""Return "" when the place's evidence is usable at `now`, otherwise the reason it is not."""
def evidence_problem(place: PlaceFacts, now: datetime.datetime) -> str {
    if not place.source_ref.strip() {
        return "Evidence has no source";
    }
    try {
        checked = datetime.datetime.fromisoformat(place.checked_at);
        expires = datetime.datetime.fromisoformat(place.expires_at);
    } except ValueError {
        return "Evidence timestamps are not valid ISO instants";
    }
    if checked.tzinfo is None or expires.tzinfo is None {
        return "Evidence timestamps need a UTC offset";
    }
    if checked > now {
        return "Evidence is dated in the future";
    }
    if expires <= now {
        return "Evidence has expired";
    }
    return "";
}

def _check_requirement(requirement: ProfileRequirement, place: PlaceFacts, stale_reason: str) -> RequirementCheck {
    key = requirement.category + ":" + requirement.code;
    if requirement.category == "dietary" and place.category != "food" {
        return RequirementCheck(requirement_id=requirement.id, evidence_key=key,
            status="not_applicable", reason="Dietary needs apply only to places that serve food");
    }
    if stale_reason {
        return RequirementCheck(requirement_id=requirement.id, evidence_key=key,
            status="unknown", reason=stale_reason);
    }
    value = place.eligibility.get(key);
    if value is True {
        return RequirementCheck(requirement_id=requirement.id, evidence_key=key,
            status="pass", reason=key + " is supported");
    }
    if value is False {
        return RequirementCheck(requirement_id=requirement.id, evidence_key=key,
            status="fail", reason=key + " is not supported");
    }
    return RequirementCheck(requirement_id=requirement.id, evidence_key=key,
        status="unknown", reason="No evidence for " + key);
}

def _check_child_ages(child_ages: list[int], place: PlaceFacts, stale_reason: str) -> RequirementCheck {
    key = "child:admission_ages";
    if stale_reason {
        return RequirementCheck(requirement_id=CHILD_AGES_CHECK_ID, evidence_key=key,
            status="unknown", reason=stale_reason);
    }
    lowest = place.child_min_age;
    highest = place.child_max_age;
    if lowest is None or highest is None {
        return RequirementCheck(requirement_id=CHILD_AGES_CHECK_ID, evidence_key=key,
            status="unknown", reason="Child admission ages are not known");
    }
    if lowest < 0 or highest < lowest {
        return RequirementCheck(requirement_id=CHILD_AGES_CHECK_ID, evidence_key=key,
            status="fail", reason="Child admission age range is invalid");
    }
    for age in child_ages {
        if age < lowest or age > highest {
            return RequirementCheck(requirement_id=CHILD_AGES_CHECK_ID, evidence_key=key,
                status="fail", reason="A child aged " + str(age) + " is outside ages "
                    + str(lowest) + " to " + str(highest));
        }
    }
    return RequirementCheck(requirement_id=CHILD_AGES_CHECK_ID, evidence_key=key,
        status="pass", reason="Every child is within ages " + str(lowest) + " to " + str(highest));
}

"""Combine answers: any fail -> "fail", else any unknown -> "unknown", else "pass"."""
def overall_status(checks: list[RequirementCheck]) -> str {
    has_unknown = False;
    for check in checks {
        if check.status == "fail" {
            return "fail";
        }
        if check.status == "unknown" {
            has_unknown = True;
        }
    }
    if has_unknown {
        return "unknown";
    }
    return "pass";
}

"""Check `place` against every must-have in `profile` at the time `now`.

Raises ValueError for a malformed profile, a place without an id, or a clock
without a timezone.
"""
def evaluate_place(profile: TravelerProfile, place: PlaceFacts, now: datetime.datetime) -> FilterResult {
    if now.tzinfo is None {
        raise ValueError("Clock must be timezone-aware");
    }
    if not place.id.strip() {
        raise ValueError("Each place needs an id");
    }
    require_valid_profile(profile);

    stale_reason = evidence_problem(place, now);
    checks: list[RequirementCheck] = [];
    for requirement in hard_requirements(profile) {
        checks.append(_check_requirement(requirement, place, stale_reason));
    }
    if profile.child_ages {
        checks.append(_check_child_ages(profile.child_ages, place, stale_reason));
    }
    return FilterResult(contract_version=FILTER_CONTRACT_VERSION, profile_id=profile.id,
        place_id=place.id, source_ref=place.source_ref, status=overall_status(checks), checks=checks);
}
