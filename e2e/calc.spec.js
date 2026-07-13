// عمارتي e2e — calculation correctness & logical consistency (money math).
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

const rnd = () => Math.floor(Math.random() * 1e7);

// Derived ledger: balance = opening − charges + payments. A brand-new unit is
// already charged for the CURRENT month (accrual starts when a month starts, not
// when it ends), so payments are measured as a DELTA off the post-creation
// balance rather than against a bare zero.
test('payments move the ledger balance by exactly their sum', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    const bal = async () =>
      (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((u) => u.no === no).balance;
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok', balance: 0 });
    const before = await bal();
    for (const a of [100, 50, 30]) {
      await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: a, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });
    }
    return { before, after: await bal() };
  }, { no: 'L' + rnd() });
  expect(r.before).toBe(-100); // one month accrued the moment the unit exists
  expect(r.after - r.before).toBe(180);
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

test('a year\'s closing balance carries forward to the next year\'s opening', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' });
    // add a 2027 payment; 2027 has no stored opening → must carry 2026's closing
    await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: 200, kind: 'k', month: 0, year: 2027, date: '2027-01-05', method: 'x' });
    const s2026 = await (await window.T.req('GET', '/summary?btype=residential&year=2026', tok)).body;
    const s2027 = await (await window.T.req('GET', '/summary?btype=residential&year=2027', tok)).body;
    // recompute 2026 closing from raw, then 2027 opening should equal it
    const pays = await (await window.T.req('GET', '/payments?btype=residential', tok)).body;
    const exps = await (await window.T.req('GET', '/expenses?btype=residential', tok)).body;
    const ys = await (await window.T.req('GET', '/year-summary?btype=residential&year=2026', tok)).body;
    const rev2026 = pays.filter((p) => p.year === 2026).reduce((s, p) => s + p.amount, 0);
    const exp2026 = exps.filter((e) => new Date(e.date).getFullYear() === 2026).reduce((s, e) => s + e.amount, 0);
    const closing2026 = (ys.opening_balance || 0) + rev2026 - exp2026;
    const rev2027 = pays.filter((p) => p.year === 2027).reduce((s, p) => s + p.amount, 0);
    return { balance2026: s2026.balance, closing2026, balance2027: s2027.balance, expected2027: closing2026 + rev2027 };
  }, { no: 'YC' + rnd() });
  expect(r.balance2026).toBe(r.closing2026);
  expect(r.balance2027).toBe(r.expected2027); // 2027 opened at 2026's closing, not 0
});

// Dues count what non-vacant units OWE — a credit balance does not net against a
// neighbour's debt, and a vacant unit contributes nothing. Measured as a delta so
// the assertion doesn't depend on whatever else the suite has already created.
test('dues sum only the negative balances of non-vacant units', async ({ page }) => {
  const y = new Date().getFullYear();
  const r = await page.evaluate(async ({ owes, credit, vacant, y }) => {
    const tok = await window.T.adminToken();
    const due = async () =>
      (await (await window.T.req('GET', `/summary?btype=residential&year=${y}`, tok)).body).due;
    const before = await due();

    // Owes: no payments, so its first month's fee stands as debt.
    await window.T.req('POST', '/units?btype=residential', tok, { no: owes, floor: 1, sub: 100, status: 'ok', balance: 0 });
    // In credit: overpays this month — a credit must NOT reduce the building's dues.
    await window.T.req('POST', '/units?btype=residential', tok, { no: credit, floor: 1, sub: 100, status: 'ok', balance: 0 });
    await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: credit, amount: 500, kind: 'k', month: 0, year: y, date: `${y}-01-05`, method: 'x' });
    // Vacant: excluded from dues entirely.
    await window.T.req('POST', '/units?btype=residential', tok, { no: vacant, floor: 1, sub: 100, status: 'vacant', balance: 0 });

    return { before, after: await due() };
  }, { owes: 'D' + rnd(), credit: 'C' + rnd(), vacant: 'V' + rnd(), y });
  // Only the owing unit moves the needle: +100 (one accrued month).
  expect(r.after - r.before).toBe(100);
});

test('the year-transfer grid is live: 12 months reflecting real payments', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' });
    const before = await (await window.T.req('GET', '/year-summary?btype=residential&year=2026', tok)).body;
    const b7 = (before.months || []).find((m) => m.m === 7);
    await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: 5000, kind: 'k', month: 7, year: 2026, date: '2026-08-01', method: 'x' });
    const after = await (await window.T.req('GET', '/year-summary?btype=residential&year=2026', tok)).body;
    const a7 = (after.months || []).find((m) => m.m === 7);
    return { len: after.months.length, beforePaid: b7 ? b7.paid : null, afterPaid: a7 ? a7.paid : null };
  }, { no: 'YM' + rnd() });
  expect(r.len).toBe(12); // full year, not a partial stored set
  expect(r.afterPaid).toBe(r.beforePaid + 5000); // reflects the live payment
});

// Platform branding is shared by every building, so only the super-admin may
// change it — a building manager is forbidden. Colours must still be valid hex.
test('platform settings are super-admin only and reject a non-hex colour', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const admin = await window.T.adminToken();
    const sup = await window.T.superToken();
    return {
      byAdmin: (await window.T.req('PUT', '/settings', admin, { primary: '#123456' })).status,
      bad: (await window.T.req('PUT', '/settings', sup, { primary: 'not-a-hex' })).status,
      good: (await window.T.req('PUT', '/settings', sup, { primary: '#123456' })).status,
    };
  });
  expect(r.byAdmin).toBe(403); // a building manager can't rebrand the whole product
  expect(r.bad).toBe(422);
  expect(r.good).toBe(200);
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
  // 7 months × 100: the 6 back months PLUS the current one, which is billed the
  // moment it starts (#21/#25) rather than when it ends.
  expect(r.past).toBe(-700);
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
    // Opening debt of 100, plus the current month's 100 fee = 200 owed. Settling
    // the full 200 must clear the debt AND the late status — status is derived,
    // never set by hand (#18/#19).
    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'late', balance: -100 });
    await window.T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: 200, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });
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
  expect(r.balance).toBe(-400); // 3 back months + the current one, × 100
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
