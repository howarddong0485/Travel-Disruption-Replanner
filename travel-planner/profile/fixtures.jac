"""Synthetic traveler profiles for tests and demos. No real people or bookings.

Each function builds a new profile every time it is called, so a caller can
change its copy without affecting anyone else.
"""
import from profile.models { TravelerProfile, ProfileRequirement, PetDetail, PROFILE_CONTRACT_VERSION }

"""Two adults, a six-year-old and a dog. Vegetarian and pet-friendly are must-haves."""
def family_with_pet_vegetarian -> TravelerProfile {
    requirements = [
        ProfileRequirement(id="req-vegetarian", category="dietary", code="vegetarian", strength="hard"),
        ProfileRequirement(id="req-pet-friendly", category="pet", code="pet_friendly", strength="hard"),
        ProfileRequirement(id="req-kids-menu", category="child", code="kids_menu", strength="soft",
            note="Nice to have at dinner")
    ];
    return TravelerProfile(
        id="demo-family",
        contract_version=PROFILE_CONTRACT_VERSION,
        adults=2,
        child_ages=[6],
        pets=[PetDetail(species="dog", size="medium")],
        requirements=requirements,
        interests=["museums", "outdoors"],
        pace="moderate"
    );
}

"""One adult with preferences only. There are no must-haves."""
def solo_traveler -> TravelerProfile {
    requirements = [
        ProfileRequirement(id="req-vegetarian", category="dietary", code="vegetarian", strength="soft"),
        ProfileRequirement(id="req-step-free", category="accessibility", code="step_free", strength="soft")
    ];
    return TravelerProfile(
        id="demo-solo",
        contract_version=PROFILE_CONTRACT_VERSION,
        adults=1,
        child_ages=[],
        pets=[],
        requirements=requirements,
        interests=["food", "live_music"],
        pace="packed"
    );
}

"""A well-formed profile whose must-haves cannot all be met.

The party includes a two-year-old, and adults-only venues are a must-have. The
profile itself is valid data. Reporting the conflict is the validator's job.
"""
def contradictory_constraints -> TravelerProfile {
    requirements = [
        ProfileRequirement(id="req-adults-only", category="child", code="adults_only", strength="hard",
            note="Conflicts with the two-year-old in the party"),
        ProfileRequirement(id="req-stroller", category="accessibility", code="stroller_accessible", strength="hard")
    ];
    return TravelerProfile(
        id="demo-contradictory",
        contract_version=PROFILE_CONTRACT_VERSION,
        adults=2,
        child_ages=[2],
        pets=[],
        requirements=requirements,
        interests=["museums"],
        pace="relaxed"
    );
}
