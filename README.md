# عمارتي — Amarati (Building Management)

A mobile-first **Arabic (RTL)** app for managing residential buildings and
commercial complexes — subscriptions/dues, expenses, reports, and alerts in one
place. Built in **Flutter**, recreated faithfully from a Claude Design handoff
prototype (navy + gold brand, Cairo type).

## Running

```bash
flutter pub get
flutter run            # on a connected device / emulator
# or
flutter run -d chrome  # in the browser
```

> First launch fetches the **Cairo** font via `google_fonts` (needs internet
> once; it is then cached). To bundle the font offline instead, drop the TTFs in
> `assets/fonts/` and register them in `pubspec.yaml`.

## What's inside

Three roles with a role switcher (tap the ⇄ icon on any home screen, or
**المزيد → تبديل الدور**):

- **زائر (Guest)** — general building totals + a locked CTA to sign in.
- **مسؤول لجنة المبنى (Admin)** — full toolset:
  Dashboard · Units/Shops (detail sheets, WhatsApp/QR invite) · Payments ·
  Expenses · Workers & cleaning · Parking · Guard · Elevator access (paid/unpaid
  logic) · Craftsmen · Reports (monthly/annual/unit/expense, PDF·Excel) ·
  Alerts & WhatsApp templates · Years & months.
- **ساكن (Resident)** — personal dashboard, my report, elevator (shows the phone
  number if paid / a reminder if late), craftsmen, alerts.

Color coding throughout: **green = paid, red = late, blue = credit**. Toggle
**سكني / تجاري** (apartments ↔ shops) from the role-switcher sheet or the login
screen — all data swaps accordingly.

## Project structure

```
lib/
  main.dart              App root: RTL, Cairo theme, Arabic locale
  app.dart               Router, role state, bottom nav, toast, role switcher
  app_ctx.dart           Ctx passed to every screen (go/role/btype/toast/nav)
  theme/tokens.dart      Colors, radii, shadows, type (from tokens.css)
  data/sample_data.dart  Models + sample data + fmtUSD helper
  widgets/
    app_icon.dart        Icon set — exact SVG paths via flutter_svg
    primitives.dart      Card, Button, Badge, IconChip, ListRow, header, nav…
    controls.dart        Field, Select, Segmented, Switch, Avatar, FAB…
    charts.dart          Ring, BarChart, Donut
    scaffold.dart        ScreenScaffold, SheetShell, showAppSheet, NumText
    shared.dart          StatCard, QuickTile, MiniStat, DetailGrid, HeroBanner
  screens/               Auth, admin, and resident screens
assets/images/           Brand logo (light/dark)
```

## Backend (Laravel + MySQL)

A real REST backend lives in [`backend/`](backend/) (Laravel 13 + Sanctum +
MySQL), seeded with the same sample data. See [backend/README.md](backend/README.md)
to run it. Quick start:

```bash
docker compose up -d db                     # MySQL on :3307
cd backend && php artisan migrate:fresh --seed
php artisan serve --host=127.0.0.1 --port=8000   # API on :8000/api
```

The Flutter app talks to it through a small data layer:

- `lib/api/api_client.dart` — Dio client (base URL auto-resolves: `10.0.2.2` on
  Android emulator, `127.0.0.1` elsewhere; override with
  `--dart-define=API_BASE=...`).
- `lib/api/auth_store.dart` — email/password + phone-OTP login, token persisted
  via `shared_preferences`.
- `lib/api/repository.dart` — loads the building bundle into `DataStore`.
- `lib/data/sample_data.dart` — every accessor (`kApartments`, `Summary.*`, …)
  returns **live** data once loaded, and an **empty** value otherwise (live-data
  only — no bundled seed, so a real/empty building never shows fake numbers).

Real login flow: Splash → "تسجيل الدخول" → email (`admin@amarati.app` /
`password`) or phone OTP (tap "إرسال رمز التحقق", the dev code is shown in a
toast). "تجربة كزائر" loads the public summary. Logout from **المزيد**.

For local web review you can deep-link: `/?demo=admin` performs a real login, or
`/?screen=home&role=admin&btype=commercial` opens a screen directly.

## Tests

- `flutter test` — renders all 20 screens (`test/smoke_test.dart`) and checks the
  data-pipeline getters (`test/api_integration_test.dart`).

## Notes

- The prototype's design-tool "Tweaks" panel was intentionally dropped; the
  dashboard uses the **hero** layout and the building-type/role toggles live in
  the in-app role-switcher sheet.
- Currency is the building's chosen base (NIS/USD/…); per-payment foreign
  currency is converted to the base via the entered exchange rate.

## Redesign overhaul (notes.docx)

The app was reworked against `notes.docx` (see [`CHANGES_SPEC.md`](CHANGES_SPEC.md)
for the full spec). Highlights:

- **Brand** — new عمارتي / AMARTI logo (gold + red), palette harmonised to it.
- **Sign-up** — name · phone · WhatsApp · email · password **+ email confirmation
  code**, then a **bank e-payment** step for the subscription.
- **Resident login** — mobile/email + password, **or scan a QR / enter a login
  code** issued by the admin (per-resident `login_code`).
- **Apartments** — full add/edit (نوع العقار, monthly amount, ذمم سابقة, contract
  start/end + "مستمر"), rows read "طابق X شقة/محل Y" from real data, per-resident QR.
- **Revenues (formerly المستحقات)** — months shown as "شهر N", year list-picker,
  cash-first methods, today-default dates, fixed foreign-currency conversion
  (stored in the base currency), over/under-payment carries via the unit balance,
  per-payment **receipt (سند قبض)** shareable to WhatsApp / PDF, edit-delete on tap.
- **Dashboard** — fund balance, ذمم (دائن/مدين), and a 3-column "this month"
  summary (الاشتراكات · المصروفات · الذمم) with values shown above each column.
- **Reports** — figures/charts compute from live data per month/year; new
  **تقرير شامل** exports an Excel workbook (one sheet per year, residents × months).

### Simulated / seams (no external credentials in the repo)
- **Bank payment** is a clean in-app simulation that round-trips and activates the
  subscription. Real gateway = env keys + a signed webhook (marked in code).
- **Email codes** mirror the phone-OTP flow: a `dev_code` is returned in local
  mode (shown in a toast) and sent via `Mail` once `MAIL_*` is configured.
- **QR scanning** uses `mobile_scanner` (camera) — works on device; can't be
  exercised in headless tests on a desktop without a camera.
