# عمارتي — Redesign change spec (from notes.docx)

This is the **single source of truth** for the notes.docx overhaul. Every
implementation agent reads this. The shared foundation (logo, palette, data-layer
helpers, shared widgets, deps) is **already done** — do not re-do it.

## Decisions (locked)
- **Bank payment**: clean *simulated* redirect screen that round-trips and then
  calls `POST /subscription/activate`. Leave an obvious seam (env keys + webhook)
  for a real gateway. No real credentials exist.
- **Email confirmation code**: mirror the existing phone-OTP pattern — generate a
  hashed code, return a `dev_code` in local mode, send via `Mail` when SMTP is set.
- **QR resident login**: full — admin shows a per-resident QR + short login code
  (shareable via WhatsApp); resident logs in by scanning (camera) **or** entering
  the code. Backend verifies the code.

## Foundation already in place (use it; do NOT edit these files)
`lib/theme/tokens.dart`, `lib/data/sample_data.dart`, `lib/widgets/extras.dart`,
`lib/common.dart`, `pubspec.yaml`, `assets/images/*`.

New tokens: `AppColors.brandRed`, `brandRed700`, `brandRedBg`; gold ramp now warm
(logo gold `gold500 = #C8941E`). Navy + semantic status colors unchanged.

New data helpers (in `sample_data.dart`, imported via `common.dart`):
- `monthLabelNum(int i)` → `"شهر ${i+1}"`  (months are shown numbered everywhere)
- `arMonthsNum` → `["شهر 1", … "شهر 12"]`
- `floorUnitLabel(Unit u, bool residential)` → `"طابق <floor> شقة|محل <no>"`
- `kYears` → sorted `List<int>` of years (live payment years ∪ recent window)
- `Unit.contractStart`, `Unit.contractEnd` (ISO strings, '' = none), `Unit.ongoing`,
  `Unit.loginCode`.

New shared widgets/helpers (in `extras.dart`, imported via `common.dart`):
- `DateField(label, value, onChanged)` + `Future<String?> pickDate(context, initialIso)`
  + `String todayIso()` — calendar date entry (ISO `yyyy-MM-dd`).
- `QrBox(data, size)` — renders a branded QR.
- `Future<String?> scanQr(context)` — full-screen camera scanner, returns decoded string.
- `Future<void> shareViaWhatsApp({phone, text})` — wa.me deep link, falls back to share sheet.

Existing primitives you SHOULD reuse: `Field`, `AppTextArea`, `SelectField`/`SelectOption`,
`Segmented`/`SegOption`, `AppSwitch`, `Avatar`, `EmptyState`, `AppButton`, `AppFab`,
`ScreenScaffold`, `AppHeader`, `showAppSheet`, `SheetShell`, `DetailGrid`/`DetailRow`,
`StatCard`/`MiniStat`/`QuickTile`, `NumText`, `BarChart`/`Ring`, `RoundBtn`, `AppBadge`.

## Terminology map (apply only within YOUR file; context matters)
| Where | From | To |
|---|---|---|
| Bottom-nav tab + payments/dues SCREEN title (admin_finance) | المستحقات | **الإيرادات** |
| Dashboard KPI of what residents owe (admin_dashboard) | المستحقات | **الذمم** (ذمم السكان) — show دائن/مدين |
| "الوحدات" screen title / tiles / counts | الوحدات / وحدة | **الشقق السكنية** (residential) · **المحلات التجارية** (commercial); singular **شقة / محل** |
| Unit row right square (admin_units) | "دور X" / "1 دور 1" | **`floorUnitLabel(u, ctx.res)`** → "طابق X شقة/محل Y" |
| Month labels EVERYWHERE (chips, selectors, headers) | يناير…ديسمبر / مايو | **`monthLabelNum(i)`** → "شهر N" |
| Year control | static 2026 / cycling | **list picker** over `kYears` |
| Add-payment item label (finance) | وحدة واحدة | **شقة واحدة** |
| Group screen rows (finance) | 1،2،3 | **resident names** |
| Per-resident revenue line (finance list) | اجرة الحارس | **remove that line** |
| Dashboard quick-summary bars | الإيرادات + الصيانة | **الاشتراكات · المصروفات · الذمم** (remove الصيانة; show numbers above each) |
| Name field (units add form) | الاسم الرباعي | **الاسم** |
| Phone field (units add form) | رقم الجوال | **رقم الموبايل** |

Do **not** globally delete صيانة as an expense category or the guard-management
screen — only the specific spots above.

## API contracts (new / changed) — for the backend agent and its consumers

### Email verification (mirror OTP)
- `POST /auth/request-email-code` `{ email }` → `{ sent: true, dev_code?: "123456" }`
  (dev_code only in local / when `amarati.expose_otp_dev_code`). Hashed, 10-min expiry.
- `POST /auth/verify-email-code` `{ email, code }` → `{ verified: true }` or 422.
  On success set `users.email_verified_at`.
- `POST /auth/register` now also accepts optional `phone` (unique), `whatsapp`.
  Add nullable `whatsapp` column to `users`.
- Rate-limit these under the existing 6/min auth throttle group.

### QR / code resident login
- Add nullable `login_code` (unique) to `users`. Generate a short code (e.g. 8 hex
  chars, uppercase) for every **resident** created (storeResident, approveJoinRequest,
  and backfill in the seeder for seeded residents).
- `GET /units` payload: include `login_code` for each unit (look up the resident
  user by `building_key` + `unit_no`). `Unit.fromJson` already reads `login_code`.
- `POST /residents` response: include the generated `login_code`.
- `POST /auth/redeem-code` `{ code }` → `{ token, user }` (logs in that resident).
  Rate-limited. QR encodes the **raw code** (resident may also type it).

### Payments — currency + carry-over
- `POST /payments` accepts `{ unit_no, name?, amount, currency, original_amount?,
  exchange_rate?, kind, month, year, date, method, notes? }`.
- **Server is authoritative for the base amount**: if `currency` != building base
  currency and `exchange_rate > 0`, store `amount = round(original_amount * exchange_rate)`
  (base currency); keep `original_amount`, `currency`, `exchange_rate` on the row.
  Else `amount = original_amount ?? amount`.
- **Balance / carry-over model** (`units.balance`, base currency; **+ = credit/دائن,
  − = owes/مدين**):
  - At unit creation, `balance = -previous_receivables` (ذمم سابقة; 0 if none).
  - On payment create: `unit.balance += base_amount`. On update: apply the delta.
    On delete: subtract it. (Overpayment → positive balance that carries forward;
    shortfall → remains negative. This *is* the carry-over — no per-month allocation
    engine.)
  - Keep `GET /summary` computing from payment/expense sums as today.
- `GET /summary` annual `trend`: return **12** months for the year, not 6.

### Subscription (bank redirect — mostly frontend)
- Keep `POST /subscription/activate`. Optionally accept `{ payment_ref, amount }`.
  The frontend simulates the bank round-trip then calls activate.

## Conventions (all agents)
- Arabic RTL, Cairo. Reuse existing primitives + the new shared helpers above.
- **Match the surrounding code's style and comment density.** Write like the senior
  engineer who wrote this repo (Arabic UI strings, terse English code comments).
  No "AI-generated" tells, no restating the obvious.
- **Only edit the files you are assigned.** Do not touch the foundation files, the
  other screens, `pubspec.yaml`, or run `flutter pub get`.
- **Do NOT run `flutter analyze` or `flutter test`** — the integrator runs them
  centrally and fixes cross-file issues. Focus on correct, self-consistent Dart.
- Keep any new widgets local to your file unless a shared primitive already exists.
- New screens must be reachable: if you add a screen id, wire it through the router
  in `app.dart` only if you own `app.dart` (F1); otherwise present via `showAppSheet`
  or `Navigator.push` from within your own screen.
- Guard against empty/live data (lists can be empty) — never `firstWhere` without
  `orElse`.
- End your run with a short report: what changed (file + brief), any new screen ids,
  and any assumption that affects another agent.
