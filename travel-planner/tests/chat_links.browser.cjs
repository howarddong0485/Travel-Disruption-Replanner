/** Verify chat replies show safe clickable links and labeled primary sources; never requests AI.
 * First run `jac run tests/seed_chat_links.jac` with the browser-test server's TRAVEL_DB_PATH. */
const {browserWorkspace} = require('./browser_workspace.cjs');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = process.env.TRAVEL_APP_URL || 'http://127.0.0.1:8379';

(async () => {
  const browser = await chromium.launch({channel: process.env.TRAVEL_BROWSER_CHANNEL || 'chrome'});
  const page = await browser.newPage({viewport: {width: 1440, height: 1000}});
  await browserWorkspace(page, '1baff734-c2ee-44b6-a731-580ac85eb2de');
  page.setDefaultTimeout(20000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('dialog', dialog => { errors.push('dialog: ' + dialog.message()); dialog.dismiss(); });
  let checks = 0;
  const check = (condition, message) => { assert.ok(condition, message); checks += 1; };
  try {
    await page.goto(app);
    await page.locator('.trip-card').filter({hasText: 'Chat links browser regression'}).first().click();
    await page.getByRole('button', {name: 'AI planner', exact: true}).click();
    const reply = page.locator('.chat-message.assistant').last();
    await reply.waitFor();
    const text = reply.locator('.message-text').first();
    check(await page.locator('.chat-message.user .message-text').last().innerText() === 'Official MBTA page from Logan to South Station?',
      'the traveler message without link segments is still shown');

    const cited = text.getByRole('link', {name: 'mbta.com', exact: true});
    check(await cited.getAttribute('href') === 'https://www.mbta.com/schedules/741/line?utm_source=openai', 'the Markdown citation is a link');
    check(await cited.getAttribute('target') === '_blank' && /noopener/.test(await cited.getAttribute('rel')) && /noreferrer/.test(await cited.getAttribute('rel')),
      'links open in a new tab without an opener or referrer');
    check(await cited.getAttribute('data-cited') === 'true', 'a link the search cited through a proxy copy is marked as cited');
    check(await text.getByRole('link', {name: 'https://www.mbta.com/fares', exact: true}).count() === 1, 'a bare URL is a link without its trailing period');
    const shown = await text.innerText();
    check(!shown.includes('](https://'), 'no raw Markdown link syntax is shown');
    check(shown.includes('[run](javascript:alert(1))') && shown.includes('<img src=x onerror='), 'unsafe links and markup stay visible as text');
    check(await reply.locator('img').count() === 0 && await page.title() !== 'owned', 'markup in model text is not rendered');
    const hrefs = await page.locator('.chat-sidebar a').evaluateAll(links => links.map(link => link.getAttribute('href')));
    check(hrefs.length >= 6 && hrefs.every(href => href.startsWith('https://')), 'every chat link is https: ' + hrefs.join(' '));

    const sources = reply.getByLabel('Sources').locator('.chat-source');
    check(await sources.count() === 3, 'one source per cited page');
    const proxied = sources.nth(0);
    check(await proxied.getByRole('link', {name: '↗ SL1 schedule'}).getAttribute('href') === 'https://www.mbta.com/schedules/741/line', 'a proxied citation opens the primary page');
    check(await proxied.locator('small').innerText() === 'mbta.com', 'the primary page is labeled with its site');
    const copy = proxied.getByRole('link', {name: 'Cited through a third-party proxy, r.jina.ai'});
    check(await copy.getAttribute('href') === 'https://r.jina.ai/https://www.mbta.com/schedules/741/line', 'the cited proxy copy stays available and labeled');
    check(await sources.nth(1).locator('small').innerText() === 'mbta.com' && await sources.nth(1).locator('a').count() === 1, 'a direct citation has no copy link');
    check(await sources.nth(2).locator('small').innerText() === 'bit.ly · redirect link', 'an unresolvable redirect is labeled and listed last');

    await reply.locator('.chat-research summary').click();
    const research = reply.locator('.chat-research').getByRole('link', {name: 'Massport', exact: true});
    check((await research.getAttribute('href')).startsWith('https://www.massport.com/'), 'search notes links are clickable');
    check(await reply.locator('.chat-research .message-link small').textContent() === ' (massport.com)', 'search notes show where an uncited link goes');
    check(errors.length === 0, 'no page errors: ' + errors.join('; '));
    console.log('chat links: ' + checks + ' checks passed');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
