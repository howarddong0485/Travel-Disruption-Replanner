"""Boundary tests for standalone full-trip checks; all facts are synthetic."""
from copy import deepcopy
from dataclasses import replace
from datetime import datetime, timedelta, timezone
import unittest

from backup.validation import MissingFact, instant, validate_replacement
from backup.validation_fixtures import build_fixture, run_fixture
from backup.validation_models import Dependency, Moment, Window

NOW = datetime(2026, 10, 13, 12, tzinfo=timezone.utc)


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.trip, self.risk, self.options = build_fixture("rain", "family", NOW)
        self.option = self.options[0]

    def result(self, trip=None, option=None, risk=None):
        return validate_replacement(trip or self.trip, risk or self.risk, option or self.option, NOW)

    def changed(self, **changes):
        return replace(self.option, item=replace(self.option.item, **changes))

    def assertCheck(self, result, code, status):
        self.assertTrue(any(c['code'] == code and c['status'] == status for c in result['checks']), result)

    def test_complete_whole_trip_and_cost(self):
        r = self.result()
        self.assertEqual(r['status'], 'passed_fixture_checks')
        self.assertEqual(r['cost']['projected_total_minor'], 44000)
        self.assertEqual(r['cost']['retained_original_payment_minor'], 1500)
        self.assertEqual(len(r['proposed_items']), 4)
        self.assertEqual(r['scope'], 'standalone_fixture')

    def test_budget_exact_boundary_and_one_cent_over(self):
        self.assertEqual(self.result(trip=replace(self.trip, budget_minor=44000))['status'], 'passed_fixture_checks')
        self.assertCheck(self.result(trip=replace(self.trip, budget_minor=43999)), 'budget', 'fail')

    def test_missing_and_malformed_budget(self):
        self.assertCheck(self.result(trip=replace(self.trip, budget_minor=None)), 'budget', 'unknown')
        for value in (-1, True, 44.5):
            with self.subTest(value=value):
                self.assertCheck(self.result(trip=replace(self.trip, budget_minor=value)), 'budget', 'fail')

    def test_quote_requires_whole_party_and_fees(self):
        for changes in ({'cost_minor': None}, {'party_size': 1}, {'fees_included': False}):
            with self.subTest(changes=changes):
                r = self.result(option=self.changed(**changes))
                self.assertEqual(r['status'], 'needs_validation')
                self.assertIsNone(r['cost']['projected_total_minor'])
        self.assertCheck(self.result(option=self.changed(cost_minor=-1)), 'price', 'fail')

    def test_currency_never_invents_conversion(self):
        self.assertCheck(self.result(option=self.changed(currency='EUR')), 'currency', 'unknown')
        self.assertCheck(self.result(trip=replace(self.trip, currency='')), 'currency', 'unknown')

    def test_unknown_original_payment_and_no_refunds(self):
        items = tuple(replace(i, paid_minor=None) if i.id == 'activity' else i for i in self.trip.items)
        self.assertCheck(self.result(trip=replace(self.trip, items=items)), 'original_payment', 'unknown')
        r = self.result(option=self.changed(cost_minor=0))
        self.assertEqual(r['cost']['projected_total_minor'], 38000)

    def test_invalid_existing_payment(self):
        items = tuple(replace(i, paid_minor=999999) if i.id == 'hotel' else i for i in self.trip.items)
        self.assertCheck(self.result(trip=replace(self.trip, items=items)), 'payment', 'fail')

    def test_fixed_and_completed_target(self):
        for field in ('fixed', 'completed'):
            items = tuple(replace(i, **{field: True}) if i.id == 'activity' else i for i in self.trip.items)
            self.assertCheck(self.result(trip=replace(self.trip, items=items)), 'protected_item', 'fail')

    def test_unchanged_item_constraints_are_checked(self):
        items = tuple(replace(i, availability='unavailable') if i.id == 'hotel' else i for i in self.trip.items)
        self.assertCheck(self.result(trip=replace(self.trip, items=items)), 'availability', 'fail')

    def test_full_duration_opening_hours_and_close_boundary(self):
        item = self.option.item
        exact = (Window(item.start, item.end),)
        self.assertEqual(self.result(option=self.changed(hours=exact))['status'], 'passed_fixture_checks')
        too_short = (Window(item.start, replace(item.end, local=item.end.local[:11] + '11:59')),)
        self.assertCheck(self.result(option=self.changed(hours=too_short)), 'opening_hours', 'fail')
        self.assertCheck(self.result(option=self.changed(hours=None)), 'opening_hours', 'unknown')
        self.assertCheck(self.result(option=self.changed(hours=())), 'opening_hours', 'fail')

    def test_overlap_including_identical_intervals(self):
        first = self.trip.items[0]
        self.assertCheck(self.result(option=self.changed(start=first.start, end=first.end)), 'overlap', 'fail')

    def test_transfer_duration_missing_stale_and_wrong_venue(self):
        first, second = self.option.transfers
        for changed, status in ((replace(first, minutes=61), 'fail'), (replace(first, minutes=None), 'unknown'),
                                (replace(first, to_venue='old venue'), 'unknown'), (replace(first, evidence=None), 'unknown')):
            r = self.result(option=replace(self.option, transfers=(changed, second)))
            self.assertNotEqual(r['status'], 'passed_fixture_checks')
            self.assertTrue(any(c['status'] == status and c['code'].startswith('transfer') for c in r['checks']))
        self.assertCheck(self.result(option=replace(self.option, transfers=())), 'transfer', 'unknown')

    def test_each_hard_requirement_and_unknown(self):
        for need in ('pet:dog', 'accessibility:wheelchair', 'indoor'):
            with self.subTest(need=need):
                rules = {**self.option.item.eligibility, need: False}
                self.assertCheck(self.result(option=self.changed(eligibility=rules)), 'eligibility', 'fail')
                rules[need] = None
                self.assertCheck(self.result(option=self.changed(eligibility=rules)), 'eligibility', 'unknown')
        self.assertCheck(self.result(option=self.changed(child_min_age=9)), 'child_age', 'fail')
        self.assertCheck(self.result(option=self.changed(child_max_age=None)), 'child_age', 'unknown')

    def test_dietary_requirement_on_unchanged_meal(self):
        items = tuple(replace(i, eligibility={**i.eligibility, 'dietary:vegetarian': False}) if i.category == 'food' else i for i in self.trip.items)
        self.assertCheck(self.result(trip=replace(self.trip, items=items)), 'eligibility', 'fail')

    def test_soft_interests_never_override_hard_failure(self):
        trip = replace(self.trip, profile=replace(self.trip.profile, interests=('garden', 'museum')))
        self.assertEqual(self.result(trip=trip)['status'], 'passed_fixture_checks')
        self.assertEqual(self.result(trip=trip, option=self.changed(availability='unavailable'))['status'], 'invalid')

    def test_incomplete_profile_and_invalid_child_age(self):
        self.assertCheck(self.result(trip=replace(self.trip, profile=replace(self.trip.profile, complete=False))), 'profile', 'unknown')
        self.assertCheck(self.result(trip=replace(self.trip, profile=replace(self.trip.profile, child_ages=(-1,)))), 'profile', 'fail')

    def test_evidence_expiry_boundary_future_and_blank(self):
        e = self.option.item.evidence
        for changed in (replace(e, expires_at=NOW.isoformat()), replace(e, source='  '),
                        replace(e, checked_at=(NOW + timedelta(minutes=1)).isoformat())):
            self.assertCheck(self.result(option=self.changed(evidence=changed)), 'item_evidence', 'unknown')

    def test_scope_and_risk_are_not_trusted(self):
        self.assertCheck(self.result(risk=replace(self.risk, trip_id='other')), 'risk_scope', 'fail')
        self.assertCheck(self.result(risk=replace(self.risk, evidence=None)), 'risk_evidence', 'unknown')
        self.assertCheck(self.result(risk=replace(self.risk, status='unknown')), 'risk_status', 'unknown')
        self.assertCheck(self.result(option=replace(self.option, replaces_id='missing')), 'replacement_scope', 'fail')

    def test_delay_cannot_begin_before_new_arrival(self):
        trip, risk, options = build_fixture('arrival_delay', 'family', NOW)
        self.assertEqual(validate_replacement(trip, risk, options[0], NOW)['status'], 'passed_fixture_checks')
        risk = replace(risk, not_before=replace(risk.not_before, local=trip.start_date + 'T20:00'))
        self.assertCheck(validate_replacement(trip, risk, options[0], NOW), 'arrival_delay', 'fail')

    def test_dependencies_and_cycles(self):
        for edges, code in (((Dependency('activity', 'dinner', 400),), 'dependency'),
                            ((Dependency('activity', 'dinner', 0), Dependency('dinner', 'activity', 0)), 'dependency_cycle'),
                            ((Dependency('missing', 'dinner', 0),), 'dependency')):
            self.assertCheck(self.result(trip=replace(self.trip, dependencies=edges)), code, 'fail')

    def test_outside_trip_and_overnight_window(self):
        item = self.option.item
        next_day = (datetime.fromisoformat(self.trip.end_date) + timedelta(days=1)).date().isoformat()
        late_end = Moment(next_day + 'T00:30', item.end.zone)
        late_start = replace(item.start, local=self.trip.end_date + 'T23:30')
        option = self.changed(start=late_start, end=late_end, hours=(Window(late_start, late_end),))
        self.assertCheck(self.result(option=option), 'trip_bounds', 'fail')
        self.assertCheck(self.result(option=option), 'opening_hours', 'pass')

    def test_dst_gap_fold_and_cross_timezone(self):
        with self.assertRaises(ValueError):
            instant(Moment('2026-03-08T02:30', 'America/New_York'))
        with self.assertRaises(MissingFact):
            instant(Moment('2026-11-01T01:30', 'America/New_York'))
        first = instant(Moment('2026-11-01T01:30', 'America/New_York', 0))
        second = instant(Moment('2026-11-01T01:30', 'America/New_York', 1))
        self.assertEqual(second - first, timedelta(hours=1))
        self.assertEqual(instant(Moment('2026-10-20T11:00', 'America/New_York')),
                         instant(Moment('2026-10-20T08:00', 'America/Los_Angeles')))
        item = self.option.item
        cross_zone = self.changed(start=Moment(self.trip.start_date + 'T08:00', 'America/Los_Angeles'),
                                  end=Moment(self.trip.start_date + 'T09:00', 'America/Los_Angeles'))
        self.assertEqual(self.result(option=cross_zone)['status'], 'passed_fixture_checks')

    def test_ambiguous_time_is_unknown_invalid_time_fails(self):
        trip = replace(self.trip, start_date='2026-11-01', end_date='2026-11-01')
        option = self.changed(start=Moment('2026-11-01T01:30', 'America/New_York'))
        self.assertCheck(self.result(trip=trip, option=option), 'schedule', 'unknown')
        self.assertCheck(self.result(option=self.changed(start=Moment('bad-date', 'America/New_York'))), 'schedule', 'fail')

    def test_inputs_not_mutated_and_results_independent(self):
        original = deepcopy((self.trip, self.risk, self.options))
        a = self.result()
        a['proposed_items'][0]['title'] = 'changed result'
        b = self.result(option=self.options[1])
        self.assertEqual((self.trip, self.risk, self.options), original)
        self.assertNotEqual(b['proposed_items'][0]['title'], 'changed result')
        self.assertEqual(a['base_snapshot'], b['base_snapshot'])
        modified = replace(self.trip, reserve_minor=6000)
        self.assertNotEqual(a['base_snapshot'], self.result(trip=modified)['base_snapshot'])

    def test_fixture_scenarios(self):
        for scenario, first in (('rain', 'passed_fixture_checks'), ('arrival_delay', 'passed_fixture_checks'),
                                ('missing_evidence', 'needs_validation'), ('stale_evidence', 'needs_validation'),
                                ('schedule_conflict', 'invalid'), ('fixed_item', 'invalid'), ('eligibility_conflict', 'invalid')):
            with self.subTest(scenario=scenario):
                r = run_fixture(scenario, now=NOW)
                self.assertEqual(r['results'][0]['status'], first)
        self.assertEqual(run_fixture('eligibility_conflict', 'solo', now=NOW)['results'][0]['status'], 'passed_fixture_checks')

    def test_fixture_input_validation_and_low_budget(self):
        for budget in ('-1', 'NaN', 'Infinity', '10.001', '1e4', '100000001', '1' * 100):
            with self.subTest(budget=budget), self.assertRaises(ValueError):
                run_fixture(budget=budget, now=NOW)
        for kwargs in ({'scenario': 'bad'}, {'profile_name': 'bad'}, {'now': NOW.replace(tzinfo=None)}):
            with self.assertRaises(ValueError):
                run_fixture(**kwargs)
        self.assertEqual(run_fixture(budget='400', now=NOW)['summary']['invalid'], 2)
        self.assertEqual(run_fixture(budget='', now=NOW)['summary']['needs_validation'], 2)


if __name__ == '__main__':
    unittest.main()
