"""Helpers for the Person 1 draft TravelerProfile contract.

Pure functions: they read a profile and never change it. They check that a
profile is well-formed data. They do not decide whether a trip is feasible.
"""
import from profile.models {
    TravelerProfile, ProfileRequirement, PROFILE_CONTRACT_VERSION,
    REQUIREMENT_CATEGORIES, REQUIREMENT_STRENGTHS, PACE_VALUES, PET_SIZES
}

glob MAX_CHILD_AGE: int = 17;

"""Return only the must-have requirements, in their original order."""
def hard_requirements(profile: TravelerProfile) -> list[ProfileRequirement] {
    result: list[ProfileRequirement] = [];
    for requirement in profile.requirements {
        if requirement.strength == "hard" {
            result.append(requirement);
        }
    }
    return result;
}

"""Return only the preferences, in their original order."""
def soft_preferences(profile: TravelerProfile) -> list[ProfileRequirement] {
    result: list[ProfileRequirement] = [];
    for requirement in profile.requirements {
        if requirement.strength == "soft" {
            result.append(requirement);
        }
    }
    return result;
}

"""True only for a real whole number. True and False are rejected even though Python treats them as 1 and 0."""
def is_whole_number(value: any) -> bool {
    if isinstance(value, bool) {
        return False;
    }
    return isinstance(value, int);
}

def _party_problems(profile: TravelerProfile) -> list[str] {
    problems: list[str] = [];
    if not is_whole_number(profile.adults) {
        problems.append("Number of adults must be a whole number, not " + repr(profile.adults));
    } elif profile.adults < 1 {
        problems.append("A profile needs at least one adult");
    }
    for age in profile.child_ages {
        if not is_whole_number(age) {
            problems.append("Each child age must be a whole number, not " + repr(age));
        } elif age < 0 or age > MAX_CHILD_AGE {
            problems.append("Child age " + str(age) + " must be between 0 and " + str(MAX_CHILD_AGE));
        }
    }
    for pet in profile.pets {
        if not pet.species.strip() {
            problems.append("Each pet needs a species");
        }
        if pet.size not in PET_SIZES {
            problems.append("Pet size '" + pet.size + "' is not one of: " + ", ".join(PET_SIZES));
        }
    }
    return problems;
}

def _requirement_problems(profile: TravelerProfile) -> list[str] {
    problems: list[str] = [];
    seen_ids: list[str] = [];
    seen_topics: list[str] = [];
    for requirement in profile.requirements {
        label = requirement.id.strip() or "(no id)";
        if not requirement.id.strip() {
            problems.append("Each requirement needs an id");
        } elif requirement.id in seen_ids {
            problems.append("Requirement id '" + requirement.id + "' is used more than once");
        }
        seen_ids.append(requirement.id);
        if requirement.category not in REQUIREMENT_CATEGORIES {
            problems.append("Requirement " + label + " has unknown category '" + requirement.category + "'");
        }
        if requirement.strength not in REQUIREMENT_STRENGTHS {
            problems.append("Requirement " + label + " has unknown strength '" + requirement.strength + "'");
        }
        if not requirement.code.strip() {
            problems.append("Requirement " + label + " needs a code");
        }
        # The same need listed twice, for example vegetarian as both hard and soft, is ambiguous.
        topic = requirement.category + "/" + requirement.code;
        if topic in seen_topics {
            problems.append("Requirement " + label + " repeats " + topic);
        }
        seen_topics.append(topic);
    }
    return problems;
}

"""List everything wrong with the shape of a profile. An empty list means it is well-formed."""
def profile_problems(profile: TravelerProfile) -> list[str] {
    problems: list[str] = [];
    if not profile.id.strip() {
        problems.append("A profile needs an id");
    }
    if profile.contract_version != PROFILE_CONTRACT_VERSION {
        problems.append("Unsupported profile contract version '" + profile.contract_version + "'");
    }
    problems.extend(_party_problems(profile));
    problems.extend(_requirement_problems(profile));
    for interest in profile.interests {
        if not interest.strip() {
            problems.append("Interests cannot be blank");
        }
    }
    if profile.pace not in PACE_VALUES {
        problems.append("Pace '" + profile.pace + "' is not one of: " + ", ".join(PACE_VALUES));
    }
    return problems;
}

"""Raise ValueError with every problem if the profile is not well-formed."""
def require_valid_profile(profile: TravelerProfile) -> None {
    problems = profile_problems(profile);
    if problems {
        raise ValueError("Invalid traveler profile: " + "; ".join(problems));
    }
}
