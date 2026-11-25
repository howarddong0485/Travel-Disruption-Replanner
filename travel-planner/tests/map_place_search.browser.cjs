/** Verify the map's place search: no repeated city in the default query and a short message when the gateway times out. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const api = process.env.TRAVEL_API_URL || app + '/api/server';
const GATEWAY_PAGE = '<html><head><title>504 Gateway Time-out</title></head><body><center><h1>504 Gateway Time-out</h1></center><hr><center>nginx</center></body></html>';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const page = await (await browser.newContext({viewport: {width: 1280, height: 1000}})).newPage();
  const searches = [];
  let key = '', trip = null;
  async function call(name, args) {
    const response = await page.request.post(api + '/function/' + name, {data: {...args, workspace_key: key}});
    const envelope = await response.json();
    assert.ok(envelope.ok, name + ' failed');
    return envelope.data.result;
  }
  try {
    // No geocoder traffic: automatic lookups find nothing and place search answers like a timed-out gateway.
    await page.route('**/function/resolve_trip_map_places', route => route.fulfill({json: {ok: true, data: {result: {located: 0, remaining: 0}}}}));
    await page.route('**/function/search_map_places', async route => {
      searches.push(JSON.parse(route.request().postData()).query);
      await route.fulfill({status: 504, contentType: 'text/html', body: GATEWAY_PAGE});
    });
    await page.goto(app);
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    key = await page.evaluate(() => localStorage.getItem('jacroam.private-workspace.v1'));
    trip = await call('save_trip', {title: 'Place search check', destination: 'Boston, MA', start_date: '2031-03-01',
      end_date: '2031-03-02', currency: 'USD', budget: '500'});
    const address = 'Boston Public Garden, 4 Charles St, Boston, MA 02116';
    await call('save_item', {trip_id: trip.id, title: 'Garden walk', category: 'activity', date: '2031-03-01', time: '10:00', location: address});
    await page.reload();
    await page.getByRole('button', {name: /Place search check/}).click();
    await page.locator('.trip-card[data-active=true]').filter({hasText: 'Place search check'}).waitFor();
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    await page.locator('.map-stop-card').filter({hasText: 'Garden walk'}).click();

    const query = page.getByLabel('Find this place');
    assert.equal(await query.inputValue(), address, 'a complete address is not followed by its city again');
    await page.getByRole('button', {name: 'Search location'}).click();
    const error = page.locator('.map-inline-error');
    await error.waitFor();
    const message = await error.innerText();
    assert.match(message, /^Place search did not respond\. Try again/);
    assert.ok(!/[<>]|nginx|Function /.test(message), 'gateway HTML and RPC details stay hidden');
    assert.equal(await query.inputValue(), address, 'the search text stays editable for a retry');
    assert.deepEqual(searches, [address]);
    console.log('map place search: 5 checks passed');
  } finally {
    try { if (trip) await call('delete_trip', {trip_id: trip.id}); }
    finally { await browser.close(); }
  }
})().catch(error => { console.error(error); process.exit(1); });
