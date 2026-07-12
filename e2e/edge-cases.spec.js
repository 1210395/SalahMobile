// عمارتي e2e — edge cases surfaced by adversarial probing (all now fixed).
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

const rnd = () => Math.floor(Math.random() * 1e7);

test('an over-long string field returns 422, not a raw 500', async ({ page }) => {
  const s = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    return (await window.T.req('POST', '/expenses?btype=residential', tok, { cat: 'x', supplier: 'A'.repeat(5000), amount: 1, date: '2026-01-01' })).status;
  });
  expect(s).toBe(422);
});

test('a negative expense amount is rejected (422)', async ({ page }) => {
  const s = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    return (await window.T.req('POST', '/expenses?btype=residential', tok, { cat: 'x', supplier: 'y', amount: -999, date: '2026-01-01' })).status;
  });
  expect(s).toBe(422);
});

test('deleting a unit with payments is blocked; an empty unit still deletes', async ({ page }) => {
  const r = await page.evaluate(async ({ n1, n2 }) => {
    const tok = await window.T.adminToken();
    const u = (await window.T.req('POST', '/units?btype=residential', tok, { no: n1, floor: 1, sub: 100, status: 'ok' })).body;
    await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: n1, amount: 100, kind: 'x', month: 0, year: 2026, date: '2026-01-05', method: 'نقداً' });
    const blocked = (await window.T.req('DELETE', '/units/' + u.id + '?btype=residential', tok)).status;
    const u2 = (await window.T.req('POST', '/units?btype=residential', tok, { no: n2, floor: 1, sub: 100, status: 'ok' })).body;
    const empty = (await window.T.req('DELETE', '/units/' + u2.id + '?btype=residential', tok)).status;
    return { blocked, empty };
  }, { n1: 'DP' + rnd(), n2: 'DE' + rnd() });
  expect(r.blocked).toBe(422);
  expect(r.empty).toBe(200);
});

test('duplicate parking numbers are rejected', async ({ page }) => {
  const r = await page.evaluate(async ({ pk }) => {
    const tok = await window.T.adminToken();
    const a = (await window.T.req('POST', '/parking?btype=residential', tok, { no: pk, status: 'شاغر' })).status;
    const b = (await window.T.req('POST', '/parking?btype=residential', tok, { no: pk, status: 'شاغر' })).status;
    return { a, b };
  }, { pk: 'PKX' + rnd() });
  expect(r.a).toBe(201);
  expect(r.b).toBe(422);
});

test('editing a foreign-currency payment amount resyncs its currency to base', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' });
    const p = (await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, original_amount: 350, currency: 'ILS', exchange_rate: 0.27, kind: 'x', month: 0, year: 2026, date: '2026-01-05', method: 'نقداً' })).body;
    const e = (await window.T.req('PUT', '/payments/' + p.id + '?btype=residential', tok, { amount: 500 })).body;
    return { amount: e.amount, original: e.original_amount, currency: e.currency };
  }, { no: 'CE' + rnd() });
  expect(r.amount).toBe(500);
  expect(r.original).toBe(500); // no stale 350
  expect(r.currency).toBe('NIS'); // the building's base currency (#6), not stale ILS
});
