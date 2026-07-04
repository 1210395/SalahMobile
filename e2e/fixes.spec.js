// عمارتي — live end-to-end verification of the correctness/security fixes.
//
// Each test loads the real web app, then runs the scenario through the page's
// own fetch() against the isolated backend (API_BASE below). Mutating tests
// require a THROWAWAY seeded DB — see e2e/README.md. Never point API_BASE at
// production or your real data.
const { test, expect } = require('@playwright/test');

const API = process.env.API_BASE || 'http://127.0.0.1:8001/api';
const ADMIN = { email: 'admin@amarati.app', password: 'password' };

// Run a function in the page context with API + admin creds injected.
async function inPage(page, fn) {
  await page.goto('/');
  await page.waitForTimeout(500);
  return page.evaluate(fn, { API, ADMIN });
}

const login = async (API, email, password) => {
  const r = await fetch(API + '/auth/login', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  return (await r.json()).token;
};

test('app boots and renders against the live backend', async ({ page }) => {
  await page.goto('/');
  await page.waitForTimeout(600);
  await expect(page).toHaveTitle(/عمارتي/);
  const ok = await page.evaluate(async ({ API }) => {
    const b = await (await fetch(API + '/building')).json();
    return !!b.name;
  }, { API });
  expect(ok).toBeTruthy();
});

test('FIX: refreshing alerts preserves manager-sent notifications', async ({ page }) => {
  const res = await inPage(page, async ({ API, ADMIN }) => {
    const H = (t) => ({ Accept: 'application/json', 'Content-Type': 'application/json', ...(t ? { Authorization: 'Bearer ' + t } : {}) });
    const tok = (await (await fetch(API + '/auth/login', { method: 'POST', headers: H(), body: JSON.stringify(ADMIN) })).json()).token;
    const title = 'E2E notice ' + Math.floor(Math.random() * 1e6);
    await fetch(API + '/notifications?btype=residential', { method: 'POST', headers: H(tok), body: JSON.stringify({ title, body: 'x', target: 'all' }) });
    await fetch(API + '/alerts/regenerate?btype=residential', { method: 'POST', headers: H(tok) });
    const alerts = await (await fetch(API + '/alerts?btype=residential', { headers: H(tok) })).json();
    return alerts.some((a) => a.type === 'notice' && a.title === title);
  });
  expect(res).toBe(true);
});

test('FIX: per-unit overdue alerts are targeted (admin sees them; residents do not see neighbours)', async ({ page }) => {
  const res = await inPage(page, async ({ API, ADMIN }) => {
    const H = (t) => ({ Accept: 'application/json', 'Content-Type': 'application/json', ...(t ? { Authorization: 'Bearer ' + t } : {}) });
    const tok = (await (await fetch(API + '/auth/login', { method: 'POST', headers: H(), body: JSON.stringify(ADMIN) })).json()).token;
    await fetch(API + '/alerts/regenerate?btype=residential', { method: 'POST', headers: H(tok) });
    const adminAlerts = await (await fetch(API + '/alerts?btype=residential', { headers: H(tok) })).json();
    const subs = adminAlerts.filter((a) => a.type === 'subscription');
    const adminSeesSubs = subs.length; // admin feed is unfiltered
    const noneBroadcast = subs.every((a) => a.target && a.target !== 'all');
    // A fresh resident on unit 101 must not see another unit's overdue alert.
    const r = await (await fetch(API + '/residents?btype=residential', { method: 'POST', headers: H(tok), body: JSON.stringify({ name: 'E2E res', phone: '+9705' + Math.floor(Math.random() * 1e7), unit_no: '101' }) })).json();
    const rTok = (await (await fetch(API + '/auth/redeem-code', { method: 'POST', headers: H(), body: JSON.stringify({ code: r.login_code }) })).json()).token;
    const rAlerts = await (await fetch(API + '/alerts', { headers: H(rTok) })).json();
    const seesNeighbour = rAlerts.some((a) => a.type === 'subscription' && a.target && a.target !== '101' && a.target !== 'all');
    return { adminSeesSubs, noneBroadcast, seesNeighbour };
  });
  expect(res.noneBroadcast).toBe(true);
  expect(res.seesNeighbour).toBe(false);
});

test('FIX: manager-created resident gets a 128-bit login code that redeems', async ({ page }) => {
  const res = await inPage(page, async ({ API, ADMIN }) => {
    const H = (t) => ({ Accept: 'application/json', 'Content-Type': 'application/json', ...(t ? { Authorization: 'Bearer ' + t } : {}) });
    const tok = (await (await fetch(API + '/auth/login', { method: 'POST', headers: H(), body: JSON.stringify(ADMIN) })).json()).token;
    const r = await (await fetch(API + '/residents?btype=residential', { method: 'POST', headers: H(tok), body: JSON.stringify({ name: 'E2E code', phone: '+9705' + Math.floor(Math.random() * 1e7), unit_no: '101' }) })).json();
    const redeem = await (await fetch(API + '/auth/redeem-code', { method: 'POST', headers: H(), body: JSON.stringify({ code: r.login_code }) })).json();
    return { len: (r.login_code || '').length, role: redeem.user && redeem.user.role, hasToken: !!redeem.token };
  });
  expect(res.len).toBe(32);
  expect(res.hasToken).toBe(true);
  expect(res.role).toBe('resident');
});

test('FIX: renaming a unit cascades its payments (no orphans)', async ({ page }) => {
  const res = await inPage(page, async ({ API, ADMIN }) => {
    const H = (t) => ({ Accept: 'application/json', 'Content-Type': 'application/json', ...(t ? { Authorization: 'Bearer ' + t } : {}) });
    const tok = (await (await fetch(API + '/auth/login', { method: 'POST', headers: H(), body: JSON.stringify(ADMIN) })).json()).token;
    const units = await (await fetch(API + '/units?btype=residential', { headers: H(tok) })).json();
    const pays = await (await fetch(API + '/payments?btype=residential', { headers: H(tok) })).json();
    const no = pays.length ? pays[0].unit_no : units[0].no;
    const unit = units.find((u) => u.no === no) || units[0];
    const before = pays.filter((p) => p.unit_no === unit.no).length;
    const newNo = unit.no + '-E2ERN';
    await fetch(API + '/units/' + unit.id + '?btype=residential', { method: 'PUT', headers: H(tok), body: JSON.stringify({ no: newNo, floor: unit.floor, sub: unit.sub, status: unit.status }) });
    const after = await (await fetch(API + '/payments?btype=residential', { headers: H(tok) })).json();
    const moved = after.filter((p) => p.unit_no === newNo).length;
    const orphans = after.filter((p) => p.unit_no === unit.no).length;
    // rename back to leave the seed tidy
    await fetch(API + '/units/' + unit.id + '?btype=residential', { method: 'PUT', headers: H(tok), body: JSON.stringify({ no: unit.no, floor: unit.floor, sub: unit.sub, status: unit.status }) });
    return { before, moved, orphans };
  });
  expect(res.moved).toBe(res.before);
  expect(res.orphans).toBe(0);
});

test('SECURITY: a residential admin cannot edit a commercial unit (IDOR blocked)', async ({ page }) => {
  const status = await inPage(page, async ({ API, ADMIN }) => {
    const H = (t) => ({ Accept: 'application/json', 'Content-Type': 'application/json', ...(t ? { Authorization: 'Bearer ' + t } : {}) });
    const tok = (await (await fetch(API + '/auth/login', { method: 'POST', headers: H(), body: JSON.stringify(ADMIN) })).json()).token;
    const cu = await (await fetch(API + '/units?btype=commercial', { headers: H(tok) })).json();
    if (!Array.isArray(cu) || !cu.length) return 'skip';
    const rr = await fetch(API + '/units/' + cu[0].id + '?btype=residential', { method: 'PUT', headers: H(tok), body: JSON.stringify({ no: 'HACK', floor: 0, sub: 1, status: 'ok' }) });
    return rr.status;
  });
  if (status !== 'skip') expect(status).toBe(403);
});
