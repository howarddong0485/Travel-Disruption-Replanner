/** Verify one map filter per city alias and a Find on map action for an unmapped route city (issue #69). */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const api = process.env.TRAVEL_API_URL || app + '/api/server';
const PROVIDENCE = [{label: 'Providence, Providence County, Rhode Island, United States', lat: 41.824, lon: -71.4128},
  {label: 'Providence County, Rhode Island, United States', lat: 41.87, lon: -71.57}];

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const page = await (await browser.newContext({viewport: {width: 1280, height: 1000}})).newPage();
  const searches = [];
  let key = '', trip = null;
  async function call(name, args) {
    const response = await page.request.post(api + '/function/' + name, {data: {...args, workspace_key: key}});
    const envelope = await response.json();
    assert.ok(envelope.ok, name + ' failed: ' + JSON.stringify(envelope.error));
    return envelope.data.result;
  }
  async function openTrip() {
    await page.reload();
    await page.getByRole('button', {name: /Northeast loop/}).click();
    await page.locator('.trip-card[data-active=true]').filter({hasText: 'Northeast loop'}).waitFor();
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    await page.locator('.map-city-switcher').waitFor();
  }
  const cityFilters = () => page.locator('.map-city-switcher').getByRole('button');
  try {
    // No geocoder traffic. A city search finds two Providence candidates, so it is not placed automatically.
    await page.route('**/function/resolve_trip_map_places', route => route.fulfill({json: {ok: true, data: {result: {located: 0, remaining: 0}}}}));
    await page.route('**/function/search_map_places', async route => {
      const query = JSON.parse(route.request().postData()).query;
      searches.push(query);
      await route.fulfill({json: {ok: true, data: {result: query.startsWith('Providence') ? PROVIDENCE : []}}});
    });
    await page.goto(app);
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    key = await page.evaluate(() => localStorage.getItem('jacroam.private-workspace.v1'));
    trip = await call('save_trip', {title: 'Northeast loop', destination: 'Boston, MA', start_date: '2031-05-01', end_date: '2031-05-04',
      currency: 'USD', budget: '900', departure_location: 'New York', return_location: 'New York'});
    const state = await call('journey_state', {trip_id: trip.id});
    const leg = (from_id, to_id) => ({from_id, to_id, mode: 'train', before_minutes: 30, after_minutes: 30});
    await call('save_journey', {trip_id: trip.id, expected_version: state.version, payload: {version: 1,
      origin: {city: 'New York', zone: 'America/New_York'}, return_to: {city: 'New York', zone: 'America/New_York'},
      stops: [{id: 'boston', city: 'Boston, MA', zone: 'America/New_York', arrival_date: '2031-05-01', departure_date: '2031-05-03'},
        {id: 'providence', city: 'Providence, RI', zone: 'America/New_York', arrival_date: '2031-05-03', departure_date: '2031-05-04'}],
      legs: [leg('origin', 'boston'), leg('boston', 'providence'), leg('providence', 'return')]}});
    for (const [title, time] of [['Freedom Trail walk', '10:00'], ['Harbor dinner', '19:00']]) {
      await call('save_item', {trip_id: trip.id, title, category: 'activity', date: '2031-05-02', time, location: '', journey: {stop_id: 'boston'}});
    }
    await openTrip();

    const labels = await cityFilters().allInnerTexts();
    assert.equal(labels.filter(text => /^Boston/.test(text)).length, 1, 'Boston and Boston, MA share one filter: ' + labels.join(' | '));
    await cityFilters().filter({hasText: /^Boston/}).click();
    for (const title of ['Freedom Trail walk', 'Harbor dinner']) {
      await page.locator('.map-stop-card').filter({hasText: title}).waitFor();
    }

    await page.getByRole('button', {name: 'All cities'}).click();
    assert.equal(labels.filter(text => /^Providence/.test(text)).length, 0, 'an ambiguous city search is not placed automatically');
    await page.getByRole('button', {name: /location\(s\) not mapped/}).click();
    await page.getByRole('button', {name: 'Find Providence, RI on the map'}).click();
    await page.getByRole('button', {name: 'Search', exact: true}).click();
    await page.getByRole('button', {name: /^Providence, Providence County/}).click();
    await page.getByRole('button', {name: /location\(s\) not mapped/}).waitFor({state: 'detached'});

    const saved = await call('journey_state', {trip_id: trip.id});
    const providence = saved.journey.stops.find(stop => stop.id === 'providence');
    assert.deepEqual([providence.lat, providence.lon], [41.824, -71.4128]);
    assert.equal(saved.journey.legs.length, 3);
    await cityFilters().filter({hasText: /^Providence/}).waitFor();
    assert.equal((await cityFilters().allInnerTexts()).filter(text => /^Boston/.test(text)).length, 1);
    assert.ok(searches.includes('Providence, RI'));
    console.log('map city aliases: 6 checks passed');
  } finally {
    try { if (trip) await call('delete_trip', {trip_id: trip.id}); }
    finally { await browser.close(); }
  }
})().catch(error => { console.error(error); process.exit(1); });
