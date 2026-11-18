/** Departure/return map fallbacks use local fixtures; no live AI or flight searches. */
const {browserWorkspace} = require('./browser_workspace.cjs');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const appUrl = process.env.TRAVEL_APP_URL || 'http://127.0.0.1:8379';
const apiUrl = process.env.TRAVEL_API_URL || appUrl + '/api/server';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  const workspace_key = await browserWorkspace(page);

  page.setDefaultTimeout(20000);
  const fixtures = new Map(), trips = [], errors = [];
  let aiCalls = 0;
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error' && /ErrorBoundary|TypeError|ReferenceError/.test(message.text())) errors.push(message.text());
  });
  async function api(name, data) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data: {...data, workspace_key}});
    const payload = await response.json();
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  }
  const fulfilled = (route, result) => route.fulfill({json: {ok: true, data: {result}}});
  const map = () => page.getByRole('region', {name: 'Trip map', exact: true});
  const strip = () => map().getByRole('group', {name: 'Departure and return flights', exact: true});
  const flight = (direction, from, to) => strip().getByRole('button', {name: `${direction} flight: ${from} → ${to}`, exact: true});
  const point = (city, lat, lon) => ({city, zone: 'America/New_York', lat, lon});
  function incompleteJourney(stale) {
    return {version: 1,
      origin: stale ? point('Boston', 42.36, -71.06) : point('Detroit', 42.33, -83.05),
      return_to: stale ? point('Boston', 42.36, -71.06) : null,
      stops: [{id: 'destination', ...point('New York', 40.71, -74.01), arrival_date: '2027-01-01', departure_date: '2027-01-03'}],
      legs: stale ? [
        {id: 'old-outbound', from_id: 'origin', to_id: 'destination', mode: 'flight', before_minutes: 60, after_minutes: 30},
        {id: 'old-return', from_id: 'destination', to_id: 'return', mode: 'flight', before_minutes: 60, after_minutes: 30}
      ] : []};
  }
  function middleDayItem(trip) {
    return {id: 'middle-' + trip.id, trip_id: trip.id, title: 'Middle day museum', category: 'activity',
      date: '2027-01-02', time: '13:00', location: trip.destination, notes: 'Synthetic map test activity.',
      cost_cents: 3000, duration_minutes: 90, reference: '', done: false, paid: false, fixed: false, protected: false,
      journey: {stop_id: 'destination', zone: 'America/New_York', end_zone: 'America/New_York',
        leg_id: '', arrival_date: '2027-01-02', arrival_time: '14:30'}};
  }
  async function select(index) {
    const trip = trips[index];
    await page.locator('.trip-card').filter({hasText: trip.title}).click();
    await page.getByRole('heading', {name: trip.title, exact: true}).waitFor();
    await page.getByRole('button', {name: 'AI planner', exact: true}).click();
    await strip().waitFor();
  }
  async function closeDetails() {
    const close = map().getByRole('button', {name: 'Close map details', exact: true});
    if (await close.count()) await close.click();
  }
  async function assertRoundTrip(index, returning, mapped = true) {
    const trip = trips[index];
    const outbound = flight('Departure', trip.departure_location, trip.destination);
    const inbound = flight('Return', trip.destination, returning);
    await outbound.waitFor(); await inbound.waitFor();
    assert.equal(await outbound.getAttribute('data-estimated'), 'true');
    assert.equal(await inbound.getAttribute('data-estimated'), 'true');
    assert((await outbound.innerText()).includes('Estimated flight'));
    assert((await inbound.innerText()).includes('Estimated flight'));
    assert.equal(await map().locator('.planning-plane, animateMotion').count(), 0);
    if (mapped) {
      await map().getByRole('button', {name: 'Explore ' + trip.departure_location, exact: true}).waitFor();
      await map().getByRole('button', {name: 'Explore ' + returning, exact: true}).waitFor();
      assert(await map().locator('.map-route-hit').count() >= 2, 'The geographic map should draw both flight routes');
    }
    for (const control of [outbound, inbound]) {
      await control.click();
      const popup = map().getByRole('dialog');
      await popup.waitFor();
      assert.match(await popup.innerText(), /estimat|unverified|not.*confirm/i);
      assert.equal(await popup.getByRole('link', {name: 'View flight source ↗', exact: true}).count(), 0,
        'Estimated flights must not invent a flight listing');
      await closeDetails();
    }
  }
  try {
    const suffix = Date.now().toString(36);
    const cases = [
      ['Empty route', 'Detroit', 'New York', 'Detroit', null],
      ['Missing return', 'Detroit', 'New York', 'Chicago', incompleteJourney(false)],
      ['Stale endpoints', 'Detroit', 'New York', 'Chicago', incompleteJourney(true)],
      ['Unmapped endpoints', 'Unlisted Departure', 'Unlisted Destination', 'Unlisted Return', null],
      ['Default return', 'Detroit', 'New York', '', null]
    ];
    for (const [title, departure, destination, returning, journey] of cases) {
      const trip = await api('save_trip', {title: title + ' ' + suffix, destination, departure_location: departure,
        return_location: returning, start_date: '2027-01-01', end_date: '2027-01-03', budget: '5000'});
      trips.push(trip);
      fixtures.set(trip.id, {journey, items: journey ? [middleDayItem(trip)] : []});
    }
    for (const name of ['journey_state', 'load_trip_map', 'list_items']) {
      await page.route('**/function/' + name, route => {
        const fixture = fixtures.get(route.request().postDataJSON().trip_id);
        if (!fixture) return route.continue();
        const result = name === 'list_items' ? fixture.items : name === 'journey_state'
          ? {journey: fixture.journey, version: 1, issues: []}
          : {journey: fixture.journey, trip_version: 1, pins: {}, routes: {}, location_points: {}, flights: {}, dependencies: [], risks: [], plans: []};
        return fulfilled(route, result);
      });
    }
    await page.route('**/function/search_map_places', route => fulfilled(route, []));
    await page.route('**/function/assistant_chat', route => { aiCalls++; return route.abort(); });
    await page.goto(appUrl);
    await select(0); await assertRoundTrip(0, 'Detroit');
    assert((await map().getByRole('button', {name: 'Explore Detroit', exact: true}).innerText()).includes('Departure & return'));

    await select(1); await assertRoundTrip(1, 'Chicago');
    assert((await map().getByRole('button', {name: 'Explore Detroit', exact: true}).innerText()).includes('Departure'));
    assert((await map().getByRole('button', {name: 'Explore Chicago', exact: true}).innerText()).includes('Return'));
    await page.getByRole('group', {name: 'Map days', exact: true}).getByRole('button', {name: 'Map day 2027-01-02', exact: true}).click();
    await assertRoundTrip(1, 'Chicago');

    await select(2); await assertRoundTrip(2, 'Chicago');
    assert.equal(await map().getByRole('button', {name: 'Explore Boston', exact: true}).count(), 0,
      'Stale route endpoints must not replace the trip\'s current saved departure and return');

    await select(3); await assertRoundTrip(3, 'Unlisted Return', false);
    assert.equal(await map().locator('.map-route-hit').count(), 0, 'Unknown locations must not get fabricated map coordinates');
    await page.setViewportSize({width: 390, height: 844});
    await assertRoundTrip(3, 'Unlisted Return', false);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Endpoint flight controls must fit on mobile');
    await map().screenshot({path: '/tmp/roam-round-trip-map-mobile.png', animations: 'disabled'});
    await page.setViewportSize({width: 1440, height: 1000});

    await select(4); await assertRoundTrip(4, 'Detroit');
    for (const trip of trips) {
      assert.deepEqual(await api('list_items', {trip_id: trip.id}), [], 'Map fallback flights must not write itinerary items');
      assert.equal((await api('journey_state', {trip_id: trip.id})).journey, null, 'Map fallbacks must not alter the saved journey');
    }
    assert.equal(aiCalls, 0, 'Displaying missing flights should require no AI request');
    assert.deepEqual(errors, []);
    console.log('Passed: estimated departure/return flights for empty, incomplete, stale and unmapped routes, separate return city, day filters, mobile controls, and no writes or AI calls.');
  } catch (error) {
    if (errors.length) console.error('Browser render errors:', errors);
    throw error;
  } finally {
    for (const trip of trips) await api('delete_trip', {trip_id: trip.id});
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
