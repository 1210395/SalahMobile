// عمارتي e2e — onboarding: subscription, building setup guards, join requests.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('a non-owner cannot set up the already-claimed residential building (403)', async ({ page }) => {
  const status = await page.evaluate(async () => {
    const email = 'ob' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    const tok = (await window.T.req('POST', '/auth/register', null, { name: 'مالك', email, password: 'secret123' })).body.token;
    const r = await window.T.req('POST', '/building/setup', tok, {
      btype: 'residential', name: 'محاولة', address: 'عنوان', floors: 5, units_count: 10,
    });
    return r.status;
  });
  expect(status).toBe(403); // residential is owned by the seeded admin
});

test('the subscription status endpoint is reachable', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    return (await window.T.req('GET', '/subscription?btype=residential', tok)).body;
  });
  expect(r).toHaveProperty('status');
});

test('a join request is listed for the admin, and approving it admits the resident', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    // fresh user submits a join request for unit 101
    const email = 'jr' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    const applicant = (await window.T.req('POST', '/auth/register', null, { name: 'منضم', email, password: 'secret123' })).body;
    await window.T.req('POST', '/join-requests', applicant.token, { btype: 'residential', unit_no: '101', name: 'منضم' });
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
    const jr = (await window.T.req('POST', '/join-requests', applicant.token, { btype: 'residential', unit_no: '102' })).body;
    const rej = await window.T.req('POST', '/join-requests/' + jr.id + '/reject?btype=residential', tok);
    return rej.body && rej.body.status;
  });
  expect(r).toBe('rejected');
});
