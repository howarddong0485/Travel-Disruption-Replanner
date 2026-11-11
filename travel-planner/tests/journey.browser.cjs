/** Real UI + API regression; all schedules/prices are synthetic and no model is called. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const path = require('node:path');
const appUrl = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const apiUrl = process.env.TRAVEL_API_URL || 'http://localhost:8001/api/server';
const shots = process.env.TRAVEL_MAP_SCREENSHOTS;

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  page.setDefaultTimeout(15000);
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', msg => { if (msg.type() === 'error') console.error(msg.text()); });
  let trip;
  async function api(name, data) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data});
    const payload = await response.json();
    assert(response.ok() && payload.ok, JSON.stringify(payload));
    return payload.data.result;
  }
  async function screenshot(name) {
    if (shots) await page.screenshot({path: path.join(shots, name), fullPage: true, animations: 'disabled'});
  }
  const routePanel = page.getByRole('region', {name: 'Journey route', exact: true});
  try {
    trip = await api('save_trip', {title: 'Japan journey browser regression', destination: 'Tokyo',
      departure_location: 'Detroit', return_location: 'Detroit',
      start_date: '2027-01-01', end_date: '2027-01-07', budget: '8000'});
    await page.goto(appUrl);
    await page.getByRole('button', {name: /Japan journey browser regression/}).click();
    await page.getByRole('button', {name: 'Route', exact: true}).click();
    await routePanel.getByRole('button', {name: 'Set up route'}).click();
    await page.locator('#route-origin-zone').fill('America/Detroit');
    await page.locator('#route-return-zone').fill('America/Detroit');
    for (const [index, city, arrival, departure] of [[0,'Tokyo','02','04'],[1,'Kyoto','04','06'],[2,'Osaka','06','07']]) {
      if (index) await routePanel.getByRole('button', {name: 'Add city / region', exact: true}).click();
      await page.locator('#route-stop-' + index + '-city').fill(city);
      await page.locator('#route-stop-' + index + '-zone').fill('Asia/Tokyo');
      await page.getByLabel('City ' + (index + 1) + ' arrival date', {exact: true}).fill('2027-01-' + arrival);
      await page.getByLabel('City ' + (index + 1) + ' departure date', {exact: true}).fill('2027-01-' + departure);
    }
    await routePanel.getByRole('button', {name: 'Save journey route'}).click();
    await routePanel.getByText('Detroit → Tokyo → Kyoto → Osaka → Detroit', {exact: true}).waitFor();
    assert.equal(await routePanel.locator('.route-issues li').count(), 4);
    const saved = await api('journey_state', {trip_id: trip.id});
    assert.deepEqual(saved.journey.stops.map(s => s.city), ['Tokyo', 'Kyoto', 'Osaka']);
    assert.deepEqual(saved.journey.legs.map(l => l.mode), ['flight', 'train', 'train', 'flight']);
    await page.reload();
    await page.getByRole('button', {name: 'Route', exact: true}).click();
    await routePanel.getByText('Detroit → Tokyo → Kyoto → Osaka → Detroit', {exact: true}).waitFor();
    await screenshot('journey-route.png');

    const rows = [
      ['Outbound','transport','01','12:00',840,'','origin:city1','02','16:00',1000],
      ['Tokyo hotel check-in','stay','02','18:00',30,'city1','','','',400],
      ['Tokyo museum','activity','03','10:00',120,'city1','','','',30],
      ['Tokyo to Kyoto','transport','04','10:00',150,'','city1:city2','04','12:30',120],
      ['Kyoto walk','activity','04','14:00',120,'city2','','','',0],
      ['Kyoto to Osaka','transport','06','10:00',60,'','city2:city3','06','11:00',20],
      ['Osaka lunch','food','06','12:30',60,'city3','','','',25],
      ['Return','transport','07','16:00',720,'','city3:return','07','14:00',1000],
    ];
    for (const [title,category,day,time,duration_minutes,stop_id,leg_id,arrival,arrival_time,cost] of rows) {
      await api('save_item', {trip_id: trip.id, title, category, date: '2027-01-' + day, time,
        duration_minutes, cost: String(cost), notes: 'Synthetic estimate for UI regression',
        journey: {stop_id,leg_id,arrival_date: arrival ? '2027-01-' + arrival : '',arrival_time}});
    }
    assert.deepEqual((await api('journey_state', {trip_id: trip.id})).issues, []);
    await page.reload();
    await page.getByRole('button', {name: 'Itinerary', exact: true}).click();
    const map = page.getByRole('region', {name: 'Trip map', exact: true});
    for (const city of ['Detroit', 'Tokyo', 'Kyoto', 'Osaka']) await map.getByRole('button', {name: 'Explore ' + city, exact: true}).waitFor();
    await map.getByRole('button', {name: 'Flight route: Return', exact: true}).click();
    await map.getByText('Arrives 2027-01-07 14:00 · America/Detroit', {exact: true}).waitFor();
    await screenshot('journey-map.png');
    await page.keyboard.press('Escape');
    await page.getByRole('group', {name: 'Itinerary view'}).getByRole('button', {name: 'List', exact: true}).click();
    const items = await api('list_items', {trip_id: trip.id});
    const returning = items.find(i => i.title === 'Return');
    const card = page.locator('#itinerary-stop-' + returning.id);
    await card.getByRole('button', {name: 'Edit', exact: true}).click();
    assert.equal(await page.locator('#item-duration').inputValue(), '720');
    assert.equal(await page.getByLabel('Transport arrival time', {exact: true}).inputValue(), '14:00');
    assert.equal(await page.locator('#item-journey-leg option:checked').innerText(), 'Osaka → Detroit · flight');
    await page.locator('#item-notes').fill('Synthetic return; edited through the UI');
    const saving = page.waitForResponse(r => r.url().endsWith('/function/save_item'));
    await page.getByRole('button', {name: 'Save changes', exact: true}).click();
    assert((await (await saving).json()).ok);
    assert.equal((await api('list_items', {trip_id: trip.id})).find(i => i.id === returning.id).journey.arrival_time, '14:00');
    await page.setViewportSize({width: 390, height: 844});
    await page.getByRole('button', {name: 'Route', exact: true}).click();
    await routePanel.waitFor();
    await routePanel.getByRole('button', {name: 'Edit route', exact: true}).click();
    await page.locator('#route-origin-city').waitFor();
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
    await screenshot('journey-mobile.png');
    assert.deepEqual(errors, []);
    console.log('PASS: route editor, 3 cities + outbound/return, persistence, 4 map cities, cross-zone arrivals, manual edits and mobile layout');
  } catch (error) {
    await screenshot('journey-failure.png').catch(() => {});
    throw error;
  } finally {
    if (trip) await api('delete_trip', {trip_id: trip.id});
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
