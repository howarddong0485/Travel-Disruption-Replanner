"""Person 1 draft contract; not the shared TravelerProfile schema.

Describes who is travelling and what they need. A requirement is either "hard"
(must be met) or "soft" (a preference). This file only defines the data shapes
and their allowed values. It does not check a profile or a plan.

Budget, trip dates and currency are not here. They belong to the Roam trip.
"""

glob PROFILE_CONTRACT_VERSION: str = "person1.traveler-profile.v1";

# The four mandatory-filter categories named in docs/ARCHITECTURE.md.
glob REQUIREMENT_CATEGORIES: list[str] = ["dietary", "pet", "child", "accessibility"];

# "hard" must be met. "soft" is a preference that may be traded off.
glob REQUIREMENT_STRENGTHS: list[str] = ["hard", "soft"];

# "unknown" means the traveler has not said. It is never treated as a real answer.
glob PACE_VALUES: list[str] = ["relaxed", "moderate", "packed", "unknown"];
glob PET_SIZES: list[str] = ["small", "medium", "large", "unknown"];

"""One pet travelling with the party."""
obj PetDetail {
    has species: str;    # for example "dog"
    has size: str;       # one of PET_SIZES
}

"""One thing the traveler needs or prefers, for example vegetarian dining."""
obj ProfileRequirement {
    has id: str;             # unique within one profile, for example "req-vegetarian"
    has category: str;       # one of REQUIREMENT_CATEGORIES
    has code: str;           # short machine-readable name, for example "vegetarian"
    has strength: str;       # one of REQUIREMENT_STRENGTHS
    has note: str = "";      # optional free text from the traveler
}

"""The traveler profile for one trip."""
obj TravelerProfile {
    has id: str;
    has contract_version: str;                    # use PROFILE_CONTRACT_VERSION
    has adults: int;
    has child_ages: list[int];                    # one age in years per child; empty if no children
    has pets: list[PetDetail];                    # empty if no pets
    has requirements: list[ProfileRequirement];   # hard and soft together; see strength
    has interests: list[str];                     # for example ["museums", "outdoors"]
    has pace: str;                                # one of PACE_VALUES
}
