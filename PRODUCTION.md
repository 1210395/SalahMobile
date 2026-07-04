# عمارتي — production setup (fresh install)

This is for standing up a **new production instance** (a real customer), not the
data-preserving update of an existing server — for that, see `DEPLOY.md`.

## 1. Required environment (`.env` on the server)

These are **security-critical** — the app defaults are dev-friendly and MUST be
overridden in production:

```dotenv
APP_ENV=production
APP_DEBUG=false                 # never true in prod — leaks stack traces / secrets
APP_URL=https://your-domain     # correct scheme+host (used for logo URLs, etc.)

# Onboarding data
SEED_DEMO=false                 # start with EMPTY building shells, not demo data

# Secrets — DO NOT set these two in production:
#   AMARATI_EXPOSE_OTP_DEV_CODE  → if true, OTP/email codes are returned in the
#                                  API response (bypasses verification). Leave unset.
# Platform-owner (super-admin) account — REQUIRED to have a super-admin at all:
AMARATI_SUPERADMIN_EMAIL=owner@yourcompany.com
AMARATI_SUPERADMIN_PASSWORD=<a long random password>

# Optional:
# AMARATI_AUTH_RATE=6              # auth requests/min (default 6; leave default in prod)
# SANCTUM_EXPIRATION_MINUTES=129600  # token lifetime (90 days). Default: never
                                     # expires. Set this so a lost-device/leaked
                                     # token can't live forever; users re-login
                                     # (trivial via QR/code or password).
```

With `APP_ENV=production` and no `AMARATI_SUPERADMIN_PASSWORD`, **no super-admin
is created** (safe by default) — set the two vars above to create yours.

## 2. Database

```bash
php artisan migrate --force
php artisan db:seed --force      # with SEED_DEMO=false → 2 empty building shells
                                 # + pay-types + your super-admin. NO demo data.
php artisan storage:link         # REQUIRED for uploaded brand logos to resolve
php artisan optimize:clear
```

A fresh `SEED_DEMO=false` seed produces: **0 residents, 0 units, 0 payments**,
two empty building shells (residential + commercial), the pay-type catalogue,
and — only if you set the env vars — your super-admin. No `admin@amarati.app`,
no demo apartments.

## 3. First-run flow for the customer

1. The building manager **registers** (creates a pending-manager account).
2. **Subscribes** (activates the building's subscription).
3. **Sets up the building** (name/address/units) → promoted to admin.
4. Adds units + residents; residents log in by QR/code or phone OTP.

Renters cannot self-register — they're added by the manager (QR/code) or via an
approved join request.

## 4. Security checklist

- [ ] `APP_DEBUG=false` and `APP_ENV=production`.
- [ ] `AMARATI_EXPOSE_OTP_DEV_CODE` is **unset** (codes must not appear in API responses).
- [ ] `AMARATI_SUPERADMIN_PASSWORD` is long + random; the email is yours.
- [ ] **If migrating an older DB**: an old seed may have created
      `superadmin@amarati.app` with the password `password`. **Change or delete
      it** — `firstOrCreate` will not overwrite an existing account.
- [ ] HTTPS only; `APP_URL` uses `https://`.
- [ ] `php artisan storage:link` has been run (logos).
- [ ] Auth endpoints are rate-limited (default 6/min) — do not raise
      `AMARATI_AUTH_RATE` in production.

## 5. The mobile app (APK)

The release APK points at `https://imarty.olive-dev.com` by default. For a
different production host, rebuild with:

```bash
flutter build apk --release --dart-define=API_BASE=https://your-domain/api
```
