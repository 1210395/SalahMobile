// عمارتي e2e — expenses, workers, parking, guard, craftsmen CRUD.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('expense: create (currency-converted), edit, delete', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    // 100 ILS at 0.27 → 27 USD base
    const exp = (await window.T.req('POST', '/expenses?btype=residential', tok, {
      cat: 'صيانة', supplier: 'مورّد', amount: 100, original_amount: 100, currency: 'ILS', exchange_rate: 0.27, date: '2026-06-30',
    })).body;
    const edit = await window.T.req('PUT', '/expenses/' + exp.id + '?btype=residential', tok, { supplier: 'مورّد محدّث' });
    const del = await window.T.req('DELETE', '/expenses/' + exp.id + '?btype=residential', tok);
    const list = await (await window.T.req('GET', '/expenses?btype=residential', tok)).body;
    return { base: exp.amount, cur: exp.currency, editStatus: edit.status, editSupplier: edit.body && edit.body.supplier, delStatus: del.status, stillThere: list.some((e) => e.id === exp.id) };
  });
  expect(r.base).toBe(27);
  expect(r.cur).toBe('ILS');
  expect(r.editStatus).toBe(200);
  expect(r.editSupplier).toBe('مورّد محدّث');
  expect(r.delStatus).toBe(200);
  expect(r.stillThere).toBe(false);
});

test('worker: create, record attendance + full payment, then delete', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const w = (await window.T.req('POST', '/workers?btype=residential', tok, { name: 'عامل E2E', phone: '0599', cycle: 'شهري', amount: 200 })).body;
    const upd = (await window.T.req('PUT', '/workers/' + w.id + '?btype=residential', tok, { came: true, pay_status: 'full' })).body;
    const del = await window.T.req('DELETE', '/workers/' + w.id + '?btype=residential', tok);
    const list = await (await window.T.req('GET', '/workers?btype=residential', tok)).body;
    return { came: upd.came, pay: upd.pay_status, paid: upd.paid_amount, delStatus: del.status, gone: !list.some((x) => x.id === w.id) };
  });
  expect(r.came).toBeTruthy();
  expect(r.pay).toBe('full');
  expect(r.paid).toBe(200); // full → paid_amount = fee
  expect(r.delStatus).toBe(200);
  expect(r.gone).toBe(true);
});

test('worker: a full payment advances the next-due date by a cycle', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const w = (await window.T.req('POST', '/workers?btype=residential', tok, { name: 'عامل', phone: '0', cycle: 'شهري', amount: 200, next_due: '2026-01-01' })).body;
    const u = (await window.T.req('PUT', '/workers/' + w.id + '?btype=residential', tok, { pay_status: 'full' })).body;
    return { before: '2026-01-01', after: u.next_due };
  });
  expect(r.after).not.toBe(r.before); // advanced, not stale
  expect(new Date(r.after).getTime()).toBeGreaterThan(new Date(r.before).getTime());
});

test('parking: create, update status, delete', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const no = 'PK' + Math.floor(Math.random() * 1e6);
    const s = (await window.T.req('POST', '/parking?btype=residential', tok, { no, status: 'مشغول', unit_no: '101' })).body;
    const upd = (await window.T.req('PUT', '/parking/' + s.id + '?btype=residential', tok, { status: 'شاغر' })).body;
    const del = await window.T.req('DELETE', '/parking/' + s.id + '?btype=residential', tok);
    return { created: s.no === no, status: upd.status, delStatus: del.status };
  });
  expect(r.created).toBe(true);
  expect(r.status).toBe('شاغر');
  expect(r.delStatus).toBe(200);
});

test('guard: save and fetch the single guard record', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    await window.T.req('PUT', '/guard?btype=residential', tok, { name: 'حارس E2E', phone: '0599', fee: 175 });
    const g = await (await window.T.req('GET', '/guard?btype=residential', tok)).body;
    return { name: g.name, fee: g.fee };
  });
  expect(r.name).toBe('حارس E2E');
  expect(r.fee).toBe(175);
});

test('craftsman: create and list (shared directory)', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const name = 'سبّاك ' + Math.floor(Math.random() * 1e6);
    await window.T.req('POST', '/craftsmen', tok, { name, job: 'سباكة', phone: '0599' });
    const list = await (await window.T.req('GET', '/craftsmen', tok)).body;
    return list.some((c) => c.name === name);
  });
  expect(r).toBe(true);
});

test('building settings update persists (currency, subscription, elevator)', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const upd = (await window.T.req('PUT', '/building?btype=residential', tok, { subscription: 55, elevator_fee: 22 })).body;
    return { sub: upd.subscription, elev: upd.elevator_fee };
  });
  expect(r.sub).toBe(55);
  expect(r.elev).toBe(22);
});
