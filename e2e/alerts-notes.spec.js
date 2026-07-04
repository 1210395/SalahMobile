// عمارتي e2e — notifications, the alerts engine, and resident→admin notes.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('a broadcast notification reaches every resident; a targeted one only its unit', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const bTitle = 'بث ' + Math.floor(Math.random() * 1e6);
    const tTitle = 'موجّه ' + Math.floor(Math.random() * 1e6);
    await window.T.req('POST', '/notifications?btype=residential', tok, { title: bTitle, body: 'x', target: 'all' });
    await window.T.req('POST', '/notifications?btype=residential', tok, { title: tTitle, body: 'x', target: '101' });
    // resident on unit 101 sees both; a resident on 999 sees only the broadcast
    const r101 = await window.T.residentSession('101');
    const r999 = await window.T.residentSession('999');
    const a101 = await (await window.T.req('GET', '/alerts', r101.token)).body;
    const a999 = await (await window.T.req('GET', '/alerts', r999.token)).body;
    const has = (arr, t) => arr.some((a) => a.title === t);
    return {
      r101SeesBoth: has(a101, bTitle) && has(a101, tTitle),
      r999SeesBroadcast: has(a999, bTitle),
      r999SeesTargeted: has(a999, tTitle),
    };
  });
  expect(r.r101SeesBoth).toBe(true);
  expect(r.r999SeesBroadcast).toBe(true);
  expect(r.r999SeesTargeted).toBe(false); // privacy: not addressed to unit 999
});

test('a resident sends a note; the admin sees it in the inbox and can mark it read', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const res = await window.T.residentSession('101');
    const body = 'رسالة ' + Math.floor(Math.random() * 1e6);
    await window.T.req('POST', '/notes', res.token, { body });
    let inbox = await (await window.T.req('GET', '/notes?btype=residential', tok)).body;
    const note = inbox.find((n) => n.body === body);
    const read = await window.T.req('POST', '/notes/' + note.id + '/read?btype=residential', tok);
    return { seen: !!note, unitTagged: note && note.unit_no, wasNew: note && note.status, readStatus: read.status, nowRead: read.body && read.body.status };
  });
  expect(r.seen).toBe(true);
  expect(r.unitTagged).toBe('101'); // note carries the sender's unit
  expect(r.wasNew).toBe('new');
  expect(r.readStatus).toBe(200);
  expect(r.nowRead).toBe('read');
});

test('regenerating alerts rebuilds derived alerts but keeps manager notices', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const title = 'إعلان ' + Math.floor(Math.random() * 1e6);
    await window.T.req('POST', '/notifications?btype=residential', tok, { title, body: 'x', target: 'all' });
    const g = await window.T.req('POST', '/alerts/regenerate?btype=residential', tok);
    const alerts = await (await window.T.req('GET', '/alerts?btype=residential', tok)).body;
    return { generated: g.body && typeof g.body.generated === 'number', noticeKept: alerts.some((a) => a.type === 'notice' && a.title === title) };
  });
  expect(r.generated).toBe(true);
  expect(r.noticeKept).toBe(true);
});
