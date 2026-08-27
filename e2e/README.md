# عمارتي — end-to-end (Playwright) tests

These tests load the **real Flutter web build** in a real browser and verify the
**live Laravel backend** end-to-end through the page's own `fetch()` — the same
network path the app uses. They deliberately don't click through the CanvasKit
canvas (its semantics tree is brittle to automate); asserting real backend
behaviour from inside the browser is what actually proves the fixes.

## ⚠️ Data safety

The mutating tests (unit rename, resident creation, alert regenerate) require a
**throwaway, seeded database** — never your real data. Point the backend under
test at an isolated DB (e.g. `amarati_test`) on a separate port.

## Setup

1. **Isolated backend on :8001** against a throwaway seeded DB:

   ```bash
   cd backend
   DB_DATABASE=amarati_test SEED_DEMO=true php artisan migrate:fresh --seed --force
   DB_DATABASE=amarati_test AMARATI_EXPOSE_OTP_DEV_CODE=true \
     php artisan serve --host=127.0.0.1 --port=8001
   ```
   `AMARATI_EXPOSE_OTP_DEV_CODE` still sets BOTH channels; the per-channel
   `AMARATI_EXPOSE_SMS_DEV_CODE` / `AMARATI_EXPOSE_EMAIL_DEV_CODE` override it
   individually. The specs read `dev_code` out of the OTP response, so the SMS
   side has to stay echoed for them to run. Note it is ignored once a real
   provider is configured — an e2e backend must have none.

   (Keep your other DB env vars — `DB_CONNECTION=mysql`, `DB_HOST`, `DB_PORT`,
   `DB_USERNAME`, `DB_PASSWORD` — set for the throwaway DB.)

2. **Web build served on :8099**, built to talk to the :8001 backend:

   ```bash
   flutter build web --dart-define=API_BASE=http://127.0.0.1:8001/api
   cd build/web && python -m http.server 8099
   ```

3. **Run the tests:**

   ```bash
   cd e2e
   npm install
   npx playwright install chromium
   npx playwright test
   ```

## Overrides

- `API_BASE`  — backend API root (default `http://127.0.0.1:8001/api`)
- `WEB_BASE`  — web app origin  (default `http://127.0.0.1:8099`)

## What's covered

| Test | Proves |
|------|--------|
| app boots | web build renders + reaches the backend |
| alerts preserve notices | refreshing alerts no longer deletes manager-sent notifications |
| overdue alerts targeted | admin sees per-unit alerts; residents don't see neighbours' debts |
| 128-bit login code | manager-created resident's code is strong and redeems |
| unit rename cascade | renaming a unit carries its payments (no orphans) |
| IDOR blocked | a residential admin can't edit a commercial unit (403) |
