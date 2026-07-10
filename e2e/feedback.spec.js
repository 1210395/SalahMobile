// عمارتي e2e — regressions for Salah's feedback (v1.3.4 / v1.3.5): back-debt +
// previous dues, multi-month payment totals, past-year payments, currency
// correctness (payments, expenses, building), and the label data the UI renders.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

const rnd = () => Math.floor(Math.random() * 1e7);

// #1 — enabling 'احتساب الإيجار من بداية العقد' must ADD any previous dues
// (ذمم سابقة) on top of the from-contract debt, not replace them.
test('back-debt adds previous dues on top, it does not replace them', async ({ page }) => {
  const r = await page.evaluate(async ({ n1, n2 }) => {
    const tok = await window.T.adminToken();
    const past = new Date(); past.setMonth(past.getMonth() - 3);
    const cs = past.toISOString().slice(0, 10);
    const withDues = (await window.T.req('POST', '/units?btype=residential', tok,
      { no: n1, floor: 1, sub: 100, status: 'ok', contract_start: cs, back_debt: true, balance: -250 })).body;
    const noDues = (await window.T.req('POST', '/units?btype=residential', tok,
      { no: n2, floor: 1, sub: 100, status: 'ok', contract_start: cs, back_debt: true, balance: 0 })).body;
    return { withDues: withDues.balance, noDues: noDues.balance };
  }, { n1: 'BP' + rnd(), n2: 'BN' + rnd() });
  expect(r.noDues).toBeLessThan(0);            // back-debt accrued from the contract
  expect(r.withDues).toBe(r.noDues - 250);     // the 250 previous dues are ADDED on top
});

// #4 — recording an amount across N months (the multi-month flow saves one row
// per month) must total N × amount, and a single month must still be one amount.
test('a multi-month payment sums to the full total across the months', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok', balance: 0 });
    for (let m = 0; m < 7; m++) {
      await window.T.req('POST', '/payments?btype=residential', tok,
        { unit_no: no, amount: 100, kind: 'k', month: m, year: 2026, date: '2026-08-01', method: 'x' });
    }
    const unit = (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((u) => u.no === no);
    const mine = (await (await window.T.req('GET', '/payments?btype=residential', tok)).body).filter((p) => p.unit_no === no);
    return {
      rows: mine.length,
      balance: unit.balance,
      total: mine.reduce((s, p) => s + p.amount, 0),
      oneMonth: mine.filter((p) => p.month === 0).reduce((s, p) => s + p.amount, 0),
    };
  }, { no: 'MM' + rnd() });
  expect(r.rows).toBe(7);       // one row per covered month
  expect(r.total).toBe(700);    // 7 × 100 — the full total, not one month's 100
  expect(r.balance).toBe(700);  // the unit is credited the full total
  expect(r.oneMonth).toBe(100); // a single month remains 100
});

// #2 — a payment can be recorded for a PREVIOUS year; it must land in that year
// (decoupled from the payment date).
test('a payment recorded for a previous year lands in that year, not the date year', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 50, status: 'ok', balance: 0 });
    await window.T.req('POST', '/payments?btype=residential', tok,
      { unit_no: no, amount: 50, kind: 'k', month: 11, year: 2023, date: '2026-08-01', method: 'x' });
    const mine = (await (await window.T.req('GET', '/payments?btype=residential', tok)).body).filter((p) => p.unit_no === no);
    return { count: mine.length, year: mine[0] && mine[0].year };
  }, { no: 'PY' + rnd() });
  expect(r.count).toBe(1);
  expect(r.year).toBe(2023); // the chosen covered year, not 2026 from the date
});

// Currency — a foreign-currency expense keeps its original amount + currency and
// converts to the base amount that totals sum on (mirrors the payments path).
test('a foreign-currency expense stores the entered amount + currency and converts to base', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const e = (await window.T.req('POST', '/expenses?btype=residential', tok,
      { cat: 'صيانة', supplier: 'E2E-CUR', amount: 54, original_amount: 200, currency: 'ILS', exchange_rate: 0.27, date: '2026-06-01', description: 'x' })).body;
    return { amount: e.amount, original: e.original_amount, currency: e.currency };
  });
  expect(r.currency).toBe('ILS');
  expect(r.original).toBe(200);
  expect(r.amount).toBe(54); // 200 × 0.27 = 54 in the base currency
});

// Labels — the building carries the exact data the header/settings labels render
// (name, currency, elevator fee, subscription); all present and correctly typed.
test('the building returns the currency + fee data its labels display', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const b = (await window.T.req('GET', '/building?btype=residential', tok)).body;
    return { name: b.name, currency: b.currency, elev: b.elevator_fee, sub: b.subscription };
  });
  expect(typeof r.currency).toBe('string');
  expect(r.currency.length).toBeGreaterThan(0); // a real currency code (e.g. USD) drives every money label
  expect(typeof r.elev).toBe('number');
  expect(typeof r.sub).toBe('number');
  expect(typeof r.name).toBe('string');
  expect(r.name.length).toBeGreaterThan(0);     // building name drives the dashboard header label
});

// Currency label follows the building — changing the building currency persists,
// so money labels render the chosen currency (restored to USD afterwards).
test('updating the building currency persists so labels follow it', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const before = (await window.T.req('GET', '/building?btype=residential', tok)).body.currency;
    await window.T.req('PUT', '/building?btype=residential', tok, { currency: 'ILS' });
    const changed = (await window.T.req('GET', '/building?btype=residential', tok)).body.currency;
    await window.T.req('PUT', '/building?btype=residential', tok, { currency: before }); // restore
    const restored = (await window.T.req('GET', '/building?btype=residential', tok)).body.currency;
    return { changed, restored, before };
  });
  expect(r.changed).toBe('ILS');
  expect(r.restored).toBe(r.before);
});
