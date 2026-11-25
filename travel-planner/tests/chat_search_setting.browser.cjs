/** Verify the chat's Search the web choice survives trip switches and a reload with an empty composer. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const api = process.env.TRAVEL_API_URL || app + '/api/server';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const page = await (await browser.newContext()).newPage();
  const saved = [];
  let key = '';
  async function call(name, args) {
    const response = await page.request.post(api + '/function/' + name, {data: {...args, workspace_key: key}});
    const envelope = await response.json();
    assert.ok(envelope.ok, name + ' failed');
    return envelope.data.result;
  }
  async function openPage() {
    await Promise.all([page.waitForResponse(r => r.url().endsWith('/function/list_trips') && r.ok()), page.goto(app)]);
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    return page.evaluate(() => localStorage.getItem('jacroam.private-workspace.v1'));
  }
  async function select(title) {
    await page.getByRole('button', {name: new RegExp(title)}).click();
    await page.locator('.trip-card[data-active=true]').filter({hasText: title}).waitFor();
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    await page.getByRole('button', {name: 'AI planner', exact: true}).click();
  }
  const sidebar = page.getByRole('complementary', {name: 'Travel assistant'});
  const toggle = () => sidebar.getByRole('checkbox', {name: 'Search the web'});
  const composer = () => sidebar.getByLabel('Message the travel assistant');
  try {
    await page.route('**/function/assistant_state', async route => {
      const response = await route.fetch();
      const json = await response.json();
      json.data.result.config.configured = true;
      await route.fulfill({response, json});
    });
    key = await openPage();
    assert.ok(key, 'the page should create a private workspace');
    for (const title of ['Search setting A', 'Search setting B']) {
      saved.push(await call('save_trip', {title, destination: 'Boston', start_date: '2031-03-01',
        end_date: '2031-03-02', currency: 'USD', budget: '500'}));
    }
    await openPage();

    await select('Search setting A');
    assert.equal(await composer().inputValue(), '', 'the composer starts empty');
    assert.equal(await toggle().isChecked(), true, 'web search defaults to on');
    await toggle().uncheck();

    await select('Search setting B');
    assert.equal(await toggle().isChecked(), true, 'another trip keeps its own setting');

    await select('Search setting A');
    assert.equal(await composer().inputValue(), '');
    assert.equal(await toggle().isChecked(), false, 'switching back keeps web search off');

    await openPage();
    await select('Search setting A');
    assert.equal(await toggle().isChecked(), false, 'a reload keeps web search off');

    await composer().fill('Unsent note');
    await select('Search setting B');
    await select('Search setting A');
    assert.equal(await composer().inputValue(), 'Unsent note', 'unsent text is still restored');
    assert.equal(await toggle().isChecked(), false);
    await composer().fill('');
    await toggle().check();
    await openPage();
    await select('Search setting A');
    assert.equal(await toggle().isChecked(), true, 'turning web search back on is remembered too');
    console.log('chat search setting: 7 checks passed');
  } finally {
    try { for (const trip of saved) await call('delete_trip', {trip_id: trip.id}); }
    finally { await browser.close(); }
  }
})().catch(error => { console.error(error); process.exit(1); });
