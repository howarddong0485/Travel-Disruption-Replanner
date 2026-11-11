"""Deterministic pass / fail / unknown checks for the mandatory filter."""
import copy;
import datetime;
import from profile.fixtures { family_with_pet_vegetarian, solo_traveler, contradictory_constraints }
import from filter.models { FilterResult, FILTER_CONTRACT_VERSION }
import from filter.fixtures { fixture_clock, veggie_cafe, steakhouse, unverified_bistro, science_museum }
import from filter.evaluate { evaluate_place }

"""Map each requirement id to its status, for short assertions."""
def statuses(result: FilterResult) -> dict[str, str] {
    found: dict[str, str] = {};
    for check in result.checks {
        found[check.requirement_id] = check.status;
    }
    return found;
}

def raises_value_error(profile: any, place: any, now: datetime.datetime) -> bool {
    try { evaluate_place(profile, place, now); }
    except ValueError { return True; }
    return False;
}

test "a place with supporting evidence passes every must-have" {
    result = evaluate_place(family_with_pet_vegetarian(), veggie_cafe(), fixture_clock());
    assert result.status == "pass";
    assert result.contract_version == FILTER_CONTRACT_VERSION;
    assert result.profile_id == "demo-family" and result.place_id == "veggie-cafe";
    assert result.source_ref == "mock://filter-v1/veggie-cafe";
    assert statuses(result) == {"req-vegetarian": "pass", "req-pet-friendly": "pass", "party-child-ages": "pass"};
}

test "evidence against a must-have fails" {
    result = evaluate_place(family_with_pet_vegetarian(), steakhouse(), fixture_clock());
    assert result.status == "fail";
    assert statuses(result)["req-vegetarian"] == "fail";
    assert statuses(result)["req-pet-friendly"] == "pass";
}

test "missing evidence is unknown and never pass" {
    result = evaluate_place(family_with_pet_vegetarian(), unverified_bistro(), fixture_clock());
    assert result.status == "unknown";
    assert statuses(result) == {"req-vegetarian": "unknown", "req-pet-friendly": "unknown", "party-child-ages": "unknown"};

    place = veggie_cafe();
    place.eligibility["dietary:vegetarian"] = None;
    result = evaluate_place(family_with_pet_vegetarian(), place, fixture_clock());
    assert result.status == "unknown" and statuses(result)["req-vegetarian"] == "unknown";
}

test "fail outranks unknown in the overall status" {
    place = steakhouse();
    place.eligibility.pop("pet:pet_friendly");
    result = evaluate_place(family_with_pet_vegetarian(), place, fixture_clock());
    assert statuses(result)["req-pet-friendly"] == "unknown";
    assert result.status == "fail";
}

test "dietary needs do not apply to places that do not serve food" {
    result = evaluate_place(family_with_pet_vegetarian(), science_museum(), fixture_clock());
    assert statuses(result)["req-vegetarian"] == "not_applicable";
    assert result.status == "pass";
}

test "child admission ages pass fail and stay unknown" {
    profile = family_with_pet_vegetarian();
    place = science_museum();
    place.child_min_age = 8;
    assert statuses(evaluate_place(profile, place, fixture_clock()))["party-child-ages"] == "fail";
    place.child_min_age = 10; place.child_max_age = 5;
    assert statuses(evaluate_place(profile, place, fixture_clock()))["party-child-ages"] == "fail";
    place.child_max_age = None;
    assert statuses(evaluate_place(profile, place, fixture_clock()))["party-child-ages"] == "unknown";
}

test "conflicting must-haves fail and unchecked ones stay unknown" {
    result = evaluate_place(contradictory_constraints(), science_museum(), fixture_clock());
    assert result.status == "fail";
    assert statuses(result) == {"req-adults-only": "fail", "req-stroller": "unknown", "party-child-ages": "fail"};
}

test "a traveler with no must-haves passes with nothing to check" {
    result = evaluate_place(solo_traveler(), steakhouse(), fixture_clock());
    assert result.status == "pass" and result.checks == [];
}

test "expired future malformed or unsourced evidence cannot pass" {
    later = fixture_clock() + datetime.timedelta(minutes=15);
    result = evaluate_place(family_with_pet_vegetarian(), veggie_cafe(), later);
    assert result.status == "unknown";
    assert statuses(result) == {"req-vegetarian": "unknown", "req-pet-friendly": "unknown", "party-child-ages": "unknown"};
    assert result.checks[0].reason == "Evidence has expired";

    for change in ["future", "no-offset", "garbage", "no-source"] {
        place = veggie_cafe();
        if change == "future" { place.checked_at = "2026-10-06T13:00:00+00:00"; }
        if change == "no-offset" { place.checked_at = "2026-10-06T12:00:00"; }
        if change == "garbage" { place.expires_at = "soon"; }
        if change == "no-source" { place.source_ref = " "; }
        result = evaluate_place(family_with_pet_vegetarian(), place, fixture_clock());
        assert result.status == "unknown", change;
    }
}

test "bad inputs are rejected with ValueError" {
    naive_clock = datetime.datetime(2026, 10, 6, 12, 0);
    assert raises_value_error(family_with_pet_vegetarian(), veggie_cafe(), naive_clock);

    place = veggie_cafe(); place.id = "";
    assert raises_value_error(family_with_pet_vegetarian(), place, fixture_clock());

    profile = family_with_pet_vegetarian(); profile.adults = 0;
    assert raises_value_error(profile, veggie_cafe(), fixture_clock());
}

test "evaluation is repeatable and does not change its inputs" {
    profile = family_with_pet_vegetarian();
    place = steakhouse();
    eligibility_before = copy.deepcopy(place.eligibility);
    first = evaluate_place(profile, place, fixture_clock());
    second = evaluate_place(profile, place, fixture_clock());
    assert [(c.requirement_id, c.status, c.reason) for c in first.checks]
        == [(c.requirement_id, c.status, c.reason) for c in second.checks];
    assert place.eligibility == eligibility_before;
    assert place.child_min_age == 0 and place.checked_at == "2026-10-06T12:00:00+00:00";
    assert len(profile.requirements) == 3 and profile.child_ages == [6];
}
