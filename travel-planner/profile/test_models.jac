"""Deterministic checks for the draft TravelerProfile contract, fixtures and helpers."""
import json;
import from jaclang.data.serializer { Serializer }
import from profile.models { TravelerProfile, ProfileRequirement, PetDetail, PROFILE_CONTRACT_VERSION }
import from profile.fixtures { family_with_pet_vegetarian, solo_traveler, contradictory_constraints }
import from profile.checks { hard_requirements, soft_preferences, profile_problems, require_valid_profile }

"""Remove the random per-object id Jac adds, so two equal profiles compare equal."""
def without_object_ids(value: any) -> any {
    if isinstance(value, dict) {
        cleaned: dict[str, any] = {};
        for key in value {
            if key != "_jac_id" {
                cleaned[key] = without_object_ids(value[key]);
            }
        }
        return cleaned;
    }
    if isinstance(value, list) {
        return [without_object_ids(item) for item in value];
    }
    return value;
}

def as_json(profile: TravelerProfile) -> str {
    plain = without_object_ids(Serializer.serialize(profile, api_mode=True));
    return json.dumps(plain, sort_keys=True);
}

def codes(requirements: list[ProfileRequirement]) -> list[str] {
    return [requirement.code for requirement in requirements];
}

def problems_text(profile: TravelerProfile) -> str {
    return " | ".join(profile_problems(profile));
}

test "every fixture is well-formed and carries the contract version" {
    for profile in [family_with_pet_vegetarian(), solo_traveler(), contradictory_constraints()] {
        assert profile.contract_version == PROFILE_CONTRACT_VERSION;
        assert profile_problems(profile) == [], problems_text(profile);
        require_valid_profile(profile);
    }
}

test "fixtures serialize to the same JSON every time" {
    assert as_json(family_with_pet_vegetarian()) == as_json(family_with_pet_vegetarian());
    assert as_json(solo_traveler()) == as_json(solo_traveler());
    assert as_json(contradictory_constraints()) == as_json(contradictory_constraints());
    data = json.loads(as_json(family_with_pet_vegetarian()));
    assert data["contract_version"] == "person1.traveler-profile.v1";
    assert data["adults"] == 2 and data["child_ages"] == [6];
    assert data["pets"][0]["species"] == "dog";
    assert data["requirements"][0]["code"] == "vegetarian" and data["requirements"][0]["strength"] == "hard";
    assert as_json(family_with_pet_vegetarian()) != as_json(solo_traveler());
}

test "hard requirements and soft preferences are separated" {
    family = family_with_pet_vegetarian();
    assert codes(hard_requirements(family)) == ["vegetarian", "pet_friendly"];
    assert codes(soft_preferences(family)) == ["kids_menu"];
    solo = solo_traveler();
    assert hard_requirements(solo) == [];
    assert codes(soft_preferences(solo)) == ["vegetarian", "step_free"];
}

test "contradictory fixture is valid data with conflicting must-haves" {
    profile = contradictory_constraints();
    assert profile_problems(profile) == [];
    assert profile.child_ages == [2];
    assert "adults_only" in codes(hard_requirements(profile));
}

test "party problems are reported" {
    profile = family_with_pet_vegetarian();
    profile.adults = 0;
    assert "at least one adult" in problems_text(profile);

    profile = family_with_pet_vegetarian();
    profile.child_ages = [6, -1, 18];
    assert "Child age -1" in problems_text(profile) and "Child age 18" in problems_text(profile);
    assert "Child age 6 " not in problems_text(profile);

    profile = family_with_pet_vegetarian();
    profile.pets = [PetDetail(species=" ", size="huge")];
    assert "needs a species" in problems_text(profile) and "Pet size 'huge'" in problems_text(profile);
}

test "booleans and non-whole numbers are rejected for adults and child ages" {
    # Typed as `any` so the wrong values reach the checker, as they could from JSON or a teammate's code.
    bad_adult_counts: list[any] = [True, False, 2.0];
    for bad_adults in bad_adult_counts {
        profile = solo_traveler();
        profile.adults = bad_adults;
        assert "Number of adults must be a whole number" in problems_text(profile), repr(bad_adults);
        rejected = False;
        try { require_valid_profile(profile); }
        except ValueError { rejected = True; }
        assert rejected, repr(bad_adults);
    }
    bad_child_ages: list[any] = [True, False, 6.5];
    for bad_age in bad_child_ages {
        profile = family_with_pet_vegetarian();
        profile.child_ages = [bad_age];
        assert "Each child age must be a whole number" in problems_text(profile), repr(bad_age);
        rejected = False;
        try { require_valid_profile(profile); }
        except ValueError { rejected = True; }
        assert rejected, repr(bad_age);
    }
}

test "boundary child ages 0 and 17 are accepted" {
    profile = family_with_pet_vegetarian();
    profile.child_ages = [0, 17];
    assert profile_problems(profile) == [];
}

test "requirement problems are reported" {
    profile = family_with_pet_vegetarian();
    profile.requirements[1].id = "req-vegetarian";
    assert "'req-vegetarian' is used more than once" in problems_text(profile);

    profile = family_with_pet_vegetarian();
    profile.requirements[0].id = "";
    profile.requirements[0].code = " ";
    assert "needs an id" in problems_text(profile) and "needs a code" in problems_text(profile);

    profile = family_with_pet_vegetarian();
    profile.requirements[0].category = "budget";
    profile.requirements[1].strength = "maybe";
    assert "unknown category 'budget'" in problems_text(profile);
    assert "unknown strength 'maybe'" in problems_text(profile);

    profile = family_with_pet_vegetarian();
    profile.requirements.append(
        ProfileRequirement(id="req-vegetarian-soft", category="dietary", code="vegetarian", strength="soft"));
    assert "req-vegetarian-soft repeats dietary/vegetarian" in problems_text(profile);
}

test "profile level problems are reported" {
    profile = solo_traveler();
    profile.id = "";
    profile.contract_version = "someone-else.v9";
    profile.interests = ["food", ""];
    profile.pace = "sprint";
    text = problems_text(profile);
    assert "needs an id" in text and "Unsupported profile contract version 'someone-else.v9'" in text;
    assert "Interests cannot be blank" in text and "Pace 'sprint'" in text;
    assert len(profile_problems(profile)) == 4;
}

test "unknown pace and pet size are allowed and stay unknown" {
    profile = family_with_pet_vegetarian();
    profile.pace = "unknown";
    profile.pets[0].size = "unknown";
    assert profile_problems(profile) == [];
    assert profile.pace == "unknown" and profile.pets[0].size == "unknown";
}

test "require_valid_profile raises ValueError listing every problem" {
    profile = solo_traveler();
    profile.adults = 0;
    profile.pace = "sprint";
    message = "";
    try { require_valid_profile(profile); }
    except ValueError as error { message = str(error); }
    assert message.startswith("Invalid traveler profile: ");
    assert "at least one adult" in message and "Pace 'sprint'" in message;
}

test "helpers do not change the profile and fixtures are independent copies" {
    profile = family_with_pet_vegetarian();
    before = as_json(profile);
    hard = hard_requirements(profile);
    soft_preferences(profile);
    profile_problems(profile);
    require_valid_profile(profile);
    assert as_json(profile) == before;

    hard.clear();
    assert len(profile.requirements) == 3;

    profile.requirements.clear();
    profile.child_ages.append(1);
    fresh = family_with_pet_vegetarian();
    assert len(fresh.requirements) == 3 and fresh.child_ages == [6];
}
