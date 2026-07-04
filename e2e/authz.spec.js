// عمارتي e2e — authorization: roles, guest access, cross-tenant (IDOR), super-admin.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('guest can read public endpoints but not protected ones', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const building = await window.T.req('GET', '/building'); // public
    const units = await window.T.req('GET', '/units'); // protected
    return { building: building.status, units: units.status };
  });
  expect(r.building).toBe(200);
  expect(r.units).toBe(401);
});

test('a resident cannot perform admin writes (create payment / unit / expense)', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const res = await window.T.residentSession('101');
    const pay = await window.T.req('POST', '/payments?btype=residential', res.token, { unit_no: '101', amount: 10, kind: 'x', month: 0, year: 2026, date: '2026-01-01', method: 'نقداً' });
    const unit = await window.T.req('POST', '/units?btype=residential', res.token, { no: 'Z9', floor: 1, sub: 1, status: 'ok' });
    const exp = await window.T.req('POST', '/expenses?btype=residential', res.token, { cat: 'x', supplier: 'y', amount: 1, date: '2026-01-01' });
    return { pay: pay.status, unit: unit.status, exp: exp.status };
  });
  expect(r.pay).toBe(403);
  expect(r.unit).toBe(403);
  expect(r.exp).toBe(403);
});

test('a residential admin cannot touch commercial data (cross-tenant IDOR)', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    // seed a commercial payment + unit + parking directly is not possible without a
    // commercial admin, so read the commercial units (admins may switch btype) and
    // attempt a residential-scoped mutation against a commercial-bound id.
    const cUnits = await (await window.T.req('GET', '/units?btype=commercial', tok)).body;
    const cPays = await (await window.T.req('GET', '/payments?btype=commercial', tok)).body;
    const out = {};
    if (Array.isArray(cUnits) && cUnits.length) {
      out.unit = (await window.T.req('PUT', '/units/' + cUnits[0].id + '?btype=residential', tok, { no: 'HACK', floor: 0, sub: 1, status: 'ok' })).status;
    }
    if (Array.isArray(cPays) && cPays.length) {
      out.pay = (await window.T.req('DELETE', '/payments/' + cPays[0].id + '?btype=residential', tok)).status;
    }
    return out;
  });
  if ('unit' in r) expect(r.unit).toBe(403);
  if ('pay' in r) expect(r.pay).toBe(403);
});

test('super-admin endpoints reject a regular admin and accept the super-admin', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const admin = await window.T.adminToken();
    const sup = await window.T.superToken();
    return {
      adminAdmins: (await window.T.req('GET', '/admins', admin)).status,
      adminReport: (await window.T.req('GET', '/reports/global', admin)).status,
      supAdmins: (await window.T.req('GET', '/admins', sup)).status,
      supReport: (await window.T.req('GET', '/reports/global', sup)).status,
    };
  });
  expect(r.adminAdmins).toBe(403);
  expect(r.adminReport).toBe(403);
  expect(r.supAdmins).toBe(200);
  expect(r.supReport).toBe(200);
});

test('the global report totals across buildings for the super-admin', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const sup = await window.T.superToken();
    return (await window.T.req('GET', '/reports/global', sup)).body;
  });
  expect(r).toHaveProperty('buildings');
  expect(r).toHaveProperty('totals');
  expect(Array.isArray(r.buildings)).toBe(true);
});
