/** Run against a local Roam service with a dedicated TRAVEL_DB_PATH. */
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const path = require('node:path');
const projectRequire = createRequire(path.join(__dirname, '..', '.jac', 'client', 'configs', 'package.json'));
const { chromium } = process.env.PLAYWRIGHT_MODULE
  ? require(process.env.PLAYWRIGHT_MODULE) : projectRequire('playwright');

const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';
const previewRoute = '**/function/generate_backup_plans';

(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.TRAVEL_BROWSER_CHANNEL ? {channel: process.env.TRAVEL_BROWSER_CHANNEL} : {}),
  });
  const page = await browser.newPage({viewport: {width: 1440, height: 1100}});
  const errors = [];
  const trips = [];
  let checks = 0;
  page.on('pageerror', error => errors.push(error.message));
  const passed = name => { checks++; console.log('PASS: ' + name); };
  const api = async (name, data) => {
    const response = await page.request.post(apiUrl + '/function/' + name, {data});
    const payload = await response.json();
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  };
  const panel = page.getByRole('region', {name: 'Integrated backup plans'});
  const options = panel.locator('.backup-option');
  const findPlans = panel.getByRole('button', {name: 'Find alternative plans'});
  const selectTrip = async trip => {
    await page.getByRole('button', {name: new RegExp(trip.title)}).click();
    await page.getByRole('button', {name: 'Backup plans', exact: true}).click();
    await panel.getByLabel('What should the plans address?').waitFor();
  };
  const generate = async () => {
    await findPlans.click();
    await options.first().waitFor();
  };
  const savedItems = async trip_id => (await api('list_items', {trip_id}))
    .map(({_jac_id, ...item}) => item);

  try {
    const suffix = Date.now();
    const demos = [];
    for (const scenario of ['rain', 'arrival_delay']) {
      const state = await api('create_planning_demo', {scenario});
      const trip = (await api('list_trips', {})).find(row => row.id === state.trip_id);
      trips.push(trip);
      trip.title += ' ' + suffix;
      await api('save_trip', {trip_id: trip.id, title: trip.title, destination: trip.destination,
        start_date: trip.start_date, end_date: trip.end_date, budget: String(trip.budget_cents / 100),
        currency: trip.currency, notes: trip.notes});
      demos.push(trip);
    }
    const [first, second] = demos;
    const unsupported = await api('save_trip', {title: 'Backup empty ' + suffix, destination: 'Kyoto',
      start_date: '2026-11-01', end_date: '2026-11-03'});
    trips.push(unsupported);
    const before = await savedItems(first.id);
    await page.clock.install();
    await page.goto(appUrl);
    await selectTrip(first);
    await generate();
    assert.match(await options.first().innerText(), /Projected trip total/);
    assert.match(await panel.innerText(), /prices are simulated/i);
    passed('rain alternatives show whole-trip costs and inventory disclosure');

    await page.setViewportSize({width: 390, height: 844});
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.setViewportSize({width: 1440, height: 1100});
    passed('backup panel fits a mobile viewport');

    await panel.getByLabel('What should the plans address?').selectOption('timing');
    assert.equal(await options.count(), 0);
    await panel.getByLabel('Affected item').waitFor();
    await selectTrip(second);
    await generate();
    assert.match(await options.first().innerText(), /dinner/i);
    passed('changing the reason clears previews and arrival delay offers dinner alternatives');

    await panel.getByRole('button', {name: 'Reload trip facts'}).click();
    await options.first().waitFor({state: 'detached'});
    await page.route(previewRoute, route => route.abort(), {times: 1});
    await findPlans.click();
    await panel.getByRole('alert').waitFor();
    assert.equal(await options.count(), 0);
    await page.unroute(previewRoute);
    passed('reload and failed generation clear previous results');

    let release, signal;
    const held = new Promise(resolve => { release = resolve; });
    const intercepted = new Promise(resolve => { signal = resolve; });
    await page.route(previewRoute, async route => {
      const response = await route.fetch();
      signal();
      await held;
      await route.fulfill({response});
    }, {times: 1});
    await findPlans.click();
    await intercepted;
    await selectTrip(unsupported);
    const completed = page.waitForResponse(response => response.url().endsWith('/function/generate_backup_plans'));
    release();
    await completed;
    assert.equal(await options.count(), 0);
    assert(await findPlans.isDisabled());
    await page.unroute(previewRoute);
    passed('a late response from another trip leaves the empty trip unchanged');

    await selectTrip(first);
    await generate();
    await page.clock.fastForward(60 * 60 * 1000);
    await panel.getByRole('status').filter({hasText: 'expired'}).waitFor();
    assert.equal(await options.count(), 0);
    await page.clock.setSystemTime(new Date());
    await generate();
    assert.equal(await panel.getByRole('status').filter({hasText: 'expired'}).count(), 0);
    passed('expired proposals clear automatically and refreshed proposals have fresh status');

    assert.deepEqual(await savedItems(first.id), before);
    assert.equal((await api('list_trips', {})).find(trip => trip.id === first.id).budget_cents, first.budget_cents);
    assert.deepEqual(errors, []);
    passed('draft review preserves the itinerary and budget');
    console.log(checks + ' browser checks passed');
  } finally {
    try {
      for (const trip of trips) await api('delete_trip', {trip_id: trip.id});
    } finally { await browser.close(); }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
