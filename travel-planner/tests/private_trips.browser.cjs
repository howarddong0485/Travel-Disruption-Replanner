/** Verify two ordinary browser profiles, separate tabs and a late assistant response. */
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = process.env.TRAVEL_APP_URL || 'http://localhost:8000';
const api = process.env.TRAVEL_API_URL || app + '/api/server';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const one = await browser.newContext(), two = await browser.newContext();
  const page = await one.newPage(), other = await two.newPage();
  const saved = [];
  async function call(client, key, name, args) {
    const response = await client.request.post(api + '/function/' + name, {data: {...args, workspace_key: key}});
    const envelope = await response.json();
    assert.ok(envelope.ok, name + ' failed');
    return envelope.data.result;
  }
  async function openPage(p) {
    await Promise.all([p.waitForResponse(r => r.url().endsWith('/function/list_trips') && r.ok()), p.goto(app)]);
    await p.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
    return p.evaluate(() => localStorage.getItem('jacroam.private-workspace.v1'));
  }
  async function select(p, title) {
    await p.getByRole('button', {name: new RegExp(title)}).click();
    await p.locator('.trip-card[data-active=true]').filter({hasText: title}).waitFor();
    await p.getByRole('button', {name: '↻ Refresh', exact: true}).waitFor();
  }
  try {
    await page.route('**/function/assistant_state', async route => {
      const response = await route.fetch();
      const json = await response.json();
      json.data.result.config.configured = true;
      await route.fulfill({response, json});
    });
    const [key, otherKey] = await Promise.all([openPage(page), openPage(other)]);
    assert(key && otherKey && key !== otherKey);
    const suffix = Date.now();
    for (const destination of ['Boston', 'Seattle']) {
      const trip = await call(page, key, 'save_trip', {title: destination + ' ' + suffix,
        destination, start_date: '2027-02-01', end_date: '2027-02-03'});
      saved.push({key, id: trip.id, title: trip.title});
      await call(page, key, 'save_item', {trip_id: trip.id, title: destination + ' private stop', location: destination, date: '2027-02-01'});
    }
    const [a,b] = saved;
    await page.getByRole('button', {name: '↻ Refresh', exact: true}).click();
    await select(page, a.title);
    const cities = page.getByRole('navigation', {name:'Choose a city'});
    await cities.getByRole('button',{name:'Boston',exact:true}).click();
    await page.getByLabel('Show',{exact:true}).selectOption('activity');
    await page.getByRole('button',{name:'Zoom in'}).click();
    await select(page,b.title);
    const mapState = id => page.evaluate(key => JSON.parse(sessionStorage.getItem('jacroam.map-view.' + key)), id);
    const originalView = await mapState(a.id);
    assert(originalView && originalView.zoom && originalView.city && originalView.category==='activity');
    assert.equal(await page.getByLabel('Show',{exact:true}).inputValue(), '');
    await select(page,a.title);
    await page.locator('.map-city-switcher button[aria-pressed=true]').filter({hasText:'Boston'}).waitFor();
    assert.equal(await page.getByLabel('Show',{exact:true}).inputValue(), 'activity');
    await select(page,b.title);
    const restoredView = await mapState(a.id);
    assert.equal(restoredView.zoom, originalView.zoom);
    assert(Math.abs(restoredView.center[0]-originalView.center[0]) < 0.001);
    assert(Math.abs(restoredView.center[1]-originalView.center[1]) < 0.001);
    await select(page,a.title);
    await page.getByRole('button', {name:'AI planner',exact:true}).click();
    const sidebar = page.getByRole('complementary', {name:'Travel assistant'});
    await sidebar.getByLabel('Message the travel assistant').fill('Unsent Boston note');
    await select(page,b.title);
    await page.getByRole('button',{name:'AI planner',exact:true}).click();
    assert.equal(await sidebar.getByLabel('Message the travel assistant').inputValue(),'');
    await select(page,a.title);
    await page.getByRole('button',{name:'AI planner',exact:true}).click();
    assert.equal(await sidebar.getByLabel('Message the travel assistant').inputValue(),'Unsent Boston note');
    await sidebar.getByLabel('Message the travel assistant').fill('Boston-only prompt');
    const captured = Promise.withResolvers(), release = Promise.withResolvers();
    await page.route('**/function/assistant_chat', async route => {
      const args = route.request().postDataJSON();
      captured.resolve(args.trip_id);
      await release.promise;
      await route.fulfill({json:{ok:true,data:{result:{trip_id:a.id,messages:[
        {role:'assistant',content:'Boston-only reply'}],drafts:[]}}}});
    });
    await sidebar.getByRole('button', {name:/send/i}).click();
    assert.equal(await captured.promise, a.id);
    await select(page, b.title);
    await page.getByRole('button',{name:'Replan',exact:true}).click();
    await page.getByRole('heading',{name:'Replan your trip'}).waitFor();
    release.resolve();
    await page.unrouteAll({behavior:'wait'});
    assert(!(await page.locator('main, .chat-sidebar').allTextContents()).join(' ').includes('Boston-only'));
    assert.equal(await sidebar.getByLabel('Message the travel assistant').inputValue(),'');
    assert.deepEqual((await call(page,key,'replan_state',{trip_id:b.id})).items.map(i=>i.title),['Seattle private stop']);
    const another = await one.newPage();
    assert.equal(await openPage(another),key);
    await select(another,a.title);
    await page.reload();
    await page.locator('.trip-card[data-active=true]').filter({hasText:b.title}).waitFor();
    await other.getByRole('button',{name:'↻ Refresh',exact:true}).click();
    await other.getByRole('heading',{name:'Create your first trip'}).waitFor();
    assert.deepEqual(await call(other,otherKey,'list_trips',{}),[]);
    console.log('PASS: browser ownership, tab selection, restored city, filters, camera and composer, separate replans and late chat after switching trips');
  } finally {
    try { for (const t of saved) await call(page,t.key,'delete_trip',{trip_id:t.id}); }
    finally { await browser.close(); }
  }
})().catch(err=>{ console.error(err); process.exitCode=1; });
