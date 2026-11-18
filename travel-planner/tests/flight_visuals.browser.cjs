/** Static flight-route design checks with synthetic trips; never requests AI. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const appUrl = process.env.TRAVEL_APP_URL || 'http://127.0.0.1:8379';
const apiUrl = process.env.TRAVEL_API_URL || appUrl + '/api/server';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  page.setDefaultTimeout(20000);
  const trips = [], errors = [];
  let aiCalls = 0;
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error' && /ErrorBoundary|TypeError|ReferenceError/.test(message.text())) errors.push(message.text());
  });
  async function api(name, data) {
    const response = await page.request.post(apiUrl + '/function/' + name, {data});
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
  async function select(title) {
    await page.locator('.trip-card').filter({hasText: title}).click();
    await marker('Departure').waitFor();
    await marker('Return').waitFor();
  }
  async function assertLayout(estimated) {
    await page.waitForFunction(value => {
      const markers = Array.from(document.querySelectorAll('.map-route-pin[data-direction="Departure"], .map-route-pin[data-direction="Return"]'));
      return markers.length === 2 && markers.every(marker => marker.getAttribute('data-estimated') === String(value));
    }, estimated);
    const region = await map().boundingBox();
    const outgoing = await marker('Departure').boundingBox();
    const returning = await marker('Return').boundingBox();
    for (const box of [outgoing, returning]) {
      assert(box && Number.isFinite(box.x) && Number.isFinite(box.y), 'Flight markers must have valid screen positions');
      assert(box.x >= region.x && box.x + box.width <= region.x + region.width + 1, 'Flight markers must fit across the map');
      assert(box.y >= region.y && box.y + box.height <= region.y + region.height + 1, 'Flight markers must fit vertically');
    }
    const separation = Math.hypot(outgoing.x + outgoing.width / 2 - returning.x - returning.width / 2,
      outgoing.y + outgoing.height / 2 - returning.y - returning.height / 2);
    assert(separation > 32, 'Outbound and return flight markers must remain separately clickable');
    assert.equal(await marker('Departure').getAttribute('data-estimated'), String(estimated));
    assert.equal(await marker('Return').getAttribute('data-estimated'), String(estimated));
    assert.equal(await map().locator('animateMotion, .planning-plane').count(), 0, 'Flight routes must stay static');
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Map layout must not overflow the screen');
  }
  async function clickCurve(title) {
    const path = map().getByLabel('Open route ' + title, {exact: true});
    await path.waitFor();
    await map().scrollIntoViewIfNeeded();
    const point = await path.evaluate(el => {
      for (const fraction of [0.25, 0.7, 0.15, 0.85]) {
        const position = el.getPointAtLength(el.getTotalLength() * fraction);
        const screen = new DOMPoint(position.x, position.y).matrixTransform(el.getScreenCTM());
        if (document.elementFromPoint(screen.x, screen.y) === el) return {x: screen.x, y: screen.y};
      }
      return null;
    });
    assert(point, 'The flight curve must have an unobstructed click target');
    await page.mouse.click(point.x, point.y);
    await map().getByRole('dialog', {name: title, exact: true}).waitFor();
  }
  async function shot(name) {
    await closeDetails();
    await map().screenshot({path: '/tmp/roam-flight-design-' + name + '.png', animations: 'disabled'});
  }
  try {
    const suffix = Date.now().toString(36);
    for (const destination of ['New York', 'Miami']) {
      trips.push(await api('save_trip', {title: 'Flight design ' + destination + ' ' + suffix,
        destination, departure_location: 'Detroit', return_location: 'Detroit',
        start_date: '2027-01-01', end_date: '2027-01-03', budget: '5000'}));
    }
    await page.route('**/function/assistant_chat', route => { aiCalls++; return route.abort(); });
    await page.goto(appUrl);

    await select(trips[0].title);
    await assertLayout(true);
    const outgoingColor = await marker('Departure').evaluate(el => getComputedStyle(el).color);
    const returnColor = await marker('Return').evaluate(el => getComputedStyle(el).color);
    assert.notEqual(outgoingColor, returnColor, 'Outbound and return markers should use distinct visual colors');
    await clickCurve('Detroit → New York');
    assert.match(await map().getByRole('dialog').innerText(), /estimat|illustrative|unverified/i);
    await closeDetails();
    await map().getByRole('button', {name: 'Explore New York', exact: true}).click();
    await map().getByRole('dialog', {name: 'New York', exact: true}).waitFor();
    await shot('estimated-desktop');
    await page.setViewportSize({width: 390, height: 844});
    await assertLayout(true);
    await marker('Return').click();
    await map().getByRole('dialog', {name: 'New York → Detroit', exact: true}).waitFor();
    await shot('estimated-mobile');

    await page.setViewportSize({width: 1440, height: 1000});
    await select(trips[1].title);
    await assertLayout(true);
    // North/south travel used to have both arcs sitting on the same vertical line.
    const outgoing = await marker('Departure').boundingBox(), returning = await marker('Return').boundingBox();
    assert(Math.abs(outgoing.x - returning.x) > 24, 'North/south flight directions should separate horizontally');
    await marker('Departure').focus();
    await page.keyboard.press('Enter');
    await map().getByRole('dialog', {name: 'Detroit → Miami', exact: true}).waitFor();
    await shot('north-south-desktop');

    await select('Flight map browser regression');
    await assertLayout(false);
    await marker('Departure').click();
    await map().getByRole('dialog').getByText('Fixture Air · QA101', {exact: true}).waitFor();
    await shot('sourced-desktop');
    await page.setViewportSize({width: 390, height: 844});
    await assertLayout(false);
    await marker('Return').click();
    await map().getByRole('dialog').getByText('Fixture Air · QA102', {exact: true}).waitFor();
    await shot('sourced-mobile');

    assert.equal(aiCalls, 0, 'Viewing flight routes must not make an AI request');
    assert.deepEqual(errors, []);
    console.log('Passed: static flight route design, distinct outbound/return colors, clickable curves/cities, separated north/south routes, sourced flights, keyboard access, and desktop/mobile layouts.');
  } catch (error) {
    if (errors.length) console.error('Browser render errors:', errors);
    throw error;
  } finally {
    for (const trip of trips) await api('delete_trip', {trip_id: trip.id});
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
