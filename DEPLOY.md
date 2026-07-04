# Deploying عمارتي — keep your existing data

Your live backend (`imarty.olive-dev.com`) is running **old code** and is missing
the new endpoints/columns. These steps update it **without touching the data you
already have** (no reseed, no wipe).

## ✅ Do this (on the server / Coolify)

1. **Get the latest code** onto the server.
   - Coolify: open the app → **Redeploy** (it pulls `main` from GitHub).
   - Or manually: `git pull origin main` in the backend directory.

2. **Run migrations — additive only, data-preserving:**
   ```bash
   php artisan migrate --force
   ```
   This runs one new migration (`..._overhaul_additive_columns`) that ADDS the
   new columns (expense currency, worker attendance/payment, elevator contract,
   alert target) using `hasColumn` guards. **Your rows are untouched.**

3. **Clear caches** (so the new routes/config load):
   ```bash
   php artisan optimize:clear
   ```

4. Done. Verify a new endpoint responds (401 = deployed, 404 = not):
   ```bash
   curl -o /dev/null -w "%{http_code}\n" -X POST https://imarty.olive-dev.com/api/notifications
   ```
   `401` (or `422`) = success. `404` = the code didn't deploy — redeploy again.

## ❌ Do NOT run these (they destroy or pollute your data)

- `php artisan migrate:fresh` — **drops every table** (all your data gone).
- `php artisan migrate:fresh --seed` — drops everything **and** inserts demo
  apartments/payments + a demo `admin@amarati.app`.
- `php artisan db:seed` — would try to add demo data. (It self-skips when a
  building already exists, but don't rely on it — just don't run it.)

## Notes

- **`SEED_DEMO`**: only matters if you seed. Since you're keeping your data and
  NOT seeding, you can ignore it. (If you ever set up a *fresh* production DB,
  put `SEED_DEMO=false` in `.env` first so `--seed` creates empty buildings.)
- **⚠️ Super-admin password**: an earlier seed may have created
  `superadmin@amarati.app` with the password `password`. If that account exists,
  **change its password now** — it can view every building's finances and create
  admins. New code no longer seeds a weak super-admin (see `PRODUCTION.md`).
  Check: `php artisan tinker --execute="echo App\Models\User::where('role','superadmin')->pluck('email');"`
- **Resident login codes**: new codes are 128-bit; any existing 8-char codes
  still work unchanged — no action needed.
- **The APK**: install the new `app-release.apk` (built from this branch). It
  points at `imarty.olive-dev.com` by default, so it works once step 2 is done.

## If a redeploy still shows old code (404 on `/notifications`)

Coolify auto-deploy may be disabled or watching the wrong branch. In Coolify:
- Confirm the app's Git source is `1210395/SalahMobile`, branch `main`.
- Enable **Auto Deploy** (or hit Redeploy manually after each push).
- Check the deploy logs for a failed build/migration.
