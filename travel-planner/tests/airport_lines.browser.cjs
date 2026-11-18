/** Actual airport-label regression: visible map lines without AI or flight listings. */
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
  const trips = [], journeys = new Map(), draftStates = new Map(), mapRequests = [], errors = [], mutations = [];
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
  const map = () => page.getByRole('region', {name: 'Trip map', exact: true});
  const marker = direction => map().locator('.map-route-pin[data-direction="' + direction + '"]');
  async function closeDetails() {
    const close = map().getByRole('button', {name: 'Close map details', exact: true});
    if (await close.count()) await close.click();
  }
  async function assertPaintedFlights() {
    await page.waitForFunction(() => document.querySelectorAll('.trip-map .map-route-hit').length === 2);
    for (const direction of ['Departure', 'Return']) {
      await marker(direction).waitFor();
      assert.equal(await marker(direction).getAttribute('data-estimated'), 'true');
      const path = map().locator('.map-route-hit[data-direction="' + direction + '"]');
      assert(!/NaN|Infinity|undefined/.test(await path.getAttribute('d')), 'Route path must have finite coordinates');
      // Leaflet routes have a visible SVG stroke plus a wider transparent hit target.
      const visible = map().locator('.map-route-line[data-direction="' + direction + '"]');
      await visible.waitFor();
      assert.equal(await visible.getAttribute('d'), await path.getAttribute('d'));
      assert(await visible.evaluate(p => p.getTotalLength() > 20 &&
        getComputedStyle(p).stroke !== 'none' && Number(getComputedStyle(p).strokeWidth.replace('px', '')) > 2));
    }
    assert.equal(await map().locator('animateMotion, .planning-plane').count(), 0);
  }
  async function select(index) {
    const trip = trips[index];
    await page.locator('.trip-card').filter({hasText: trip.title}).click();
    await page.getByRole('heading', {name: trip.title, exact: true}).waitFor();
    await map().waitFor();
    if (draftStates.has(trip.id)) {
      await page.getByRole('button', {name: 'AI planner', exact: true}).click();
      await page.waitForFunction(() => document.querySelector('.trip-map')?.getAttribute('data-source') === 'draft');
    }
    await assertPaintedFlights();
  }
  try {
    const suffix = Date.now().toString(36);
    for (const [departure, destination, savedRoute] of [
      ['DTW', 'New York City, New York', false],
      ['DTW', 'Kyoto, Japan', true],
      ['dtw', 'New York City, New York', false],
      ['Detroit (DTW)', 'Kyoto, Japan', false],
      ['DTW', 'New York City, New York', false],
      ['DTW', 'New York City, New York', false]
    ]) {
      const trip = await api('save_trip', {title: 'Airport line ' + trips.length + ' ' + suffix,
        destination, departure_location: departure, return_location: departure,
        start_date: '2027-01-01', end_date: '2027-01-03', budget: '5000'});
      trips.push(trip);
      if (savedRoute) {
        const endpoint = {city: departure, zone: 'UTC', lat: null, lon: null};
        journeys.set(trip.id, {version: 1, origin: {...endpoint}, return_to: {...endpoint},
          stops: [{id: 'destination', city: destination, zone: 'UTC', lat: null, lon: null,
            arrival_date: trip.start_date, departure_date: trip.end_date}],
          legs: [
            {id: 'origin:destination', from_id: 'origin', to_id: 'destination', mode: 'flight', before_minutes: 60, after_minutes: 30},
            {id: 'destination:return', from_id: 'destination', to_id: 'return', mode: 'flight', before_minutes: 60, after_minutes: 30}
          ]});
      }
      const initial = await api('load_trip_map', {trip_id: trip.id});
      assert.equal(Object.keys(initial.flights || {}).length, 0, 'Fixtures must have no researched flight listing');
      const point = initial.location_points?.[departure];
      assert(point && point.lat > 42 && point.lat < 43 && point.lon < -82 && point.lon > -84,
        'Backend should recognize DTW labels as Detroit airport coordinates');
    }
    // The draft introduces an airport name absent from both the saved trip and saved route.
    const draftTrip = trips[4], endpoint = {city: 'DTW', zone: 'America/Detroit', lat: null, lon: null};
    const draftJourney = {version: 1, origin: {...endpoint}, return_to: {...endpoint},
      stops: [{id: 'destination', city: 'LGA', zone: 'America/New_York', lat: null, lon: null,
        arrival_date: draftTrip.start_date, departure_date: draftTrip.end_date}],
      legs: [
        {id: 'origin:destination', from_id: 'origin', to_id: 'destination', mode: 'flight', before_minutes: 60, after_minutes: 30},
        {id: 'destination:return', from_id: 'destination', to_id: 'return', mode: 'flight', before_minutes: 60, after_minutes: 30}
      ]};
    const proposed = (id, title, date, time, category, detail, cost_cents) => ({item_id: '', before: null, price_unknown: false,
      after: {id, trip_id: draftTrip.id, title, date, time, category, location: category === 'transport' ? 'DTW / LGA' : 'New York',
        notes: 'Illustrative itinerary estimate; no flight listing has been verified.', reference: '', duration_minutes: 120,
        cost_cents, fixed: false, protected: false, done: false, paid: false, flight: {},
        journey: {zone: 'America/New_York', end_zone: 'America/New_York', ...detail}}});
    const draft = {id: 'airport-draft-' + suffix, status: 'pending', expires: new Date(Date.now() + 1800000).toISOString(),
      title: 'New York via LaGuardia', summary: 'Synthetic estimated round trip with a newly proposed airport.', mode: 'plan',
      relaxed: true, journey: draftJourney, trip_before: draftTrip, trip_after: draftTrip, trip_changes: {}, trip_edits: [],
      original_total_cents: 0, total_cents: 42000, reserve_cents: 0, checks: [], issues: [], warnings: [], can_apply: true,
      changes: [
        proposed('airport-outbound', 'Estimated outbound flight', draftTrip.start_date, '08:00', 'transport',
          {leg_id: 'origin:destination', arrival_date: draftTrip.start_date, arrival_time: '10:00', mode: 'flight'}, 20000),
        proposed('airport-activity', 'Museum visit', '2027-01-02', '13:00', 'activity',
          {stop_id: 'destination', arrival_date: '2027-01-02', arrival_time: '15:00'}, 2000),
        proposed('airport-return', 'Estimated return flight', draftTrip.end_date, '18:00', 'transport',
          {leg_id: 'destination:return', arrival_date: draftTrip.end_date, arrival_time: '20:00', mode: 'flight'}, 20000)
      ]};
    draftStates.set(draftTrip.id, {...await api('assistant_state', {trip_id: draftTrip.id}), pending: false,
      config: {configured: true}, drafts: [draft]});
    // A trip-only draft moves departure and return to ORD; the map must preview the proposed endpoints.
    const movedTrip = trips[5], movedAfter = {...movedTrip, departure_location: 'ORD', return_location: 'ORD'};
    draftStates.set(movedTrip.id, {...await api('assistant_state', {trip_id: movedTrip.id}), pending: false,
      config: {configured: true}, drafts: [{...draft, id: 'airport-moved-' + suffix, title: 'Leave from Chicago O\'Hare',
        journey: null, trip_before: movedTrip, trip_after: movedAfter,
        trip_changes: {departure_location: 'ORD', return_location: 'ORD'}, changes: [], total_cents: 0}]});
    const movedPreview = await api('load_trip_map', {trip_id: movedTrip.id, preview_trip: movedAfter});
    assert(movedPreview.location_points?.ORD?.lat > 41 && movedPreview.location_points.ORD.lon < -87,
      'The real backend must resolve airport labels introduced only by draft trip changes');
    const preview = await api('load_trip_map', {trip_id: draftTrip.id, preview_journey: draftJourney});
    assert(preview.location_points?.LGA?.lat > 40 && preview.location_points.LGA.lon < -73,
      'The real backend must resolve airport labels introduced only in a draft');
    await page.route('**/function/assistant_state', route => {
      const state = draftStates.get(route.request().postDataJSON().trip_id);
      return state ? route.fulfill({json: {ok: true, data: {result: state}}}) : route.continue();
    });
    await page.route('**/function/journey_state', route => {
      const journey = journeys.get(route.request().postDataJSON().trip_id);
      if (!journey) return route.continue();
      return route.fulfill({json: {ok: true, data: {result: {journey, version: 1, issues: []}}}});
    });
    await page.route('**/function/assistant_chat', route => { aiCalls++; return route.abort(); });
    page.on('request', request => {
      const name = request.url().split('/function/')[1];
      if (name === 'load_trip_map') mapRequests.push(request.postDataJSON());
      if (name && /^(save_|delete_|assistant_review|assistant_update|assistant_save)/.test(name)) mutations.push(name);
    });
    await page.goto(appUrl);
    for (let index = 0; index < trips.length; index++) {
      await select(index);
      const trip = trips[index];
      const shown = draftStates.get(trip.id)?.drafts[0].trip_after || trip;
      const mappedDestination = draftStates.get(trip.id)?.drafts[0].journey ? 'LGA' : shown.destination;
      for (const [direction, from, to] of [
        ['Departure', shown.departure_location, mappedDestination],
        ['Return', mappedDestination, shown.return_location]
      ]) {
        await map().getByRole('button', {name: direction + ' flight: ' + from + ' → ' + to, exact: true}).click();
        const popup = map().getByRole('dialog');
        await popup.waitFor();
        assert.match(await popup.innerText(), /estimated|illustrative|unverified/i);
        assert.equal(await popup.getByRole('link', {name: 'View flight source ↗', exact: true}).count(), 0);
        await closeDetails();
        await marker(direction).click();
        await popup.waitFor();
        await closeDetails();
      }
      if (index === 0) {
        await map().screenshot({path: '/tmp/roam-dtw-flight-lines.png', animations: 'disabled'});
        await page.setViewportSize({width: 390, height: 844});
        await assertPaintedFlights();
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
        await page.setViewportSize({width: 1440, height: 1000});
      }
    }
    assert(mapRequests.some(request => request.trip_id === draftTrip.id &&
      request.preview_journey?.stops?.some(stop => stop.city === 'LGA')),
      'The map must ask the backend to resolve newly proposed airport labels');
    assert(mapRequests.some(request => request.trip_id === trips[5].id && request.preview_trip?.departure_location === 'ORD'),
      'The map must ask the backend to resolve airports from proposed trip changes');
    assert.equal(aiCalls, 0, 'Airport coordinate resolution must not trigger AI');
    assert.deepEqual(mutations, [], 'Reading maps must not write itinerary, journey or AI data');
    for (const trip of trips) {
      assert.deepEqual(await api('list_items', {trip_id: trip.id}), []);
      assert.equal((await api('journey_state', {trip_id: trip.id})).journey, null);
    }
    assert.deepEqual(errors, []);
    console.log('Passed: DTW/airport aliases and draft-only LGA/ORD endpoints draw both colored flight lines without searches or listings, including null-coordinate journeys, clickable details, mobile rendering and no writes.');
  } catch (error) {
    if (errors.length) console.error('Browser render errors:', errors);
    throw error;
  } finally {
    for (const trip of trips) await api('delete_trip', {trip_id: trip.id});
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
