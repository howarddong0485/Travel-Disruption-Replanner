/** Synthetic date-line itinerary; no live model or inventory calls. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL});
  // A browser zone different from every route zone must not change the order.
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}, timezoneId: 'Europe/Paris'});
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  async function api(name, data) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data});
    const payload = await response.json();
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  }
  let trip;
  try {
    trip = await api('save_trip', {title: 'Date-line display regression', destination: 'Tokyo',
      departure_location: 'Detroit', return_location: '', start_date: '2027-01-01', end_date: '2027-01-05'});
    const state = await api('journey_state', {trip_id: trip.id});
    await api('save_journey', {trip_id: trip.id, expected_version: state.version, payload: {
      version: 1, origin: {city: 'Detroit', zone: 'America/Detroit'}, return_to: null,
      stops: [
        {id: 'tokyo', city: 'Tokyo', zone: 'Asia/Tokyo', arrival_date: '2027-01-02', departure_date: '2027-01-04'},
        {id: 'honolulu', city: 'Honolulu', zone: 'Pacific/Honolulu', arrival_date: '2027-01-04', departure_date: '2027-01-05'},
      ],
      legs: [
        {from_id: 'origin', to_id: 'tokyo', mode: 'flight', before_minutes: 60, after_minutes: 60},
        {from_id: 'tokyo', to_id: 'honolulu', mode: 'flight', before_minutes: 60, after_minutes: 60},
      ],
    }});
    const saved = [];
    for (const [title, category, date, time, duration_minutes, journey, location] of [
      ['Outbound', 'transport', '2027-01-01', '12:00', 840, {leg_id: 'origin:tokyo', arrival_date: '2027-01-02', arrival_time: '16:00'}, 'Airport'],
      ['Tokyo museum', 'activity', '2027-01-03', '10:00', 60, {stop_id: 'tokyo'}, 'City museum'],
      ['Date-line flight', 'transport', '2027-01-04', '22:00', 420, {leg_id: 'tokyo:honolulu', arrival_date: '2027-01-04', arrival_time: '10:00'}, 'Airport'],
      ['Island lunch', 'food', '2027-01-04', '12:00', 60, {stop_id: 'honolulu'}, 'Central market'],
    ]) saved.push(await api('save_item', {trip_id: trip.id, title, category, date, time, duration_minutes, journey, location}));
    assert.deepEqual((await api('journey_state', {trip_id: trip.id})).issues, []);
    await page.goto(appUrl);
    await page.getByRole('button', {name: /Date-line display regression/}).click();
    await page.getByRole('button', {name: 'Itinerary', exact: true}).click();
    await page.getByRole('group', {name: 'Itinerary view'}).getByRole('button', {name: 'List', exact: true}).click();
    await page.locator('#itinerary-stop-' + saved[3].id).waitFor();
    assert.deepEqual(await page.locator('.itinerary-row .travel-item h3').allTextContents(),
      ['Outbound', 'Tokyo museum', 'Date-line flight', 'Island lunch']);
    const query = async locator => new URL(await locator.getAttribute('href')).searchParams.get('query');
    assert.equal(await query(page.getByRole('link', {name: /Map for Island lunch/})), 'Central market, Honolulu');
    await page.getByRole('button', {name: 'Place details for Island lunch'}).click();
    const popup = page.getByRole('dialog', {name: 'Details for Island lunch'});
    assert.equal(await query(popup.getByRole('link', {name: /Open map/})), 'Central market, Honolulu');
    await popup.getByRole('button', {name: 'Show in Places'}).click();
    assert.equal(await query(page.getByRole('region', {name: 'Places in Honolulu'}).getByRole('link', {name: /Open in Maps/})), 'Central market, Honolulu');
    assert.deepEqual(errors, []);
    console.log('PASS: UTC date-line ordering with a different browser zone and city-aware links in all three views');
  } finally {
    if (trip) await api('delete_trip', {trip_id: trip.id});
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
