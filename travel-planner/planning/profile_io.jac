"""JSON boundary for Person 1's profile; preserve every hard requirement.

Named profile_io so standalone scripts do not shadow the owner's profile package.
"""
import from profile.models { TravelerProfile, ProfileRequirement, PetDetail, PROFILE_CONTRACT_VERSION }
import from profile.checks { require_valid_profile }

def profile_from_data(data: dict[str, any]) -> TravelerProfile {
    if not isinstance(data, dict) { raise ValueError("Traveler profile must be an object"); }
    required = {"id", "contract_version", "adults", "child_ages", "pets", "requirements", "interests", "pace"};
    if set(data) != required { raise ValueError("Supply all TravelerProfile fields and no unsupported fields"); }
    if type(data["adults"]) is not int or not isinstance(data["child_ages"], list) or
        any(type(age) is not int for age in data["child_ages"]) { raise ValueError("Party counts and ages must be integers"); }
    for name in ("pets", "requirements", "interests") {
        if not isinstance(data[name], list) or len(data[name]) > 100 { raise ValueError("Invalid profile list: " + name); }
    }
    try {
        profile = TravelerProfile(**{**data,
            "pets": [PetDetail(**p) for p in data["pets"]],
            "requirements": [ProfileRequirement(**r) for r in data["requirements"]]});
        require_valid_profile(profile);
        # A travelling pet is itself a mandatory eligibility need, even when
        # intake did not repeat its species in the requirements list.
        for pet in profile.pets {
            matching = [r for r in profile.requirements if r.category == "pet" and r.code == pet.species];
            if matching { matching[0].strength = "hard"; }
            else {
                requirement_id = "party-pet-" + pet.species;
                while any(r.id == requirement_id for r in profile.requirements) { requirement_id = "_" + requirement_id; }
                profile.requirements.append(ProfileRequirement(id=requirement_id, category="pet", code=pet.species, strength="hard"));
            }
        }
        require_valid_profile(profile);
    } except (TypeError, AttributeError) as exc { raise ValueError("Malformed traveler profile") from exc; }
    return profile;
}
