# عمارتي — updating a running server

Data-preserving update of a server that already carries customer data. For a
fresh instance see [`PRODUCTION.md`](PRODUCTION.md); for the jobs that run on the
box see [`OPS.md`](OPS.md).

## The update

```bash
git pull origin main
php artisan migrate --force      # every migration in this repo is additive
php artisan optimize:clear       # routes + config are cached; new routes need this
```

On the current host the app is served by `php artisan serve` straight out of the
working tree, so **pulling changes the running code immediately** — the moment a
migration is pending, the served code is ahead of the schema. Pull and migrate
together, in that order, and never leave the pair half-done.

Verify:

```bash
curl -o /dev/null -w "%{http_code}\n" -H 'Accept: application/json' \
  https://imarty.olive-dev.com/api/units          # 401 = deployed, 404 = not
```

`Accept: application/json` matters: without it Laravel answers an unauthenticated
request differently, which is a property of the framework, not of the deploy.

## Never run these

- `php artisan migrate:fresh` — drops every table
- `php artisan migrate:fresh --seed` — drops everything, then inserts demo data
- `php artisan db:seed` — development only; it has no business near real data

## Migrations that carry data changes

Two of the recent ones changed existing rows, and both were rehearsed on a copy
of the live database before being applied:

- `2026_08_21_110000_split_dues_from_subscription` — adds `payments.bucket` and
  backfills it from what each row already said (`kind = 'ذمم'` → the ذمم pot,
  income-only → neither).
- `2026_08_27_100000_production_readiness_indexes_and_fks` — deletes `pay_types`
  rows whose building no longer exists (28 of them), then adds the foreign key
  that stops more appearing.

Rehearsing means: dump the live database, restore into a scratch one, run
`migrate` there, check the counts, and only then run it for real.

## After deploying

- The scheduler task runs `amarati:alerts` daily; nothing else needs restarting.
- If mail or SMS settings changed, `php artisan amarati:test-notify` says whether
  delivery still works.
- `C:\server\_logs\amarati-monitor-status.json` shows the box's own view of
  health within the hour.

## Older clients keep working

An APK already installed in the field talks to this API. Two behaviours exist
specifically to keep that true, and should not be "cleaned up":

- a payment that names no `bucket` is filed by its `kind`, exactly as before the
  two-pot split;
- `applies_to_dues` is still written alongside `bucket` for readers that predate
  it.

The one deliberate break is Android signing: **v1.5.2 is signed with a real key,
so v1.5.1 and earlier must be uninstalled before it can be installed.** Every
release after v1.5.2 updates normally.
