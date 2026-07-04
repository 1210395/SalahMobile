// عمارتي e2e — calculation correctness & logical consistency (money math).
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

const rnd = () => Math.floor(Math.random() * 1e7);

test('the ledger balance equals the sum of a unit\'s payments', async ({ page }) => {
  const bal = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok', balance: 0 });
    for (const a of [100, 50, 30]) {
      await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: a, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });
    }
    return (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((u) => u.no === no).balance;
  }, { no: 'L' + rnd() });
  expect(bal).toBe(180);
});

test('foreign-currency conversion rounds half-up to the base amount', async ({ page }) => {
  const r = await page.evaluate(async ({ n1, n2 }) => {
    const tok = await window.T.adminToken();
    const mk = async (no) => window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' });
    await mk(n1); await mk(n2);
    const p1 = (await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: n1, original_amount: 350, currency: 'ILS', exchange_rate: 0.27, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' })).body;
    const p2 = (await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: n2, original_amount: 100, currency: 'ILS', exchange_rate: 0.335, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' })).body;
    return { a: p1.amount, b: p2.amount };
  }, { n1: 'R' + rnd(), n2: 'R' + rnd() });
  expect(r.a).toBe(95); // 350 * 0.27 = 94.5 → 95
  expect(r.b).toBe(34); // 100 * 0.335 = 33.5 → 34
});

test('summary balance = opening + year revenue − year expenses', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const ys = await (await window.T.req('GET', '/year-summary?btype=residential&year=2026', tok)).body;
    const sum = await (await window.T.req('GET', '/summary?btype=residential&year=2026', tok)).body;
    const pays = await (await window.T.req('GET', '/payments?btype=residential', tok)).body;
    const exps = await (await window.T.req('GET', '/expenses?btype=residential', tok)).body;
    const rev = pays.filter((p) => p.year === 2026).reduce((s, p) => s + p.amount, 0);
    const exp = exps.filter((e) => new Date(e.date).getFullYear() === 2026).reduce((s, e) => s + e.amount, 0);
    return { got: sum.balance, expected: (ys.opening_balance || 0) + rev - exp };
  });
  expect(r.got).toBe(r.expected);
});

test('dues sum only the negative balances of non-vacant units', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const units = await (await window.T.req('GET', '/units?btype=residential', tok)).body;
    const sum = await (await window.T.req('GET', '/summary?btype=residential', tok)).body;
    const expected = units.filter((u) => u.status !== 'vacant' && u.balance < 0).reduce((s, u) => s + Math.abs(u.balance), 0);
    return { got: sum.due, expected };
  });
  expect(r.got).toBe(r.expected);
});

test('global report totals equal the sum across buildings', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const sup = await window.T.superToken();
    const gr = await (await window.T.req('GET', '/reports/global', sup)).body;
    return { got: gr.totals.collected, expected: gr.buildings.reduce((s, b) => s + b.collected, 0) };
  });
  expect(r.got).toBe(r.expected);
});

test('back-debt accrues for a past contract but never for a future one', async ({ page }) => {
  const r = await page.evaluate(async ({ nf, np }) => {
    const tok = await window.T.adminToken();
    const fut = new Date(); fut.setMonth(fut.getMonth() + 6);
    const past = new Date(); past.setMonth(past.getMonth() - 6);
    const uf = (await window.T.req('POST', '/units?btype=residential', tok, { no: nf, floor: 1, sub: 100, status: 'ok', contract_start: fut.toISOString().slice(0, 10), back_debt: true })).body;
    const up = (await window.T.req('POST', '/units?btype=residential', tok, { no: np, floor: 1, sub: 100, status: 'ok', contract_start: past.toISOString().slice(0, 10), back_debt: true })).body;
    return { future: uf.balance, past: up.balance };
  }, { nf: 'F' + rnd(), np: 'P' + rnd() });
  expect(r.future).toBe(0); // a future lease owes nothing
  expect(r.past).toBe(-600); // 6 months × 100
});

test('a zero or negative exchange rate is rejected; a valid one is accepted', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' });
    const p = (fields) => window.T.req('POST', '/payments?btype=residential', tok, Object.assign({ unit_no: no, original_amount: 500, currency: 'ILS', kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' }, fields));
    return { zero: (await p({ exchange_rate: 0 })).status, valid: (await p({ exchange_rate: 0.27 })).status };
  }, { no: 'RZ' + rnd() });
  expect(r.zero).toBe(422);
  expect(r.valid).toBe(201);
});

test('a unit status stays consistent with its balance (paying off clears late)', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'late', balance: -100 });
    await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: 100, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });
    const paid = (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((u) => u.no === no);
    // regenerate alerts — a paid-off unit must not produce an overdue alert
    await window.T.req('POST', '/alerts/regenerate?btype=residential', tok);
    const alerts = await (await window.T.req('GET', '/alerts?btype=residential', tok)).body;
    const overdueForThis = alerts.some((a) => a.type === 'subscription' && a.title && a.title.includes(no));
    return { balance: paid.balance, status: paid.status, overdueForThis };
  }, { no: 'ST' + rnd() });
  expect(r.balance).toBe(0);
  expect(r.status).toBe('ok'); // not 'late'
  expect(r.overdueForThis).toBe(false); // no spurious overdue alert
});

test('a back-debt unit is created as late (owes), not ok', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    const past = new Date(); past.setMonth(past.getMonth() - 3);
    const u = (await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok', contract_start: past.toISOString().slice(0, 10), back_debt: true })).body;
    return { balance: u.balance, status: u.status };
  }, { no: 'BD' + rnd() });
  expect(r.balance).toBe(-300);
  expect(r.status).toBe('late'); // balance drives status, despite status:'ok' input
});

test('a contract end date before the start date is rejected', async ({ page }) => {
  const r = await page.evaluate(async ({ n1, n2 }) => {
    const tok = await window.T.adminToken();
    const bad = (await window.T.req('POST', '/units?btype=residential', tok, { no: n1, floor: 1, sub: 100, status: 'ok', contract_start: '2026-06-01', contract_end: '2026-01-01' })).status;
    const good = (await window.T.req('POST', '/units?btype=residential', tok, { no: n2, floor: 1, sub: 100, status: 'ok', contract_start: '2026-01-01', contract_end: '2026-12-31' })).status;
    return { bad, good };
  }, { n1: 'CE' + rnd(), n2: 'CV' + rnd() });
  expect(r.bad).toBe(422);
  expect(r.good).toBe(201);
});
