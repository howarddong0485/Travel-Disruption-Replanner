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
  await page.route('https://photos.example.org/**', route => route.fulfill({
    contentType: 'image/png',
    body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1sAAAAASUVORK5CYII=', 'base64'),
  }));
  await page.route('https://www.openstreetmap.org/export/embed.html**',
    route => route.fulfill({contentType: 'text/html', body: '<p>Test map preview</p>'}));

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
    const originalActivity = saved.items.find(item => item.category === 'activity');
    const optional = await api('save_item', {trip_id: saved.trip_id, title: 'Hotel luggage drop',
      category: 'stay', date: originalActivity.date, time: '11:05', location: originalActivity.location, cost: '0'});
    const withOptional = await api('planning_state', {trip_id: saved.trip_id});
    withOptional.facts.items[optional.id] = {
      ...withOptional.facts.items[originalActivity.id], blocks_time: false, tags: ['indoor'],
      end: {local: originalActivity.date + 'T11:10', zone: withOptional.facts.zone},
    };
    await api('save_planning_context', {trip_id: saved.trip_id, payload: withOptional.facts,
      expected_version: withOptional.trip_version});
    const regular = await api('save_trip', {title: 'Regular review trip', destination: 'Seattle',
      start_date: '2026-12-10', end_date: '2026-12-11', budget: '300'});
    trips.push(regular.id);
    const regularFlight = await api('save_item', {trip_id: regular.id, title: 'Flight to Seattle',
      category: 'transport', date: '2026-12-10', time: '10:00', location: 'Seattle-Tacoma International Airport'});
    const dinner = await api('save_item', {trip_id: regular.id, title: 'Pike Place dinner',
      category: 'food', date: '2026-12-11', time: '18:00', location: 'Pike Place Market'});
    await api('save_place_details', {trip_id: regular.id, item_id: dinner.id, location: dinner.location,
      expected_revision: 0, payload: {latitude: 47.6097, longitude: -122.3422,
        photo_url: 'https://photos.example.org/pike.png', photo_source: 'Traveler test photo'}});

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
    const flightPopup = page.getByRole('dialog', {name: 'Details for Flight to Seattle'});
    await flightPopup.getByText(/Add coordinates/).waitFor();
    await page.keyboard.press('Escape');
    await flightPopup.waitFor({state: 'hidden'});
    await page.waitForFunction(id => document.activeElement.id === 'place-details-' + id, regularFlight.id);
    await page.getByRole('button', {name: 'Place details for Pike Place dinner'}).click();
    const dinnerPopup = page.getByRole('dialog', {name: 'Details for Pike Place dinner'});
    await dinnerPopup.getByRole('img', {name: dinner.title}).waitFor();
    assert.match(await dinnerPopup.getByTitle('Map preview for Pike Place dinner').getAttribute('src'), /marker=47.6097,-122.3422/);
    await dinnerPopup.getByText('Traveler test photo', {exact: true}).waitFor();
    await dinnerPopup.getByText('Add or edit photo and map pin', {exact: true}).click();
    await dinnerPopup.getByLabel('Photo source or photographer').fill('Updated traveler photo');
    await dinnerPopup.getByRole('button', {name: 'Save place details'}).click();
    await dinnerPopup.locator('figcaption').filter({hasText: 'Updated traveler photo'}).waitFor();
    await dinnerPopup.getByRole('button', {name: 'Show in Places'}).click();
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

    await flightActions.click();
    await page.getByRole('button', {name: 'Report a delay', exact: true}).click();
    const delayGroup = page.getByRole('group', {name: 'Quick delay', exact: true});
    await delayGroup.getByRole('button', {name: '+3 hours', exact: true}).click();
    await page.getByRole('status').filter({hasText: '1 arrangement to check'}).waitFor();
    await page.getByRole('button', {name: 'Review impact and options', exact: false}).click();
    assert.equal(await panel.getByLabel('Delay in minutes').inputValue(), '180');
    await page.keyboard.press('Escape');
    await panel.waitFor({state: 'hidden'});
    assert.deepEqual(await listItems(regular.id), regularBefore);
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
    const activity = before.find(item => item.id === originalActivity.id);
    const actions = page.getByRole('button', {name: 'Options for ' + activity.title, exact: true});
    await actions.click();
    await page.getByRole('button', {name: 'Review impact', exact: true}).click();
    await panel.getByText(activity.title, {exact: true}).waitFor();
    await panel.getByLabel('What changed?').selectOption('weather');
    const generate = panel.getByRole('button', {name: 'Report change and find alternatives'});
    const firstGenerated = page.waitForResponse(response => response.url().endsWith('/function/generate_backup_plans') && response.ok());
    await generate.click();
    const generatedPlans = (await (await firstGenerated).json()).data.result.plans;
    const choices = panel.getByRole('radio');
    await choices.nth(1).waitFor();
    assert(!/Option [1-9]/.test(await panel.locator('.review-options').innerText()));
    assert(await panel.getByText('Lowest total among ready options', {exact: true}).count());
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
    const cashInfo = panel.locator('.review-costs .evidence-trigger');
    await cashInfo.click();
    const explanation = page.getByRole('dialog', {name: 'Why confirmation is needed'});
    await explanation.getByText(/Payment timing, received refunds/).waitFor();
    await page.keyboard.press('Escape');
    await explanation.waitFor({state: 'hidden'});
    assert(await panel.isVisible());
    const startTimes = generatedPlans.map(plan => plan.replacements.find(change => change.replaces_id === activity.id).item.start.local);
    const earlyIndex = startTimes.indexOf([...startTimes].sort()[0]);
    const lateIndex = startTimes.indexOf([...startTimes].sort().at(-1));
    await choices.nth(earlyIndex).check();
    const earlyOrder = await page.locator('.itinerary-row .travel-item').evaluateAll(elements => elements.map(element => element.id));
    await choices.nth(lateIndex).check();
    const lateOrder = await page.locator('.itinerary-row .travel-item').evaluateAll(elements => elements.map(element => element.id));
    assert.notDeepEqual(earlyOrder, lateOrder);
    assert(await page.locator('.time-shift').count());

    await page.setViewportSize({width: 390, height: 844});
    await page.emulateMedia({reducedMotion: 'reduce'});
    const sheetSizes = panel.getByRole('group', {name: 'Review sheet size'});
    await sheetSizes.getByRole('button', {name: 'Summary', exact: true}).click();
    assert.equal(await panel.getAttribute('data-sheet-size'), 'peek');
    assert.equal(await panel.locator('.review-scroll').isVisible(), false);
    await sheetSizes.getByRole('button', {name: 'Details', exact: true}).click();
    assert.equal(await panel.getAttribute('data-sheet-size'), 'full');
    const handle = panel.getByRole('button', {name: 'Resize review sheet'});
    await handle.focus();
    await page.keyboard.press('Home');
    assert.equal(await panel.getAttribute('data-sheet-size'), 'peek');
    await page.keyboard.press('End');
    assert.equal(await panel.getAttribute('data-sheet-size'), 'full');
    const grip = await handle.boundingBox();
    await page.mouse.move(grip.x + grip.width / 2, grip.y + grip.height / 2);
    await page.mouse.down();
    await page.mouse.move(grip.x + grip.width / 2, grip.y + 330, {steps: 12});
    await page.mouse.up();
    assert.equal(await panel.getAttribute('data-sheet-size'), 'half');
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

    const unresolved = await api('create_planning_demo', {});
    trips.push(unresolved.trip_id);
    const unresolvedTrip = (await api('list_trips', {})).find(trip => trip.id === unresolved.trip_id);
    await api('save_trip', {trip_id: unresolved.trip_id, title: 'Unresolved policy review', destination: unresolvedTrip.destination,
      start_date: unresolvedTrip.start_date, end_date: unresolvedTrip.end_date, currency: unresolvedTrip.currency,
      budget: String(unresolvedTrip.budget_cents / 100)});
    const unresolvedState = await api('planning_state', {trip_id: unresolved.trip_id});
    unresolvedState.facts.profile.pets = [{species: 'cat', size: 'small'}];
    unresolvedState.facts.profile.requirements = unresolvedState.facts.profile.requirements
      .filter(requirement => requirement.category !== 'pet')
      .concat([{id: 'cat', category: 'pet', code: 'cat', strength: 'hard'}]);
    await api('save_planning_context', {trip_id: unresolved.trip_id, payload: unresolvedState.facts,
      expected_version: unresolvedState.trip_version});
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).click();
    const unresolvedBefore = await chooseTrip(unresolved.trip_id, 'Unresolved policy review');
    const unconfirmedActivity = unresolvedBefore.find(item => item.category === 'activity');
    await page.getByRole('button', {name: 'Options for ' + unconfirmedActivity.title}).click();
    await page.getByRole('button', {name: 'Find indoor options', exact: true}).click();
    await panel.getByRole('button', {name: 'Report change and find alternatives'}).click();
    await panel.getByRole('radio').first().waitFor();
    assert.equal(await panel.getByRole('button', {name: 'Confirm and save revision'}).isDisabled(), true);
    await panel.locator('.review-option-card .evidence-trigger').first().click();
    await explanation.getByRole('heading', {name: 'Recorded sources'}).waitFor();
    assert(await explanation.getByText(/^Checked /).count());
    assert(await explanation.getByText(/^Expires /).count());
    await explanation.getByRole('button', {name: 'Open saved trip facts'}).click();
    await page.getByRole('heading', {name: 'Alternatives for your trip'}).waitFor();
    assert.deepEqual(await listItems(unresolved.trip_id), unresolvedBefore);

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
    console.log('PASS: quick delay impact, chronological previews, descriptive options, photo/map popovers, evidence explanations, sheet snapping/drag/keyboard, stale rejection and exact confirmed application');
  } finally {
    for (const trip_id of trips) await api('delete_trip', {trip_id});
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
