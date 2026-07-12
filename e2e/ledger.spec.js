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
  const res = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    const due = async () =>
      (await (await window.T.req('GET', '/summary?btype=residential', tok)).body).due;
    // A real debt now comes from the OPENING balance (ذمم سابقة), not from writing
    // `balance` by hand — that field is derived and no longer settable (#19).
    // Opening −200, plus the current month's 100 fee = 300 owed.
    const id = (await window.T.req('POST', '/units?btype=residential', tok,
      { no, floor: 1, sub: 100, status: 'late', balance: -200 })).body.id;
    const dueWith = await due();

    await window.T.req('PUT', '/units/' + id + '?btype=residential', tok, { no, floor: 1, sub: 100, status: 'vacant' });
    const unit = (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((x) => x.no === no);
    return { balance: unit.balance, status: unit.status, dueWith, dueVacant: await due() };
  }, { no: 'VC' + Math.floor(Math.random() * 1e7) });
  expect(res.status).toBe('vacant');
  expect(res.balance).toBe(0); // vacant → balance zeroed
  expect(res.dueVacant).toBe(res.dueWith - 300); // opening 200 + this month's 100
});

// ─────────── QA wave: the derived ledger's own rules ───────────
// balance = opening_balance − charges + payments, and charges accrue INCLUSIVE of
// the current month. None of the rules below had e2e coverage before.

const rnd = () => Math.floor(Math.random() * 1e7);

// #19: balance is DERIVED. A PUT that tries to set it is ignored, not honoured —
// this is the whole point of the rewrite (it is what let #40's "missing 50" happen).
test('a unit balance cannot be set by hand — only payments move it', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    const id = (await window.T.req('POST', '/units?btype=residential', tok,
      { no, floor: 1, sub: 100, status: 'ok', balance: 0 })).body.id;
    // Try to hand it a fortune.
    await window.T.req('PUT', '/units/' + id + '?btype=residential', tok,
      { no, floor: 1, sub: 100, status: 'ok', balance: 99999 });
    const after = (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((u) => u.no === no);
    return { balance: after.balance, status: after.status };
  }, { no: 'DR' + rnd() });
  expect(r.balance).toBe(-100); // still just the one accrued month — the 99999 was ignored
  expect(r.status).toBe('late');
});

// #28: "أخرى" is income, NOT a dues settlement. It must never reduce what a
// resident owes — only a dues-applying payment does that.
test('an أخرى payment is income but does not settle dues', async ({ page }) => {
  const r = await page.evaluate(async ({ no, y }) => {
    const tok = await window.T.adminToken();
    const bal = async () =>
      (await (await window.T.req('GET', '/units?btype=residential', tok)).body).find((u) => u.no === no).balance;
    const revenue = async () =>
      (await (await window.T.req('GET', `/summary?btype=residential&year=${y}`, tok)).body).yearRevenue;

    await window.T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok', balance: 0 });
    const before = { bal: await bal(), rev: await revenue() };

    await window.T.req('POST', '/payments?btype=residential', tok,
      { unit_no: no, amount: 250, kind: 'أخرى', applies_to_dues: false, month: 0, year: y, date: `${y}-01-05`, method: 'نقداً' });
    const afterOther = { bal: await bal(), rev: await revenue() };

    // A normal dues payment, by contrast, DOES clear the debt.
    await window.T.req('POST', '/payments?btype=residential', tok,
      { unit_no: no, amount: 100, kind: 'دفعة شهرية', month: 0, year: y, date: `${y}-01-05`, method: 'نقداً' });

    return { before, afterOther, afterDues: await bal() };
  }, { no: 'OT' + rnd(), y: new Date().getFullYear() });

  expect(r.afterOther.bal).toBe(r.before.bal);              // dues untouched by أخرى
  expect(r.afterOther.rev - r.before.rev).toBe(250);        // but it IS revenue
  expect(r.afterDues).toBe(r.afterOther.bal + 100);         // a dues payment does settle
});

// #38/#39: "ايراد خاص" — building income tied to no renter at all (e.g. a cell
// tower). It needs no unit, requires a description, and never settles dues.
test('ايراد خاص needs no unit, requires a name, and never settles dues', async ({ page }) => {
  const r = await page.evaluate(async ({ y }) => {
    const tok = await window.T.adminToken();
    const revenue = async () =>
      (await (await window.T.req('GET', `/summary?btype=residential&year=${y}`, tok)).body).yearRevenue;
    const dues = async () =>
      (await (await window.T.req('GET', `/summary?btype=residential&year=${y}`, tok)).body).due;
    const before = { rev: await revenue(), due: await dues() };

    // No unit + no name → rejected: a special income must say what it is.
    const nameless = await window.T.req('POST', '/payments?btype=residential', tok,
      { amount: 1200, kind: 'ايراد خاص', month: 0, year: y, date: `${y}-01-05`, method: 'نقداً' });

    const ok = await window.T.req('POST', '/payments?btype=residential', tok,
      { name: 'دفعة برج جوال', amount: 1200, kind: 'ايراد خاص', month: 0, year: y, date: `${y}-01-05`, method: 'نقداً' });

    return {
      nameless: nameless.status,
      created: ok.status,
      unitNo: ok.body && ok.body.unit_no,
      appliesToDues: ok.body && ok.body.applies_to_dues,
      revDelta: (await revenue()) - before.rev,
      dueDelta: (await dues()) - before.due,
    };
  }, { y: new Date().getFullYear() });

  expect(r.nameless).toBe(422);      // a unit-less income must be described
  expect(r.created).toBe(201);
  expect(r.unitNo == null).toBe(true); // genuinely unit-less
  expect(!!r.appliesToDues).toBe(false); // forced off — it can never settle a resident's dues
  expect(r.revDelta).toBe(1200);     // it is income
  expect(r.dueDelta).toBe(0);        // and it changes nobody's dues
});

// #9/#10: the dashboard splits dues into what the year added vs what it inherited,
// and payments settle the OLDEST debt first.
test('summary splits dues into carried-over and this-year, oldest debt first', async ({ page }) => {
  const y = new Date().getFullYear();
  const r = await page.evaluate(async ({ no, y }) => {
    const tok = await window.T.adminToken();
    const sum = async () =>
      (await (await window.T.req('GET', `/summary?btype=residential&year=${y}`, tok)).body);
    const before = await sum();

    // Billed from January LAST year: 12 carried months + every month elapsed this year.
    await window.T.req('POST', '/units?btype=residential', tok, {
      no, floor: 1, sub: 100, status: 'ok', balance: 0,
      contract_start: `${y - 1}-01-01`, back_debt: true,
    });
    const owed = await sum();

    // Pay off exactly the carried 1200 — the carried slice must go to zero while
    // this year's own charges stand.
    await window.T.req('POST', '/payments?btype=residential', tok,
      { unit_no: no, amount: 1200, kind: 'ذمم', month: 0, year: y, date: `${y}-01-05`, method: 'نقداً' });
    const paid = await sum();

    return {
      prevDelta: owed.duePrev - before.duePrev,
      yearDelta: owed.dueYear - before.dueYear,
      afterPrevDelta: paid.duePrev - before.duePrev,
      afterYearDelta: paid.dueYear - before.dueYear,
      carried: typeof owed.carried,
    };
  }, { no: 'CO' + rnd(), y });

  const thisYear = (new Date().getMonth() + 1) * 100; // Jan…current month, inclusive
  expect(r.prevDelta).toBe(1200);        // 12 months of last year, carried in
  expect(r.yearDelta).toBe(thisYear);    // this year's own charges
  expect(r.afterPrevDelta).toBe(0);      // the payment cleared the OLD debt first
  expect(r.afterYearDelta).toBe(thisYear); // …leaving this year's charges standing
  expect(r.carried).toBe('number');      // مرحل من السنوات السابقة is reported
});
