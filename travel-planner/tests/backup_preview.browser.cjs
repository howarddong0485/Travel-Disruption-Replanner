/** Run against a local Roam service with a dedicated TRAVEL_DB_PATH. */
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const path = require('node:path');
const projectRequire = createRequire(path.join(__dirname, '..', '.jac', 'client', 'configs', 'package.json'));
const { chromium } = process.env.PLAYWRIGHT_MODULE
  ? require(process.env.PLAYWRIGHT_MODULE) : projectRequire('playwright');

const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';
const previewRoute = '**/function/preview_backups';

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
  const createTrip = async (suffix, destination = 'Boston') => {
    const trip = await api('save_trip', {
      title: `Backup browser ${Date.now()} ${suffix}`, destination,
      start_date: '2026-11-01', end_date: '2026-11-03', budget: '100',
    });
    trips.push(trip);
    return trip;
  };
  const selectTrip = async trip => {
    await page.getByRole('button', {name: new RegExp(trip.title)}).click();
    await page.getByLabel('Original itinerary item').waitFor();
  };
  const generate = async itemId => {
    await page.getByLabel('Original itinerary item').selectOption(itemId);
    await page.locator('.backup-panel .primary').click();
    await page.locator('.backup-option').first().waitFor();
    assert.equal(await page.locator('.backup-option').count(), 2);
  };

  try {
    const first = await createTrip('A');
    const second = await createTrip('B');
    const unsupported = await createTrip('unsupported', 'Kyoto');
    const activity = await api('save_item', {trip_id: first.id, title: 'Audit outdoor walk', date: '2026-11-02', cost: '10'});
    const dinner = await api('save_item', {trip_id: first.id, title: 'Audit dinner', category: 'food', date: '2026-11-02', cost: '20'});
    await api('save_item', {trip_id: second.id, title: 'Second trip activity', date: '2026-11-02'});
    const unsupportedItem = await api('save_item', {trip_id: unsupported.id, title: 'Unsupported location activity', date: '2026-11-02'});
    const before = await api('list_items', {trip_id: first.id});
    await page.clock.install();
    await page.goto(appUrl);
    await selectTrip(first);
    await generate(activity.id);
    assert.match(await page.locator('.backup-options').innerText(), /NEEDS FULL VALIDATION/);
    await page.getByText('mock://boston-v1/indoor-gallery', {exact: false}).waitFor();
    passed('rain preview shows two mock drafts with evidence and validation status');

    await page.setViewportSize({width: 390, height: 844});
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.setViewportSize({width: 1440, height: 1100});
    passed('backup panel fits a mobile viewport');

    await page.getByLabel('Activation scenario').selectOption('arrival_delay');
    assert.equal(await page.locator('.backup-option').count(), 0);
    assert.equal(await page.getByLabel('Original itinerary item').inputValue(), '');
    await generate(dinner.id);
    await page.getByRole('heading', {name: 'Demo late-opening bistro'}).waitFor();
    passed('scenario switch clears old state and delayed dinner renders its own drafts');

    await page.getByRole('button', {name: '↻ Refresh', exact: true}).click();
    await page.getByLabel('Original itinerary item').waitFor();
    assert.equal(await page.locator('.backup-option').count(), 0);
    assert.equal(await page.getByLabel('Original itinerary item').inputValue(), '');
    passed('workspace refresh clears the preview and selection');

    await page.getByLabel('Original itinerary item').selectOption(activity.id);
    await page.route(previewRoute, route => route.abort('failed'), {times: 1});
    await page.locator('.backup-panel .primary').click();
    await page.locator('.backup-panel [role="alert"]').waitFor();
    assert.equal(await page.locator('.backup-option').count(), 0);
    await page.unroute(previewRoute);
    passed('failed preview requests show an error without old options');

    let release;
    let signal;
    const held = new Promise(resolve => { release = resolve; });
    const intercepted = new Promise(resolve => { signal = resolve; });
    await page.route(previewRoute, async route => {
      const response = await route.fetch();
      signal();
      await held;
      await route.fulfill({response});
    }, {times: 1});
    await page.locator('.backup-panel .primary').click();
    await intercepted;
    await selectTrip(second);
    const completed = page.waitForResponse(response => response.url().endsWith('/function/preview_backups'));
    release();
    await completed;
    assert.equal(await page.locator('.backup-option').count(), 0);
    assert.equal(await page.getByLabel('Original itinerary item').inputValue(), '');
    await page.unroute(previewRoute);
    passed('a late response from another trip cannot restore old previews');

    await selectTrip(unsupported);
    await page.getByLabel('Original itinerary item').selectOption(unsupportedItem.id);
    await page.locator('.backup-panel .primary').click();
    await page.locator('.backup-disclaimer').filter({hasText: 'No matching mock inventory'}).waitFor();
    assert.equal(await page.locator('.backup-option').count(), 0);
    passed('unsupported destinations show an explicit empty state');

    await selectTrip(first);
    await generate(activity.id);
    await page.clock.fastForward(16 * 60 * 1000);
    await page.locator('.backup-option').first().waitFor({state: 'detached'});
    await page.getByRole('status').filter({hasText: 'These backup ideas have expired'}).waitFor();
    assert.equal(await page.locator('.backup-option').count(), 0);
    assert.equal(await page.locator('.backup-panel .primary').innerText(), 'Refresh mock ideas');
    await page.clock.setSystemTime(new Date());
    await page.locator('.backup-panel .primary').click();
    await page.locator('.backup-option').first().waitFor();
    assert.equal(await page.locator('.backup-option').count(), 2);
    assert.equal(await page.getByRole('status').filter({hasText: 'These backup ideas have expired'}).count(), 0);
    passed('expired evidence clears automatically and refreshing restores fresh drafts');

    // Jac allocates a response-object _jac_id on each read; SQLite item.id is stable.
    const persisted = items => items.map(({_jac_id, ...item}) => item);
    assert.deepEqual(persisted(await api('list_items', {trip_id: first.id})), persisted(before));
    assert.equal((await api('list_trips', {})).find(trip => trip.id === first.id).budget_cents, first.budget_cents);
    assert.deepEqual(errors, []);
    passed('all browser interactions preserve saved items and budget without runtime errors');
    console.log(`${checks} browser checks passed`);
  } finally {
    try {
      for (const trip of trips) await api('delete_trip', {trip_id: trip.id});
    } finally { await browser.close(); }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
