// عمارتي e2e — authentication & account flows.
const { test, expect } = require('@playwright/test');
const { gotoApp } = require('./lib');

test.beforeEach(async ({ page }) => { await gotoApp(page); });

test('login with correct credentials returns a token + admin role', async ({ page }) => {
  const r = await page.evaluate(async () => window.T.req('POST', '/auth/login', null, { email: 'admin@amarati.app', password: 'password' }));
  expect(r.status).toBe(200);
  expect(r.body.token).toBeTruthy();
  expect(r.body.user.role).toBe('admin');
});

test('login with wrong password is rejected (422)', async ({ page }) => {
  const r = await page.evaluate(async () => window.T.req('POST', '/auth/login', null, { email: 'admin@amarati.app', password: 'nope' }));
  expect(r.status).toBe(422);
});

test('/me returns the current user, and logout invalidates the token', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const me = await window.T.req('GET', '/me', tok);
    const out = await window.T.req('POST', '/auth/logout', tok);
    const after = await window.T.req('GET', '/me', tok);
    return { meStatus: me.status, meRole: me.body && me.body.user && me.body.user.role, logout: out.status, afterLogout: after.status };
  });
  expect(r.meStatus).toBe(200);
  expect(r.meRole).toBe('admin');
  expect(r.afterLogout).toBe(401); // token revoked
});

test('registration creates a pending-manager (resident) account, never an admin', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const email = 'mgr' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    return window.T.req('POST', '/auth/register', null, { name: 'مالك جديد', email, password: 'secret123' });
  });
  expect(r.status).toBe(201);
  expect(r.body.user.role).toBe('resident'); // promoted to admin only via building setup
});

test('registration works WITHOUT an email code, then that account can log in', async ({ page }) => {
  // Email verification is optional — a new manager must be able to register and
  // sign in without a code (email delivery isn't wired yet).
  const r = await page.evaluate(async () => {
    const email = 'nocode' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    const reg = await window.T.req('POST', '/auth/register', null, { name: 'مدير', email, password: 'secret123' });
    const login = await window.T.req('POST', '/auth/login', null, { email, password: 'secret123' });
    return { reg: reg.status, regRole: reg.body && reg.body.user && reg.body.user.role, login: login.status, hasToken: !!(login.body && login.body.token) };
  });
  expect(r.reg).toBe(201);
  expect(r.regRole).toBe('resident'); // pending-manager, promoted via building setup
  expect(r.login).toBe(200);
  expect(r.hasToken).toBe(true);
});

test('registration rejects a duplicate email (422)', async ({ page }) => {
  const r = await page.evaluate(async () => window.T.req('POST', '/auth/register', null, { name: 'x', email: 'admin@amarati.app', password: 'secret123' }));
  expect(r.status).toBe(422);
});

test('registration with a WRONG email code fails and creates no account', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const email = 'ec' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    await window.T.req('POST', '/auth/request-email-code', null, { email });
    const reg = await window.T.req('POST', '/auth/register', null, { name: 'x', email, password: 'secret123', email_code: '000000' });
    const login = await window.T.req('POST', '/auth/login', null, { email, password: 'secret123' });
    return { reg: reg.status, login: login.status };
  });
  expect(r.reg).toBe(422);
  expect(r.login).toBe(422); // no account was created
});

test('email code: a wrong code then the right one is accepted (the reported bug)', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const email = 'wr' + Math.floor(Math.random() * 1e9) + '@e2e.app';
    const req = await window.T.req('POST', '/auth/request-email-code', null, { email });
    const code = req.body.dev_code;
    const wrong = await window.T.req('POST', '/auth/verify-email-code', null, { email, code: '999999' });
    const right = await window.T.req('POST', '/auth/verify-email-code', null, { email, code });
    return { hasDev: !!code, wrong: wrong.status, right: right.status };
  });
  expect(r.hasDev).toBe(true);
  expect(r.wrong).toBe(422);
  expect(r.right).toBe(200); // correct code still works after a wrong attempt
});

// #15 made a password MANDATORY on every manager-created resident, and verifyOtp
// refuses any account that has one. So a resident signs in with their phone (or
// email) + password — OTP is not a way around that, and cannot be used to bypass
// a known credential. A password-less account can no longer exist.
test('a manager-created resident is refused OTP and signs in with phone + password', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const phone = '+9705' + Math.floor(Math.random() * 1e7);
    const created = await window.T.req('POST', '/residents?btype=residential', tok,
      { name: 'ساكن OTP', phone, unit_no: '101', password: 'secret6' });

    // OTP must refuse the account: it has a password, so it must be used.
    const req = await window.T.req('POST', '/auth/request-otp', null, { phone });
    const verify = await window.T.req('POST', '/auth/verify-otp', null, { phone, code: req.body.dev_code || '123456' });

    // The credential the manager set is what actually signs them in.
    const login = await window.T.req('POST', '/auth/login', null, { phone, password: 'secret6' });
    return {
      created: created.status,
      verify: verify.status,
      login: login.status,
      role: login.body && login.body.user && login.body.user.role,
    };
  });
  expect(r.created).toBe(201);
  expect(r.verify).toBe(422); // OTP cannot sign in a password account
  expect(r.login).toBe(200);
  expect(r.role).toBe('resident');
});

// #15: a resident created WITHOUT a password is rejected outright.
test('creating a resident without a password is rejected', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const tok = await window.T.adminToken();
    const phone = '+9705' + Math.floor(Math.random() * 1e7);
    const none = await window.T.req('POST', '/residents?btype=residential', tok, { name: 'بلا كلمة', phone, unit_no: '101' });
    const short = await window.T.req('POST', '/residents?btype=residential', tok, { name: 'قصيرة', phone, unit_no: '101', password: '123' });
    return { none: none.status, short: short.status };
  });
  expect(r.none).toBe(422);
  expect(r.short).toBe(422); // min 6 characters
});

test('OTP for an unknown phone is rejected — renters cannot self-register', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const phone = '+9705' + Math.floor(Math.random() * 1e7);
    await window.T.req('POST', '/auth/request-otp', null, { phone });
    // request-otp issues a code, but verify must still reject an unknown phone.
    const req = await window.T.req('POST', '/auth/request-otp', null, { phone });
    const verify = await window.T.req('POST', '/auth/verify-otp', null, { phone, code: req.body.dev_code || '123456' });
    return verify.status;
  });
  expect(r).toBe(422);
});

test('OTP cannot take over a password-protected (admin) account', async ({ page }) => {
  const r = await page.evaluate(async () => {
    const phone = '+966500000001'; // seeded admin phone
    const req = await window.T.req('POST', '/auth/request-otp', null, { phone });
    const verify = await window.T.req('POST', '/auth/verify-otp', null, { phone, code: req.body.dev_code || '123456' });
    return verify.status;
  });
  expect(r).toBe(422);
});

test('redeeming an invalid login code is rejected (422)', async ({ page }) => {
  const r = await page.evaluate(async () => window.T.req('POST', '/auth/redeem-code', null, { code: 'NOTACODE' }));
  expect(r.status).toBe(422);
});

// A renter added before logins were mandatory had NO account, and the edit sheet
// had no password field — so they could never sign in, and a forgotten password
// was unrecoverable. Setting a password on the unit creates/repairs the login.
test('setting a unit password creates the renter login and reissues the QR', async ({ page }) => {
  const r = await page.evaluate(async ({ no, phone }) => {
    const tok = await window.T.adminToken();
    const unit = (await window.T.req('POST', '/units?btype=residential', tok,
      { no, floor: 1, resident: 'ساكن بلا حساب', kind: 'مستأجر', phone, sub: 100, status: 'ok' })).body;

    // No account exists yet: phone + password cannot sign in.
    const before = await window.T.req('POST', '/auth/login', null, { phone, password: 'secret6' });

    const set = await window.T.req('POST', `/units/${unit.id}/password?btype=residential`, tok,
      { password: 'secret6' });
    const after = await window.T.req('POST', '/auth/login', null, { phone, password: 'secret6' });

    // A reset rotates the QR and kills the old password.
    const reset = await window.T.req('POST', `/units/${unit.id}/password?btype=residential`, tok,
      { password: 'newpass6' });
    const stale = await window.T.req('POST', '/auth/login', null, { phone, password: 'secret6' });
    const fresh = await window.T.req('POST', '/auth/login', null, { phone, password: 'newpass6' });

    return {
      before: before.status,
      set: set.status,
      code: (set.body.login_code || '').length,
      after: after.status,
      role: after.body && after.body.user && after.body.user.role,
      rotated: reset.body.login_code !== set.body.login_code,
      stale: stale.status,
      fresh: fresh.status,
    };
  }, { no: 'PW' + Math.floor(Math.random() * 1e7), phone: '+9705' + Math.floor(Math.random() * 1e7) });

  expect(r.before).toBe(422);   // no login existed
  expect(r.set).toBe(200);
  expect(r.code).toBe(32);      // a QR to share over واتساب
  expect(r.after).toBe(200);    // the renter can now sign in
  expect(r.role).toBe('resident');
  expect(r.rotated).toBe(true); // a reset reissues the QR…
  expect(r.stale).toBe(422);    // …and the old password is dead
  expect(r.fresh).toBe(200);
});

test('a unit password needs 6+ chars, and a resident cannot set one', async ({ page }) => {
  const r = await page.evaluate(async ({ no }) => {
    const tok = await window.T.adminToken();
    const unit = (await window.T.req('POST', '/units?btype=residential', tok,
      { no, floor: 1, sub: 100, status: 'ok', phone: '+9705' + Math.floor(Math.random() * 1e7) })).body;
    const short = await window.T.req('POST', `/units/${unit.id}/password?btype=residential`, tok,
      { password: '123' });
    const res = await window.T.residentSession('101');
    const byResident = await window.T.req('POST', `/units/${unit.id}/password?btype=residential`,
      res.token, { password: 'hacked6' });
    return { short: short.status, byResident: byResident.status };
  }, { no: 'PS' + Math.floor(Math.random() * 1e7) });
  expect(r.short).toBe(422);
  expect(r.byResident).toBe(403); // only an admin may reset a renter's login
});
