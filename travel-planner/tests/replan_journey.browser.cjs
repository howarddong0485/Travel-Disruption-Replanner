/** Real UI + API regression for #63; all routes, schedules and prices are synthetic and no model is called. */
const {browserWorkspace} = require('./browser_workspace.cjs');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const path = require('node:path');
const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';
const shots = process.env.TRAVEL_MAP_SCREENSHOTS;

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  const workspace_key = await browserWorkspace(page);

  page.setDefaultTimeout(15000);
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', msg => { if (msg.type() === 'error') console.error(msg.text()); });
  let trip;
  async function api(name, data) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data: {...data, workspace_key}});
    const payload = await response.json();
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  }
  async function screenshot(name) {
    if (shots) await page.screenshot({path: path.join(shots, name), fullPage: true, animations: 'disabled'});
  }
  const city = (name) => ({city: name, zone: 'America/New_York', lat: null, lon: null});
  try {
    // The issue's route: New York → Boston → Providence → New York, all three legs by train.
    trip = await api('save_trip', {title: 'Replan train cancellation regression', destination: 'Boston',
      departure_location: 'New York', return_location: 'New York',
      start_date: '2027-02-05', end_date: '2027-02-08', budget: '2000'});
    const before = await api('journey_state', {trip_id: trip.id});
    await api('save_journey', {trip_id: trip.id, expected_version: before.version, payload: {version: 1,
      origin: city('New York'), return_to: city('New York'),
      stops: [{id: 'boston', ...city('Boston'), arrival_date: '2027-02-05', departure_date: '2027-02-07'},
        {id: 'providence', ...city('Providence'), arrival_date: '2027-02-07', departure_date: '2027-02-08'}],
      legs: [['origin', 'boston'], ['boston', 'providence'], ['providence', 'return']].map(([from_id, to_id]) =>
        ({from_id, to_id, mode: 'train', before_minutes: 30, after_minutes: 30}))}});
    const rows = [
      ['New York to Boston train', '2027-02-05', '08:00', 240, 'origin:boston', '12:00', 9000],
      ['Boston to Providence train', '2027-02-07', '10:00', 60, 'boston:providence', '11:00', 2000],
      ['Providence to New York train', '2027-02-08', '15:00', 180, 'providence:return', '18:00', 7000],
    ];
    const ids = [];
    for (const [title, date, time, duration_minutes, leg_id, arrival_time, cost] of rows) {
      ids.push((await api('save_item', {trip_id: trip.id, title, category: 'transport', date, time,
        duration_minutes, cost: String(cost / 100), notes: 'Synthetic train for UI regression',
        journey: {stop_id: '', leg_id, arrival_date: date, arrival_time}})).id);
    }
    assert.deepEqual((await api('journey_state', {trip_id: trip.id})).issues, []);
    const outbound = ids[0];

    await page.goto(appUrl);
    await page.getByRole('button', {name: /Replan train cancellation regression/}).click();
    await page.getByRole('button', {name: 'Replan', exact: true}).click();
    await page.locator('#disrupted-item').selectOption(outbound);
    await page.locator('#disruption-type').selectOption('interrupted');
    await page.getByRole('button', {name: /Generate replan options/}).click();

    // Cancellation: a specific blocker and next step, never unusable mock transport or raw RPC JSON.
    const blockers = page.locator('.replan-blockers');
    await blockers.getByRole('heading', {name: 'No replacement can be offered yet'}).waitFor();
    await blockers.getByText(/No verified replacement is available for the train from New York to Boston/).waitFor();
    await blockers.getByText(/Next step: If you were rebooked on a later departure/).waitFor();
    assert.equal(await page.locator('.backup-chip').count(), 0);
    assert.equal(await page.locator('option', {hasText: /Mock/}).count(), 0);
    assert.equal(await page.getByRole('heading', {name: 'Build your own combination'}).count(), 0);
    assert.equal(await page.locator('.proposal-card').count(), 0);
    assert.equal(await page.locator('.alert.error').filter({hasText: '{'}).count(), 0);
    await screenshot('replan-journey-blocker.png');

    // Following the next step switches the same train to the delay path, which keeps its leg.
    await blockers.getByRole('button', {name: 'Report as delayed instead'}).click();
    assert.equal(await page.locator('#disruption-type').inputValue(), 'delayed');
    assert.equal(await page.locator('#disrupted-item').inputValue(), outbound);
    await page.getByText('Enter how many minutes later your new departure leaves, then generate options.').waitFor();
    assert.equal(await blockers.count(), 0);
    await page.locator('#delay-minutes').fill('30');
    await page.getByRole('button', {name: /Generate replan options/}).click();
    const proposal = page.locator('.proposal-card').first();
    await proposal.getByText('2027-02-05 08:00 → 2027-02-05 08:30').waitFor();
    assert.equal(await page.locator('.replan-blockers').count(), 0);
    await proposal.getByRole('button', {name: 'Accept revised plan'}).click();
    await page.getByText(/Revised mock plan applied/).waitFor();

    // The accepted delay survives a reload with both local times updated.
    await page.reload();
    const moved = (await api('list_items', {trip_id: trip.id})).find(i => i.id === outbound);
    assert.equal(moved.time, '08:30');
    assert.equal(moved.journey.arrival_time, '12:30');
    assert.equal(moved.journey.leg_id, 'origin:boston');
    assert.deepEqual(errors, []);
    console.log('PASS: canceled train shows a specific blocker without mock transport, next step switches to delay, accepted delay persists');
  } catch (error) {
    await screenshot('replan-journey-failure.png').catch(() => {});
    throw error;
  } finally {
    if (trip) await api('delete_trip', {trip_id: trip.id});
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
