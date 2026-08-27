# عمارتي — standing up a production instance

For a **new** server (including the coming host move). To update a server that
is already running, see [`DEPLOY.md`](DEPLOY.md); for the jobs that run on the
box around the app, see [`OPS.md`](OPS.md).

## 1. Environment

```dotenv
APP_NAME=عمارتي
APP_ENV=production
APP_DEBUG=false                    # never true in prod — leaks stack traces
APP_URL=https://your-domain        # https, correct host (logo URLs use it)
APP_KEY=base64:...                 # COPY FROM THE OLD SERVER, do not generate a
                                   # new one: existing encrypted values and
                                   # signed URLs become unreadable without it

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=amarati
DB_USERNAME=amarati
DB_PASSWORD=...

# ── Mail: verification codes and password recovery ride this ──────────────
MAIL_MAILER=smtp
MAIL_HOST=smtp.resend.com          # any SMTP provider; Resend is what the
MAIL_PORT=587                      # sister platform on the old box used
MAIL_USERNAME=resend
MAIL_PASSWORD=<the provider's API key / password>
MAIL_FROM_ADDRESS=no-reply@your-domain
MAIL_FROM_NAME=عمارتي

# ── SMS: phone-OTP codes ──────────────────────────────────────────────────
SMS_DRIVER=log                     # log | twilio | http
SMS_FROM=Amarati
# twilio:
# TWILIO_SID=...
# TWILIO_TOKEN=...
# TWILIO_MESSAGING_SERVICE_SID=...  (optional, instead of a from-number)
# http — any operator gateway, its own field names:
# SMS_HTTP_URL=https://gateway.example/send
# SMS_HTTP_METHOD=POST
# SMS_HTTP_TO_FIELD=to
# SMS_HTTP_TEXT_FIELD=text
# SMS_HTTP_FROM_FIELD=from
# SMS_HTTP_EXTRA=apikey=XXX&account=YYY
# SMS_HTTP_SUCCESS_CONTAINS=OK      (gateways that answer 200 on failure)

# ── Security ──────────────────────────────────────────────────────────────
# DO NOT set these on a real deployment. They return verification codes in the
# API response. They are IGNORED anyway once the matching provider above is
# configured, but leaving them out is the honest setting:
#   AMARATI_EXPOSE_SMS_DEV_CODE     — an echoed SMS code turns any resident's
#                                     phone NUMBER into a one-request takeover
#   AMARATI_EXPOSE_EMAIL_DEV_CODE   — milder: only confirms an address the
#                                     caller already typed
# AMARATI_REQUIRE_EMAIL_VERIFICATION=true   (default) — a manager must confirm
#                                     their address to register
# SANCTUM_EXPIRATION_MINUTES=129600 — token lifetime, defaults to 90 days
# AMARATI_AUTH_RATE=6               — auth requests/minute per IP
# AMARATI_API_RATE=240              — signed-in requests/minute per ACCOUNT
# AMARATI_PUBLIC_RATE=60            — unauthenticated reads/minute per IP
# CORS_ALLOWED_ORIGINS=https://your-domain
# AMARATI_APP_URL=...               — where /join/CODE points for the download
```

## 2. Database and files

```bash
php artisan migrate --force       # additive; NEVER migrate:fresh on real data
php artisan storage:link          # REQUIRED or uploaded logos 404
php artisan optimize:clear
```

Seeding is **not** part of a real install. `php artisan db:seed` exists for
development; on a server carrying customer data it can only do harm.

## 3. The platform owner account

The super-admin role gates platform branding, the all-buildings report, and
creating a manager for a new customer. Nothing creates it implicitly:

```bash
php artisan amarati:superadmin --email=owner@your-domain
```

It prints a generated password once. The address must be able to **receive
mail** — password recovery sends its code there. The command refuses to take
over an existing non-super-admin account unless you pass `--force`.

## 4. Prove delivery before you trust it

```bash
php artisan amarati:test-notify --email=you@example.com --phone=059XXXXXXX
```

It prints each channel's driver and whether a real message was accepted. A
channel reporting **NOT live** is one still echoing codes in API responses.

## 5. The mobile app

The APK points at `https://imarty.olive-dev.com/api` by default. For a different
host, rebuild:

```bash
flutter build apk --release --dart-define=API_BASE=https://your-domain/api
```

Release signing is described in [`OPS.md`](OPS.md). The keystore is **not** in
this repository, and it is not replaceable: Android refuses an update signed
with a different key.

## 6. Checklist

- [ ] `APP_DEBUG=false`, `APP_ENV=production`, `APP_URL` on https
- [ ] `APP_KEY` copied from the old server, not regenerated
- [ ] Mail configured, `amarati:test-notify` accepted a real message
- [ ] SMS configured, or phone-OTP login knowingly unavailable
- [ ] No `AMARATI_EXPOSE_*_DEV_CODE` variables set
- [ ] Super-admin created, and its address receives mail
- [ ] `storage:link` run
- [ ] Backups scheduled **off this machine**, and one restore rehearsed
- [ ] The app rebuilt against the new host and released before the old one goes
