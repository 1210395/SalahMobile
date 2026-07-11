// عمارتي e2e — shared browser helper. Installs `window.T` in the page so every
// spec can drive the live backend via the app's own origin (real fetch path),
// then navigates to the app. All requests go to API_BASE (an ISOLATED throwaway
// backend — never real data). See README.md.
const API = process.env.API_BASE || 'http://127.0.0.1:8001/api';

const CREDS = {
  admin: { email: 'admin@amarati.app', password: 'password' },
  superadmin: { email: 'superadmin@amarati.app', password: 'password' },
};

// Unique-ish suffix without Date.now (fine in Node here) for collision-free data.
let _n = 0;
const uniq = (p = '') => p + Math.floor(Math.random() * 1e9) + '_' + _n++;

async function gotoApp(page) {
  await page.addInitScript((api) => {
    window.__API__ = api;
    window.T = {
      async req(method, path, token, body) {
        const r = await fetch(window.__API__ + path, {
          method,
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            ...(token ? { Authorization: 'Bearer ' + token } : {}),
          },
          body: body ? JSON.stringify(body) : undefined,
        });
        let j = null;
        try { j = await r.json(); } catch (e) { /* empty body */ }
        return { status: r.status, body: j };
      },
      async login(email, password) {
        const r = await this.req('POST', '/auth/login', null, { email, password });
        return r.body && r.body.token;
      },
      async adminToken() { return this.login('admin@amarati.app', 'password'); },
      async superToken() { return this.login('superadmin@amarati.app', 'password'); },
      // Create a resident + return {token, unit_no, code} for resident-side flows.
      async residentSession(unitNo) {
        const tok = await this.adminToken();
        const phone = '+9705' + Math.floor(Math.random() * 1e7);
        // Residents now require a password (durable phone+password login); the
        // login-code is single-use and rotates on redeem.
        const r = await this.req('POST', '/residents?btype=residential', tok, { name: 'E2E ' + phone, phone, unit_no: unitNo, password: 'secret6' });
        const code = r.body && r.body.login_code;
        const red = await this.req('POST', '/auth/redeem-code', null, { code });
        return { token: red.body && red.body.token, code, unitNo, phone, password: 'secret6' };
      },
    };
  }, API);
  await page.goto('/');
  await page.waitForTimeout(300);
}

module.exports = { gotoApp, API, CREDS, uniq };
