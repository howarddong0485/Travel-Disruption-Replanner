/** Browser regression for the saved-trip review workflow. Use a dedicated TRAVEL_DB_PATH. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  const trips = [];
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));

  async function api(name, data) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data});
    const payload = await response.json();
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  }

  async function chooseTrip(id, title) {
    await page.getByRole('button', {name: new RegExp(title)}).click();
    await page.locator('.trip-card[data-active=true]').filter({hasText: title}).waitFor();
    return listItems(id);
  }
  async function listItems(trip_id) {
    const items = await api('list_items', {trip_id});
    return items.map(({_jac_id, ...item}) => item);
  }

  try {
    const saved = await api('create_planning_demo', {});
    trips.push(saved.trip_id);
    const regular = await api('save_trip', {title: 'Regular review trip', destination: 'Seattle',
      start_date: '2026-12-10', end_date: '2026-12-11', budget: '300'});
    trips.push(regular.id);
    const regularFlight = await api('save_item', {trip_id: regular.id, title: 'Flight to Seattle',
      category: 'transport', date: '2026-12-10', time: '10:00', location: 'Seattle-Tacoma International Airport'});
    const dinner = await api('save_item', {trip_id: regular.id, title: 'Pike Place dinner',
      category: 'food', date: '2026-12-11', time: '18:00', location: 'Pike Place Market'});

    await page.goto(appUrl);
    const regularBefore = await chooseTrip(regular.id, regular.title);
    await page.getByRole('link', {name: /Map for Flight to Seattle/}).waitFor();
    const places = page.getByRole('region', {name: 'Places in Seattle'});
    await places.getByRole('button', {name: /Pike Place dinner/}).click();
    assert.equal(await page.locator('#itinerary-stop-' + dinner.id).getAttribute('data-place-selected'), 'true');
    await places.getByRole('button', {name: 'Show in itinerary'}).click();
    await page.waitForFunction(id => document.activeElement.id === 'itinerary-stop-' + id, dinner.id);
    await page.getByRole('button', {name: /Dec 11.*1 stop/}).click();
    assert.equal(await places.getByRole('button', {name: /Flight to Seattle/}).count(), 0);
    assert.equal(await page.locator('#itinerary-stop-' + regularFlight.id).count(), 0);
    assert.match(await places.getByRole('link', {name: /Open in Maps/}).getAttribute('href'), /Pike%20Place%20Market/);
    await places.getByRole('button', {name: 'Review this stop'}).click();
    const panel = page.getByRole('complementary', {name: 'Impact and alternatives'});
    assert.equal(await panel.getByLabel('Affected itinerary item').inputValue(), dinner.id);
    await page.keyboard.press('Escape');
    await panel.waitFor({state: 'hidden'});
    await page.waitForFunction(() => document.activeElement.id === 'place-review-action');
    await page.getByRole('button', {name: /All days/}).click();
    await page.getByRole('button', {name: 'Place details for Flight to Seattle'}).click();
    await page.waitForFunction(() => document.activeElement.id === 'itinerary-places-heading');
    await page.getByRole('button', {name: /Add item/}).click();
    await page.waitForFunction(() => document.activeElement.id === 'item-title');
    await page.getByRole('button', {name: 'Places', exact: false}).click();
    const flightActions = page.getByRole('button', {name: 'Options for Flight to Seattle'});
    await flightActions.focus();
    await page.keyboard.press('Enter');
    assert.equal(await page.evaluate(() => document.activeElement.textContent), 'Report a delay');
    await page.keyboard.press('Escape');
    assert.equal(await flightActions.getAttribute('aria-expanded'), 'false');
    assert.equal(await flightActions.evaluate(element => document.activeElement === element), true);

    await page.getByRole('button', {name: 'Bookings', exact: true}).click();
    await page.getByRole('button', {name: 'Review a change', exact: true}).click();
    await panel.getByLabel('Affected itinerary item').selectOption(regularFlight.id);
    await panel.getByLabel('What changed?').selectOption('timing');
    await panel.getByLabel('Delay in minutes').fill('180');
    await panel.getByRole('button', {name: 'Report change and find alternatives'}).click();
    await panel.getByRole('alert').filter({hasText: /timezone/}).waitFor();
    assert.deepEqual(await listItems(regular.id), regularBefore);
    await page.keyboard.press('Escape');
    await panel.waitFor({state: 'hidden'});
    await page.waitForFunction(() => document.activeElement.id === 'trip-actions-launch');

    const before = await chooseTrip(saved.trip_id, 'Integrated weather demo');
    const activity = before.find(item => item.category === 'activity');
    const actions = page.getByRole('button', {name: 'Options for ' + activity.title, exact: true});
    await actions.click();
    await page.getByRole('button', {name: 'Review impact', exact: true}).click();
    await panel.getByText(activity.title, {exact: true}).waitFor();
    await panel.getByLabel('What changed?').selectOption('weather');
    const generate = panel.getByRole('button', {name: 'Report change and find alternatives'});
    await generate.click();
    const choices = panel.getByRole('radio');
    await choices.nth(1).waitFor();
    assert.equal(await panel.getByLabel('What changed?').isVisible(), false);
    await panel.getByRole('button', {name: 'Edit report'}).click();
    await panel.getByLabel('What changed?').waitFor();
    await panel.getByRole('button', {name: 'Hide report'}).click();
    const beforePreview = await panel.locator('.review-diff').innerText();
    const beforeCost = await panel.locator('.review-costs').innerText();
    await choices.nth(1).check();
    assert.notEqual(await panel.locator('.review-diff').innerText(), beforePreview);
    assert.notEqual(await panel.locator('.review-costs').innerText(), beforeCost);
    assert(await page.locator('.itinerary-proposed').count());
    assert.deepEqual(await listItems(saved.trip_id), before);

    await page.setViewportSize({width: 390, height: 844});
    await page.emulateMedia({reducedMotion: 'reduce'});
    assert.equal(await panel.evaluate(element => getComputedStyle(element).position), 'fixed');
    assert.equal(await panel.evaluate(element => getComputedStyle(element).animationName), 'none');
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    const saveButton = panel.getByRole('button', {name: 'Confirm and save revision'});
    const footerBefore = await saveButton.boundingBox();
    await panel.locator('.review-scroll').evaluate(element => { element.scrollTop = element.scrollHeight; });
    const footerAfter = await saveButton.boundingBox();
    assert.equal(footerAfter.y, footerBefore.y);
    assert(footerAfter.y + footerAfter.height <= 844);

    // Change saved facts while the review is open and simulate returning to this tab.
    await api('save_item', {trip_id: saved.trip_id, title: 'New expense', category: 'expense', cost: '1'});
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await panel.getByRole('status').filter({hasText: /stale or expired/}).waitFor();
    assert.equal(await panel.getByRole('button', {name: 'Confirm and save revision'}).count(), 0);
    await panel.getByRole('button', {name: 'Reload trip impact'}).click();
    const generated = page.waitForResponse(response => response.url().endsWith('/function/generate_backup_plans') && response.ok());
    await generate.click();
    const ready = panel.getByRole('button', {name: 'Confirm and save revision'});
    await ready.waitFor();
    const revision = (await (await generated).json()).data.result.plans[0];
    await ready.click();
    await panel.waitFor({state: 'hidden'});
    await page.getByRole('status').filter({hasText: /Validated backup applied/}).waitFor();
    const after = await listItems(saved.trip_id);
    for (const change of revision.replacements) {
      const item = after.find(candidate => candidate.id === change.replaces_id);
      assert.equal(item.title, change.item.title);
      assert.equal(item.date + 'T' + item.time, change.item.start.local);
    }
    await page.waitForFunction(id => document.activeElement.id === 'itinerary-actions-' + id, activity.id);

    await page.getByRole('button', {name: 'Plan a new trip'}).click();
    await page.getByLabel('Trip name').fill('Trip brief regression');
    await page.getByLabel('Destination', {exact: true}).fill('Boston');
    await page.getByLabel('Short trip brief').fill('An accessible walk and dinner.');
    await page.getByRole('button', {name: 'Review trip brief'}).click();
    await page.getByRole('heading', {name: 'Review your trip brief'}).waitFor();
    assert(!(await api('list_trips', {})).some(trip => trip.title === 'Trip brief regression'));
    await page.getByRole('button', {name: 'Edit brief'}).click();
    await page.getByLabel('Short trip brief').fill('A museum visit and dinner.');
    await page.getByRole('button', {name: 'Review trip brief'}).click();
    await page.getByRole('button', {name: 'Confirm and create trip'}).click();
    await page.locator('.trip-card[data-active=true]').filter({hasText: 'Trip brief regression'}).waitFor();
    const created = (await api('list_trips', {})).find(trip => trip.title === 'Trip brief regression');
    trips.push(created.id);
    assert.equal(created.notes, 'A museum visit and dinner.');
    await page.getByRole('button', {name: 'Backup plans', exact: true}).click();
    await page.getByRole('heading', {name: 'Alternatives for your trip'}).waitFor();
    await page.getByRole('button', {name: 'Replan', exact: true}).click();
    await page.getByRole('heading', {name: 'Replan your trip'}).waitFor();
    await page.getByRole('button', {name: 'Try connected backup plans'}).waitFor();
    assert.deepEqual(errors, []);
    console.log('PASS: linked days and places, item and trip actions, keyboard and focus return, live schedule/cost preview, fixed mobile confirmation, stale rejection, explicit save, trip brief and existing navigation');
  } finally {
    for (const trip_id of trips) await api('delete_trip', {trip_id});
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
