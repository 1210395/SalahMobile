// عمارتي e2e — authorization: roles, guest access, cross-tenant (IDOR), super-admin.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('guest can read only branding endpoints; financials + data require auth', async ({ page }) => {
  const r = await page.evaluate(async () => {
    return {
      building: (await window.T.req('GET', '/building')).status, // public (branding)
      buildingBody: (await window.T.req('GET', '/building')).body,
      buildings: (await window.T.req('GET', '/buildings')).status, // directory → protected
      settings: (await window.T.req('GET', '/settings')).status, // public (branding)
      payTypes: (await window.T.req('GET', '/pay-types')).status, // public (onboarding)
      summary: (await window.T.req('GET', '/summary')).status, // financials → protected
      units: (await window.T.req('GET', '/units')).status, // protected
    };
  });
  expect(r.building).toBe(200);
  // ...but 200 must not mean "here is somebody's building": a guest owns none, so
  // the shell carries no tenant's name, address or elevator phone.
  expect(r.buildingBody.name).toBe('');
  expect(r.buildingBody.address).toBe('');
  expect(r.buildingBody.elevator_phone).toBe('');
  expect(r.buildings).toBe(401); // the building directory is not public
  expect(r.settings).toBe(200);
  expect(r.payTypes).toBe(200);
  expect(r.summary).toBe(401); // real financials are not public
  expect(r.units).toBe(401);
});

test('resident reads are scoped: own unit only, no login codes, own payments, no expenses/workers', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const T = window.T; const tok = await T.adminToken(); const rand = () => Math.floor(Math.random() * 1e7);
    const mine = 'M' + rand(); const other = 'O' + rand();
    await T.req('POST', '/units?btype=residential', tok, { no: mine, floor: 1, sub: 100, status: 'ok' });
    await T.req('POST', '/units?btype=residential', tok, { no: other, floor: 1, sub: 100, status: 'ok' });
    await T.req('POST', '/payments?btype=residential', tok, { unit_no: mine, amount: 50, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });
    await T.req('POST', '/payments?btype=residential', tok, { unit_no: other, amount: 70, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });
    const res = await T.residentSession(mine);
    const t = res.token;
    const units = await (await T.req('GET', '/units?btype=residential', t)).body;
    const pays = await (await T.req('GET', '/payments?btype=residential', t)).body;
    const exps = await (await T.req('GET', '/expenses?btype=residential', t)).body;
    const workers = await (await T.req('GET', '/workers?btype=residential', t)).body;
    const parking = await (await T.req('GET', '/parking?btype=residential', t)).body;
    // Building-wide finances are for the manager only.
    const summary = (await T.req('GET', '/summary?btype=residential', t)).status;
    const yearSummary = (await T.req('GET', '/year-summary?btype=residential&year=2026', t)).status;
    return {
      unitCount: units.length,
      leaksCode: units.some((u) => u.login_code),
      seesOtherUnit: units.some((u) => u.no === other),
      payCount: pays.length,
      seesOtherPay: pays.some((p) => p.unit_no === other),
      expCount: exps.length,
      workerCount: workers.length,
      parkingCount: parking.length,
      summary,
      yearSummary,
    };
  });
  expect(r.unitCount).toBe(1);
  expect(r.leaksCode).toBe(false); // no login-code leak (account-takeover vector)
  expect(r.seesOtherUnit).toBe(false);
  expect(r.payCount).toBe(1);
  expect(r.seesOtherPay).toBe(false);
  expect(r.expCount).toBe(0);
  expect(r.workerCount).toBe(0);
  expect(r.parkingCount).toBe(0);
  expect(r.summary).toBe(403); // financials are admin-only
  expect(r.yearSummary).toBe(403);
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

test('a manager cannot touch another building\'s data (cross-building IDOR)', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const T = window.T;
    // Two managers each own a building with a unit + payment (multi-building).
    const mk = async (name) => {
      const email = 'x' + Math.floor(Math.random() * 1e9) + '@e2e.app';
      const tok = (await T.req('POST', '/auth/register', null, { name, email, password: 'secret123' })).body.token;
      await T.req('POST', '/subscription/activate', tok, { btype: 'residential' });
      await T.req('POST', '/building/setup', tok, { btype: 'residential', name, address: 'x', floors: 5, units_count: 10 });
      const no = 'U' + Math.floor(Math.random() * 1e6);
      const unit = (await T.req('POST', '/units', tok, { no, floor: 1, sub: 40, status: 'ok' })).body;
      const pay = (await T.req('POST', '/payments', tok, { unit_no: no, amount: 50, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' })).body;
      return { tok, unitId: unit.id, payId: pay.id };
    };
    const a = await mk('A');
    const b = await mk('B');
    return {
      unit: (await T.req('PUT', '/units/' + a.unitId, b.tok, { no: 'HACK', floor: 0, sub: 1, status: 'ok' })).status,
      pay: (await T.req('DELETE', '/payments/' + a.payId, b.tok)).status,
    };
  });
  expect(r.unit).toBe(403);
  expect(r.pay).toBe(403);
});

// Replacing a tenant doesn't merely unlink the old one — it DISABLES their login
// entirely: their live session is revoked and their QR stops redeeming. A
// moved-out tenant keeps no way into the building.
test('reassigning a unit disables the previous tenant (revoked session, dead QR, no leak)', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const T = window.T; const tok = await T.adminToken(); const rand = () => Math.floor(Math.random() * 1e7);
    await T.req('POST', '/units?btype=residential', tok, { no, floor: 1, sub: 100, status: 'ok' });
    const a = (await T.req('POST', '/residents?btype=residential', tok, { name: 'A', phone: '+9705' + rand(), unit_no: no, password: 'secret6' })).body;

    // A signs in while still the tenant.
    const tA = (await T.req('POST', '/auth/redeem-code', null, { code: a.login_code })).body.token;
    const aBefore = (await T.req('GET', '/me/payments', tA)).status;

    // B takes over the unit → A is disabled.
    const b = (await T.req('POST', '/residents?btype=residential', tok, { name: 'B', phone: '+9705' + rand(), unit_no: no, password: 'secret6' })).body;
    await T.req('POST', '/payments?btype=residential', tok, { unit_no: no, amount: 500, kind: 'k', month: 0, year: 2026, date: '2026-01-05', method: 'x' });

    const aAfter = (await T.req('GET', '/me/payments', tA)).status;             // A's session revoked
    const aReplay = (await T.req('POST', '/auth/redeem-code', null, { code: a.login_code })).status; // A's QR dead
    const tB = (await T.req('POST', '/auth/redeem-code', null, { code: b.login_code })).body.token;
    const payB = await (await T.req('GET', '/me/payments', tB)).body;
    return { aBefore, aAfter, aReplay, bSees: payB.length };
  }, { no: 'SH' + Math.floor(Math.random() * 1e7) });
  expect(r.aBefore).toBe(200);  // A worked while the tenant
  expect(r.aAfter).toBe(401);   // reassignment revoked A's live session
  expect(r.aReplay).toBe(422);  // A's QR no longer redeems
  expect(r.bSees).toBe(1);      // the current tenant sees the unit's payment
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
