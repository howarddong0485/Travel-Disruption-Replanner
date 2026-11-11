/** Exercise the real map, plan review and persisted route metadata in a disposable local app. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const path = require('node:path');

const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';
const screenshots = process.env.TRAVEL_MAP_SCREENSHOTS;

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL});
  const page = await browser.newPage({viewport: {width: 1440, height: 960}});
  page.setDefaultTimeout(12000);
  const errors = [];
  const trips = [];
  page.on('pageerror', error => { errors.push(error.message); console.error(error.stack); });
  async function api(name, data, invalid = false) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data});
    const payload = await response.json();
    if (invalid) {
      assert(!response.ok() || !payload.ok, JSON.stringify(payload));
      return;
    }
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  }
  async function screenshot(file) {
    if (screenshots) await page.screenshot({path: path.join(screenshots, file), animations: 'disabled'});
  }
  async function savedItems(trip_id) {
    return (await api('list_items', {trip_id})).map(({_jac_id, ...item}) => item);
  }

  try {
    await page.goto(appUrl);
    const created = page.waitForResponse(r => r.ok() && r.url().endsWith('/function/create_planning_demo'));
    await page.getByRole('button', {name: /Explore a sample trip map/}).click();
    const activeTrip = {id: (await (await created).json()).data.result.trip_id};
    trips.push(activeTrip.id);
    await page.getByRole('heading', {name: 'Boston weekend map sample'}).waitFor();
    const before = await savedItems(activeTrip.id);
    const flight = before.find(item => item.title === 'Chicago to Boston flight');
    assert(flight);
    const map = page.getByRole('region', {name: 'Trip map'});
    const views = page.getByRole('group', {name: 'Itinerary view'});
    const mapView = views.getByRole('button', {name: 'Map', exact: true});
    const listView = views.getByRole('button', {name: 'List', exact: true});
    const plane = map.getByRole('button', {name: 'Flight route: Chicago to Boston flight'});
    const city = map.getByRole('button', {name: 'Explore Boston'});
    await plane.waitFor();
    assert.equal(await plane.getAttribute('data-tone'), 'disruption');
    assert.equal(await city.getAttribute('data-tone'), 'disruption');
    await listView.click();
    await map.waitFor({state: 'hidden'});
    await page.getByRole('region', {name: 'Trip summary'}).waitFor();
    await page.getByRole('region', {name: 'Places in Boston'}).waitFor();
    await page.reload();
    await listView.waitFor();
    assert.equal(await listView.getAttribute('aria-pressed'), 'true');
    await mapView.click();
    await plane.waitFor();
    await screenshot('map-overview.png');
    await plane.click();
    const flightPopup = map.getByRole('dialog', {name: flight.title});
    await flightPopup.getByText('Planned path · approximate').waitFor();
    assert.match(await flightPopup.locator('.map-endpoints').innerText(), /Chicago.*Boston/s);
    await flightPopup.getByText('Sample flight delay · 20 minutes').waitFor();
    await screenshot('map-flight.png');
    await flightPopup.getByRole('button', {name: 'Plan B', exact: true}).click();
    await flightPopup.locator('.map-alert-row').filter({hasText: 'Sample flight delay'}).getByRole('button', {name: /Review alternatives/}).click();

    const review = page.getByRole('complementary', {name: 'Impact and alternatives'});
    const run = page.waitForResponse(r => r.ok() && r.url().endsWith('/function/generate_backup_plans'));
    await review.getByRole('button', {name: 'Find alternatives', exact: true}).click();
    const result = (await (await run).json()).data.result;
    assert(result.plans.some(plan => plan.selectable), JSON.stringify(result.rejections.map(r => r.checks)));
    assert(result.plans.every(plan => plan.replacements.filter(change => change.replaces_id === flight.id)
      .every(change => change.action === 'reschedule' && change.item.title === flight.title)));
    await review.getByRole('radio').first().waitFor();
    await map.locator('.map-route-pin[data-tone=preview]').waitFor();
    assert.deepEqual(await savedItems(activeTrip.id), before);
    const selection = review.locator('input[type="radio"]:checked');
    const selectedOption = await selection.inputValue();
    await listView.click();
    await map.waitFor({state: 'hidden'});
    assert.equal(await selection.inputValue(), selectedOption);
    const flightRow = page.locator('#itinerary-stop-' + flight.id);
    assert.equal(await flightRow.getAttribute('data-proposed'), 'true');
    const timelineBox = await page.locator('.plan-card').boundingBox();
    const reviewBox = await review.boundingBox();
    assert(reviewBox.x >= timelineBox.x + timelineBox.width);
    await screenshot('list-preview.png');
    await mapView.click();
    await map.locator('.map-route-pin[data-tone=preview]').waitFor();
    assert.equal(await selection.inputValue(), selectedOption);
    assert.deepEqual(await savedItems(activeTrip.id), before);
    await screenshot('map-preview.png');

    await review.getByRole('button', {name: 'Close review'}).click();
    await city.click();
    const cityPopup = map.getByRole('dialog', {name: 'Boston'});
    await cityPopup.getByRole('button', {name: /Outdoor garden visit/}).waitFor();
    await cityPopup.getByRole('button', {name: /^Plan B/}).click();
    const savedOption = cityPopup.getByRole('button', {name: /Move Chicago to Boston flight/});
    await savedOption.first().waitFor();
    await map.evaluate(element => element.scrollIntoView({block: 'start'}));
    await screenshot('map-city-plan-b.png');
    await savedOption.first().click();
    await review.getByText('Review your saved alternatives.').waitFor();
    assert.deepEqual(await savedItems(activeTrip.id), before);

    await page.setViewportSize({width: 390, height: 844});
    await review.getByRole('button', {name: 'Details', exact: true}).click();
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await screenshot('map-mobile-review.png');
    await review.getByRole('button', {name: 'Confirm and save revision'}).click();
    await page.getByRole('status').filter({hasText: /Validated backup applied/}).waitFor();
    const after = await savedItems(activeTrip.id);
    const revised = after.find(item => item.id === flight.id);
    assert.equal(revised.title, flight.title);
    assert.notEqual(revised.time, flight.time);
    await map.locator('.map-route-pin[data-tone=planned]').waitFor();
    await page.setViewportSize({width: 1440, height: 960});

    const regular = await api('save_trip', {title: 'Map route editing test', destination: 'Seattle',
      start_date: '2026-12-10', end_date: '2026-12-11', budget: '300'});
    trips.push(regular.id);
    const item = await api('save_item', {trip_id: regular.id, title: 'Flight to Seattle', category: 'transport',
      date: '2026-12-10', time: '10:00', location: 'Seattle-Tacoma International Airport'});
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).click();
    await page.locator('.trip-card').filter({hasText: regular.title}).click();
    await map.getByRole('button', {name: 'Map details', exact: true}).click();
    await map.getByRole('dialog', {name: 'Map details'}).getByRole('button', {name: /Flight to Seattle/}).click();
    const edit = map.getByRole('dialog', {name: item.title});
    await edit.getByRole('button', {name: 'Add route', exact: true}).click();
    await edit.getByLabel('From city or airport').fill('Chicago');
    await edit.getByLabel('To city or airport').fill('Seattle');
    const version = (await api('load_trip_map', {trip_id: regular.id})).trip_version;
    await edit.getByRole('button', {name: 'Save route', exact: true}).click();
    await map.getByRole('button', {name: 'Flight route: Flight to Seattle'}).waitFor();
    await edit.getByText('Planned path · approximate').waitFor();
    const state = await api('load_trip_map', {trip_id: regular.id});
    assert.equal(state.routes[item.id].route.from.label, 'Chicago');
    assert.equal(state.trip_version, version);
    await api('save_trip_map_route', {trip_id: regular.id, item_id: item.id, title: item.title,
      location: item.location, expected_revision: 0, payload: null}, true);
    await api('save_trip_map_route', {trip_id: regular.id, item_id: item.id, title: item.title,
      location: item.location, expected_revision: 1, payload: {kind:'flight',
        from:{label:'Invalid',lat:91,lon:0}, to:{label:'Seattle',lat:47.61,lon:-122.33}}}, true);
    await page.keyboard.press('Escape');
    await edit.waitFor({state: 'hidden'});
    await map.getByRole('button', {name: 'Zoom in', exact: true}).click();
    await map.getByRole('button', {name: 'Fit all trip points', exact: true}).click();
    await api('save_item', {trip_id: regular.id, item_id: item.id, title: 'Different flight', category: 'transport',
      date: item.date, time: item.time, location: item.location});
    const changed = await api('load_trip_map', {trip_id: regular.id});
    assert.equal(changed.routes[item.id].route, null);
    assert.deepEqual(errors, []);
    console.log('PASS: interactive city/route popovers, red disruptions, saved Plan B preview and acceptance, mobile sheet and route editing');
  } catch (error) {
    await screenshot('map-test-failure.png').catch(() => {});
    throw error;
  } finally {
    for (const trip_id of trips) await api('delete_trip', {trip_id});
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
