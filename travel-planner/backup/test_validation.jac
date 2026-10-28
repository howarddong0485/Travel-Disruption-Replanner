"""Boundary tests for standalone full-trip checks; all facts are synthetic."""
import from copy { deepcopy }
import from dataclasses { replace }
import from datetime { datetime, timedelta, timezone }
import unittest;
import from backup.validation { MissingFact, instant, validate_replacement }
import from backup.validation_fixtures { build_fixture, run_fixture }
import from backup.validation_models { Dependency, Moment, Window, TripContext, RiskContext, Replacement }
glob NOW = datetime(2026, 10, 13, 12, tzinfo=timezone.utc);
class ValidationFixture(unittest.TestCase) {
    with entry {
        trip: TripContext;
        risk: RiskContext;
        options: tuple[Replacement, ...];
        option: Replacement;
    }
    def setUp(self: ValidationFixture) -> any {
        (self.trip, self.risk, self.options) = build_fixture("rain", "family", NOW);
        self.option = self.options[0];
    }
    def result(
        self: ValidationFixture, trip: any = None, option: any = None, risk: any = None
    ) -> any {
        return validate_replacement(
            (trip or self.trip), (risk or self.risk), (option or self.option), NOW
        );
    }
    def changed(self: ValidationFixture, **changes: any) -> any {
        return replace(self.option, item=replace(self.option.item, **changes));
    }
    def assertCheck(
        self: ValidationFixture, result: any, code: any, status: any
    ) -> any {
        self.assertTrue(
            `any(
                ((c['code'] == code) and (c['status'] == status))
                for c in result['checks']
            ),
            result
        );
    }
}
test "complete whole trip and cost" {
    fixture = ValidationFixture();
    fixture.setUp();
    r = fixture.result();
    fixture.assertEqual(r['status'], 'passed_fixture_checks');
    fixture.assertEqual(r['cost']['projected_total_minor'], 44000);
    fixture.assertEqual(r['cost']['retained_original_payment_minor'], 1500);
    fixture.assertEqual(len(r['proposed_items']), 4);
    fixture.assertEqual(r['scope'], 'standalone_fixture');
}

test "budget exact boundary and one cent over" {
    fixture = ValidationFixture();
    fixture.setUp();
    fixture.assertEqual(
        fixture.result(trip=replace(fixture.trip, budget_minor=44000))['status'],
        'passed_fixture_checks'
    );
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, budget_minor=43999)), 'budget', 'fail'
    );
}

test "missing and malformed budget" {
    fixture = ValidationFixture();
    fixture.setUp();
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, budget_minor=None)), 'budget', 'unknown'
    );
    for value in (-1, True, 44.5) {
        with fixture.subTest(value=value) {
            fixture.assertCheck(
                fixture.result(trip=replace(fixture.trip, budget_minor=value)),
                'budget',
                'fail'
            );
        }
    }
}

test "quote requires whole party and fees" {
    fixture = ValidationFixture();
    fixture.setUp();
    for changes in (
        {'cost_minor': None},
        {'party_size': 1},
        {'fees_included': False}
    ) {
        with fixture.subTest(changes=changes) {
            r = fixture.result(option=fixture.changed(**changes));
            fixture.assertEqual(r['status'], 'needs_validation');
            fixture.assertIsNone(r['cost']['projected_total_minor']);
        }
    }
    fixture.assertCheck(
        fixture.result(option=fixture.changed(cost_minor=-1)), 'price', 'fail'
    );
}

test "currency never invents conversion" {
    fixture = ValidationFixture();
    fixture.setUp();
    fixture.assertCheck(
        fixture.result(option=fixture.changed(currency='EUR')), 'currency', 'unknown'
    );
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, currency='')), 'currency', 'unknown'
    );
}

test "unknown original payment and no refunds" {
    fixture = ValidationFixture();
    fixture.setUp();
    items = `tuple(
        replace(i, paid_minor=None) if (i.id == 'activity') else i
        for i in fixture.trip.items
    );
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, items=items)),
        'original_payment',
        'unknown'
    );
    r = fixture.result(option=fixture.changed(cost_minor=0));
    fixture.assertEqual(r['cost']['projected_total_minor'], 38000);
}

test "invalid existing payment" {
    fixture = ValidationFixture();
    fixture.setUp();
    items = `tuple(
        replace(i, paid_minor=999999) if (i.id == 'hotel') else i
        for i in fixture.trip.items
    );
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, items=items)), 'payment', 'fail'
    );
}

test "fixed and completed target" {
    fixture = ValidationFixture();
    fixture.setUp();
    for field in ('fixed', 'completed') {
        items = `tuple(
            replace(i, **{field: True}) if (i.id == 'activity') else i
            for i in fixture.trip.items
        );
        fixture.assertCheck(
            fixture.result(trip=replace(fixture.trip, items=items)),
            'protected_item',
            'fail'
        );
    }
}

test "unchanged item constraints are checked" {
    fixture = ValidationFixture();
    fixture.setUp();
    items = `tuple(
        replace(i, availability='unavailable') if (i.id == 'hotel') else i
        for i in fixture.trip.items
    );
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, items=items)), 'availability', 'fail'
    );
}

test "full duration opening hours and close boundary" {
    fixture = ValidationFixture();
    fixture.setUp();
    item = fixture.option.item;
    exact = (Window(item.start, item.end), );
    fixture.assertEqual(
        fixture.result(option=fixture.changed(hours=exact))['status'],
        'passed_fixture_checks'
    );
    too_short = (
        Window(
            item.start, replace(item.end, local=(item.end.local[:11] + '11:59'))
        ),

    );
    fixture.assertCheck(
        fixture.result(option=fixture.changed(hours=too_short)), 'opening_hours', 'fail'
    );
    fixture.assertCheck(
        fixture.result(option=fixture.changed(hours=None)), 'opening_hours', 'unknown'
    );
    fixture.assertCheck(
        fixture.result(option=fixture.changed(hours=())), 'opening_hours', 'fail'
    );
}

test "overlap including identical intervals" {
    fixture = ValidationFixture();
    fixture.setUp();
    first = fixture.trip.items[0];
    fixture.assertCheck(
        fixture.result(option=fixture.changed(start=first.start, end=first.end)),
        'overlap',
        'fail'
    );
}

test "transfer duration missing stale and wrong venue" {
    fixture = ValidationFixture();
    fixture.setUp();
    (first, second) = fixture.option.transfers;
    for (changed, status) in (
        (replace(first, minutes=61), 'fail'),
        (replace(first, minutes=None), 'unknown'),
        (replace(first, to_venue='old venue'), 'unknown'),
        (replace(first, evidence=None), 'unknown')
    ) {
        r = fixture.result(option=replace(fixture.option, transfers=(changed, second)));
        fixture.assertNotEqual(r['status'], 'passed_fixture_checks');
        fixture.assertTrue(
            `any(
                ((c['status'] == status) and c['code'].startswith('transfer'))
                for c in r['checks']
            )
        );
    }
    fixture.assertCheck(
        fixture.result(option=replace(fixture.option, transfers=())),
        'transfer',
        'unknown'
    );
}

test "each hard requirement and unknown" {
    fixture = ValidationFixture();
    fixture.setUp();
    for need in ('pet:dog', 'accessibility:wheelchair', 'indoor') {
        with fixture.subTest(need=need) {
            rules = {** fixture.option.item.eligibility, need: False};
            fixture.assertCheck(
                fixture.result(option=fixture.changed(eligibility=rules)),
                'eligibility',
                'fail'
            );
            rules[need] = None;
            fixture.assertCheck(
                fixture.result(option=fixture.changed(eligibility=rules)),
                'eligibility',
                'unknown'
            );
        }
    }
    fixture.assertCheck(
        fixture.result(option=fixture.changed(child_min_age=9)), 'child_age', 'fail'
    );
    fixture.assertCheck(
        fixture.result(option=fixture.changed(child_max_age=None)), 'child_age', 'unknown'
    );
}

test "dietary requirement on unchanged meal" {
    fixture = ValidationFixture();
    fixture.setUp();
    items = `tuple(
        replace(i, eligibility={** i.eligibility, 'dietary:vegetarian': False})
            if (i.category == 'food')
            else i for i in fixture.trip.items
    );
    fixture.assertCheck(
        fixture.result(trip=replace(fixture.trip, items=items)), 'eligibility', 'fail'
    );
}

test "soft interests never override hard failure" {
    fixture = ValidationFixture();
    fixture.setUp();
    trip = replace(
        fixture.trip,
        profile=replace(fixture.trip.profile, interests=('garden', 'museum'))
    );
    fixture.assertEqual(fixture.result(trip=trip)['status'], 'passed_fixture_checks');
    fixture.assertEqual(
        fixture.result(trip=trip, option=fixture.changed(availability='unavailable'))[
            'status'
        ],
        'invalid'
    );
}

test "incomplete profile and invalid child age" {
    fixture = ValidationFixture();
    fixture.setUp();
    fixture.assertCheck(
        fixture.result(
            trip=replace(
                fixture.trip, profile=replace(fixture.trip.profile, complete=False)
            )
        ),
        'profile',
        'unknown'
    );
    fixture.assertCheck(
        fixture.result(
            trip=replace(
                fixture.trip, profile=replace(fixture.trip.profile, child_ages=(-1, ))
            )
        ),
        'profile',
        'fail'
    );
}

test "evidence expiry boundary future and blank" {
    fixture = ValidationFixture();
    fixture.setUp();
    e = fixture.option.item.evidence;
    for changed in (
        replace(e, expires_at=NOW.isoformat()),
        replace(e, source='  '),
        replace(e, checked_at=(NOW + timedelta(minutes=1)).isoformat())
    ) {
        fixture.assertCheck(
            fixture.result(option=fixture.changed(evidence=changed)),
            'item_evidence',
            'unknown'
        );
    }
}

test "scope and risk are not trusted" {
    fixture = ValidationFixture();
    fixture.setUp();
    fixture.assertCheck(
        fixture.result(risk=replace(fixture.risk, trip_id='other')), 'risk_scope', 'fail'
    );
    fixture.assertCheck(
        fixture.result(risk=replace(fixture.risk, evidence=None)),
        'risk_evidence',
        'unknown'
    );
    fixture.assertCheck(
        fixture.result(risk=replace(fixture.risk, status='unknown')),
        'risk_status',
        'unknown'
    );
    fixture.assertCheck(
        fixture.result(option=replace(fixture.option, replaces_id='missing')),
        'replacement_scope',
        'fail'
    );
}

test "delay cannot begin before new arrival" {
    fixture = ValidationFixture();
    fixture.setUp();
    (trip, risk, options) = build_fixture('arrival_delay', 'family', NOW);
    fixture.assertEqual(
        validate_replacement(trip, risk, options[0], NOW)['status'],
        'passed_fixture_checks'
    );
    risk = replace(
        risk,
        not_before=replace(risk.not_before, local=(trip.start_date + 'T20:00'))
    );
    fixture.assertCheck(
        validate_replacement(trip, risk, options[0], NOW), 'arrival_delay', 'fail'
    );
}

test "dependencies and cycles" {
    fixture = ValidationFixture();
    fixture.setUp();
    for (edges, code) in (
        ((Dependency('activity', 'dinner', 400), ), 'dependency'),
        (
            (
                Dependency('activity', 'dinner', 0),
                Dependency('dinner', 'activity', 0)
            ),
            'dependency_cycle'
        ),
        ((Dependency('missing', 'dinner', 0), ), 'dependency')
    ) {
        fixture.assertCheck(
            fixture.result(trip=replace(fixture.trip, dependencies=edges)), code, 'fail'
        );
    }
}

test "outside trip and overnight window" {
    fixture = ValidationFixture();
    fixture.setUp();
    item = fixture.option.item;
    next_day = (
        datetime.fromisoformat(fixture.trip.end_date) + timedelta(days=1)
    ).date().isoformat();
    late_end = Moment((next_day + 'T00:30'), item.end.zone);
    late_start = replace(item.start, local=(fixture.trip.end_date + 'T23:30'));
    option = fixture.changed(
        start=late_start, end=late_end, hours=(Window(late_start, late_end), )
    );
    fixture.assertCheck(fixture.result(option=option), 'trip_bounds', 'fail');
    fixture.assertCheck(fixture.result(option=option), 'opening_hours', 'pass');
}

test "dst gap fold and cross timezone" {
    fixture = ValidationFixture();
    fixture.setUp();
    with fixture.assertRaises(ValueError) {
        instant(Moment('2026-03-08T02:30', 'America/New_York'));
    }
    with fixture.assertRaises(MissingFact) {
        instant(Moment('2026-11-01T01:30', 'America/New_York'));
    }
    first = instant(Moment('2026-11-01T01:30', 'America/New_York', 0));
    second = instant(Moment('2026-11-01T01:30', 'America/New_York', 1));
    fixture.assertEqual((second - first), timedelta(hours=1));
    fixture.assertEqual(
        instant(Moment('2026-10-20T11:00', 'America/New_York')),
        instant(Moment('2026-10-20T08:00', 'America/Los_Angeles'))
    );
    item = fixture.option.item;
    cross_zone = fixture.changed(
        start=Moment((fixture.trip.start_date + 'T08:00'), 'America/Los_Angeles'),
        end=Moment((fixture.trip.start_date + 'T09:00'), 'America/Los_Angeles')
    );
    fixture.assertEqual(
        fixture.result(option=cross_zone)['status'], 'passed_fixture_checks'
    );
}

test "ambiguous time is unknown invalid time fails" {
    fixture = ValidationFixture();
    fixture.setUp();
    trip = replace(fixture.trip, start_date='2026-11-01', end_date='2026-11-01');
    option = fixture.changed(start=Moment('2026-11-01T01:30', 'America/New_York'));
    fixture.assertCheck(fixture.result(trip=trip, option=option), 'schedule', 'unknown');
    fixture.assertCheck(
        fixture.result(
            option=fixture.changed(start=Moment('bad-date', 'America/New_York'))
        ),
        'schedule',
        'fail'
    );
}

test "inputs not mutated and results independent" {
    fixture = ValidationFixture();
    fixture.setUp();
    original = deepcopy((fixture.trip, fixture.risk, fixture.options));
    a = fixture.result();
    a['proposed_items'][0]['title'] = 'changed result';
    b = fixture.result(option=fixture.options[1]);
    fixture.assertEqual((fixture.trip, fixture.risk, fixture.options), original);
    fixture.assertNotEqual(b['proposed_items'][0]['title'], 'changed result');
    fixture.assertEqual(a['base_snapshot'], b['base_snapshot']);
    modified = replace(fixture.trip, reserve_minor=6000);
    fixture.assertNotEqual(
        a['base_snapshot'], fixture.result(trip=modified)['base_snapshot']
    );
}

test "fixture scenarios" {
    fixture = ValidationFixture();
    fixture.setUp();
    for (scenario, first) in (
        ('rain', 'passed_fixture_checks'),
        ('arrival_delay', 'passed_fixture_checks'),
        ('missing_evidence', 'needs_validation'),
        ('stale_evidence', 'needs_validation'),
        ('schedule_conflict', 'invalid'),
        ('fixed_item', 'invalid'),
        ('eligibility_conflict', 'invalid')
    ) {
        with fixture.subTest(scenario=scenario) {
            r = run_fixture(scenario, now=NOW);
            fixture.assertEqual(r['results'][0]['status'], first);
        }
    }
    fixture.assertEqual(
        run_fixture('eligibility_conflict', 'solo', now=NOW)['results'][0][
            'status'
        ],
        'passed_fixture_checks'
    );
}

test "fixture input validation and low budget" {
    fixture = ValidationFixture();
    fixture.setUp();
    for budget in (
        '-1',
        'NaN',
        'Infinity',
        '10.001',
        '1e4',
        '100000001',
        ('1' * 100)
    ) {
        with fixture.subTest(budget=budget), fixture.assertRaises(ValueError) {
            run_fixture(budget=budget, now=NOW);
        }
    }
    for kwargs in (
        {'scenario': 'bad'},
        {'profile_name': 'bad'},
        {'now': NOW.replace(tzinfo=None)}
    ) {
        with fixture.assertRaises(ValueError) {
            run_fixture(**kwargs);
        }
    }
    fixture.assertEqual(run_fixture(budget='400', now=NOW)['summary']['invalid'], 2);
    fixture.assertEqual(
        run_fixture(budget='', now=NOW)['summary']['needs_validation'], 2
    );
}
