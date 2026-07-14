// عمارتي e2e — onboarding: subscription, building setup guards, join requests.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('multi-building: a new manager creates their OWN building (no "already managed")', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const setup = async (name) => {
      const email = 'ob' + Math.floor(Math.random() * 1e9) + '@e2e.app';
      const tok = (await window.T.req('POST', '/auth/register', null, { name, email, password: 'secret123' })).body.token;
      await window.T.req('POST', '/subscription/activate', tok, { btype: 'residential' });
      const s = await window.T.req('POST', '/building/setup', tok, { btype: 'residential', name, address: 'ع', floors: 5, units_count: 10 });
      const me = await (await window.T.req('GET', '/me', tok)).body;
      return { status: s.status, buildingId: s.body && s.body.building && s.body.building.id, role: me.user.role, unitTok: tok };
    };
    const a = await setup('مبنى أ');
    const b = await setup('مبنى ب'); // same type — must NOT be 'already managed'
    return { aStatus: a.status, bStatus: b.status, distinct: a.buildingId !== b.buildingId, aRole: a.role, bRole: b.role };
  });
  expect(r.aStatus).toBe(200);
  expect(r.bStatus).toBe(200); // ← the fixed bug
  expect(r.distinct).toBe(true); // two separate buildings
  expect(r.aRole).toBe('admin');
  expect(r.bRole).toBe('admin');
});

test('a resident cannot take over a building via setup (403)', async ({ page }) => {
  const status = await page.evaluate(async () => {
    // A resident issued by the seeded admin has a building_id; setup must 403.
    const res = await window.T.residentSession('101');
    const r = await window.T.req('POST', '/building/setup', res.token, {
      btype: 'residential', name: 'اختطاف', address: 'x', floors: 5, units_count: 10,
    });
    return r.status;
  });
  expect(status).toBe(403);
});

// Asserting the SHAPE of this response ("has a status key") is what let a real
// bug through: /subscription is a public route, so $r->user() was null and every
// admin — subscription active and paid — was told "inactive". Assert the VALUE.
test('the subscription status reflects the caller\'s own building', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    return (await window.T.req('GET', '/subscription?btype=residential', tok)).body;
  });
  expect(r.status).toBe('active');
});

test('a join request is listed for the admin, and approving it admits the resident', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    // fresh user submits a join request for unit 101
    const email = 'jr' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    const applicant = (await window.T.req('POST', '/auth/register', null, { name: 'منضم', email, password: 'secret123' })).body;
    // A join request must NAME the building it targets: several buildings share a
    // btype, so the type alone can't identify one (it used to be filed against
    // whichever building happened to be first of that type).
    const target = (await window.T.req('GET', '/building?btype=residential', tok)).body;
    await window.T.req('POST', '/join-requests', applicant.token, { btype: 'residential', building_id: target.id, unit_no: '101', name: 'منضم' });
    // admin sees it pending
    let list = await (await window.T.req('GET', '/join-requests?btype=residential', tok)).body;
    const jr = list.find((x) => x.user_id === applicant.user.id);
    // approve
    const appr = await window.T.req('POST', '/join-requests/' + jr.id + '/approve?btype=residential', tok);
    // the applicant now has unit 101 and role resident
    const me = await (await window.T.req('GET', '/me', applicant.token)).body;
    return { pending: jr && jr.status, approved: appr.body && appr.body.status, unit: me.user.unit_no, role: me.user.role };
  });
  expect(r.pending).toBe('pending');
  expect(r.approved).toBe('approved');
  expect(r.unit).toBe('101');
  expect(r.role).toBe('resident');
});

test('rejecting a join request marks it rejected', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const email = 'jx' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    const applicant = (await window.T.req('POST', '/auth/register', null, { name: 'منضم', email, password: 'secret123' })).body;
    const target = (await window.T.req('GET', '/building?btype=residential', tok)).body;
    const jr = (await window.T.req('POST', '/join-requests', applicant.token, { btype: 'residential', building_id: target.id, unit_no: '102' })).body;
    const rej = await window.T.req('POST', '/join-requests/' + jr.id + '/reject?btype=residential', tok);
    return rej.body && rej.body.status;
  });
  expect(r).toBe('rejected');
});
