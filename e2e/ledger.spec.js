// عمارتي e2e — the carry-over balance ledger (units + payments). A payment
// credits the unit's balance; editing shifts it by the delta; deleting reverts
// it. Foreign-currency amounts are converted to the building base.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

// Create a throwaway unit and return its {id, no}.
async function freshUnit(page) {
  return page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const no = 'L' + Math.floor(Math.random() * 1e7);
    const r = await window.T.req('POST', '/units?btype=residential', tok, {
      no, floor: 1, resident: 'ساكن ' + no, kind: 'مالك', sub: 100, status: 'ok', balance: 0,
    });
    return { id: r.body.id, no, tok };
  });
}

const balanceOf = (page, no) => page.evaluate(async ({ no }) => {
  const tok = await window.T.adminToken();
  const units = await (await window.T.req('GET', '/units?btype=residential', tok)).body;
  const u = units.find((x) => x.no === no);
  return u ? u.balance : null;
}, { no });

test('creating a unit, then a duplicate number is rejected', async ({ page }) => {
  const u = await freshUnit(page);
  const dup = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    return (await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' })).status;
  }, { no: u.no });
  expect(dup).toBe(422);
});

test('a payment credits the unit balance; editing shifts by the delta; deleting reverts', async ({ page }) => {
  const u = await freshUnit(page);
  const flow = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    const bal = async () => (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((x) => x.no === no).balance;
    const start = await bal();
    const pay = (await window.T.req('POST', '/payments?btype=residential', tok, {
      unit_no: no, amount: 100, kind: 'اشتراك', month: 0, year: 2026, date: '2026-01-05', method: 'نقداً',
    })).body;
    const afterCreate = await bal();
    await window.T.req('PUT', '/payments/' + pay.id + '?btype=residential', tok, { amount: 150 });
    const afterEdit = await bal();
    await window.T.req('DELETE', '/payments/' + pay.id + '?btype=residential', tok);
    const afterDelete = await bal();
    return { start, afterCreate, afterEdit, afterDelete };
  }, { no: u.no });
  expect(flow.afterCreate).toBe(flow.start + 100);
  expect(flow.afterEdit).toBe(flow.start + 150); // delta +50 applied
  expect(flow.afterDelete).toBe(flow.start); // fully reverted
});

test('a foreign-currency payment is stored converted to the base amount', async ({ page }) => {
  const u = await freshUnit(page);
  const pay = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    // 350 ILS at rate 0.27 → 95 USD (base). building base is USD.
    return (await window.T.req('POST', '/payments?btype=residential', tok, {
      unit_no: no, original_amount: 350, currency: 'ILS', exchange_rate: 0.27,
      kind: 'اشتراك', month: 1, year: 2026, date: '2026-02-05', method: 'نقداً',
    })).body;
  }, { no: u.no });
  expect(pay.currency).toBe('ILS');
  expect(pay.original_amount).toBe(350);
  expect(pay.amount).toBe(Math.round(350 * 0.27)); // base = 95
});

test('an oversized payment amount is rejected (422), not a raw 500', async ({ page }) => {
  const u = await freshUnit(page);
  const status = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    return (await window.T.req('POST', '/payments?btype=residential', tok, {
      unit_no: no, amount: 9999999999, kind: 'x', month: 0, year: 2026, date: '2026-01-05', method: 'نقداً',
    })).status;
  }, { no: u.no });
  expect(status).toBe(422);
});

test('a payment for a non-existent unit is rejected (422)', async ({ page }) => {
  const status = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    return (await window.T.req('POST', '/payments?btype=residential', tok, {
      unit_no: 'GHOST-999', amount: 50, kind: 'x', month: 0, year: 2026, date: '2026-01-05', method: 'نقداً',
    })).status;
  });
  expect(status).toBe(422);
});

test('making a unit vacant zeroes its balance and excludes it from dues', async ({ page }) => {
  const u = await freshUnit(page);
  const res = await page.evaluate(async ({ id, no }) => {
    const tok = await window.T.adminToken();
    // give it a debt, then mark vacant
    await window.T.req('PUT', '/units/' + id + '?btype=residential', tok, { no, floor: 1, sub: 100, status: 'late', balance: -200 });
    const dueWith = (await (await window.T.req('GET', '/summary?btype=residential', tok)).body).due;
    await window.T.req('PUT', '/units/' + id + '?btype=residential', tok, { no, floor: 1, sub: 100, status: 'vacant' });
    const unit = (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((x) => x.no === no);
    const dueVacant = (await (await window.T.req('GET', '/summary?btype=residential', tok)).body).due;
    return { balance: unit.balance, status: unit.status, dueWith, dueVacant };
  }, { id: u.id, no: u.no });
  expect(res.status).toBe('vacant');
  expect(res.balance).toBe(0); // vacant → balance zeroed
  expect(res.dueVacant).toBe(res.dueWith - 200); // the 200 debt no longer counts
});
