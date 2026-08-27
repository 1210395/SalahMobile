# عمارتي — what runs around the app

The app itself is one Laravel service. These are the jobs on the box that keep
it honest, added during the pre-production audit (2026-08-27). Scripts live in
`C:\server\_bin`, logs in `C:\server\_logs`.

## Scheduled tasks

| Task | When | What it does |
|---|---|---|
| `Amarati-Scheduler` | every 5 min | `artisan schedule:run` — the Windows equivalent of Laravel's cron line. Runs the daily `amarati:alerts` regeneration at 06:00. |
| `Amarati-Backup` | daily 03:30 | Database dump + uploaded files, verified, pruned to 21 days, copied to a second disk. |
| `Amarati-Restore-Rehearsal` | Sundays 04:30 | Restores the newest backup into a scratch database and checks the tables came back with rows. |
| `Amarati-Monitor` | hourly | API reachable, backup fresh, scheduler ticking, services running, disk free, database populated. |

The `imarti-queue` service still runs a queue worker. With `QUEUE_CONNECTION=sync`
it does nothing; it is left in place for when mail is moved onto a queue after
the host move.

## Backups

`backup-amarati.ps1` → `C:\server\_backups\amarati-db-<stamp>.sql.zip` plus
`amarati-files-<stamp>.zip`, and a copy in `D:\amarati-backups`.

It refuses to keep a dump that does not contain `users`, `units`, `payments` and
`buildings` with at least one data row — a backup nobody can restore is worse
than none, because it is believed. Each run writes
`_backups\amarati-backup-status.json`, which the monitor reads to notice a
backup that silently stopped happening.

**Still owed:** every copy is on this machine. A second disk survives a bad
migration or a careless delete, not the building. Real offsite storage is an
owner decision.

To restore by hand:

```powershell
Expand-Archive C:\server\_backups\amarati-db-<stamp>.sql.zip -DestinationPath $env:TEMP\r
& 'C:\Program Files\MariaDB 12.3\bin\mysql.exe' -uamarati -p<pass> amarati < $env:TEMP\r\<file>.sql
```

## Monitoring

`monitor-amarati.ps1` writes `_logs\amarati-monitor-status.json` every hour and
exits non-zero when something is wrong. Nothing sends that anywhere yet — once
mail exists on the box, wire the `problems` array into an e-mail and the last
piece of "nobody would notice" is gone.

## Android release signing

- Keystore: `C:\server\_keys\amarati-release.jks` (copy in `D:\amarati-backups\keystore`)
- Passwords and the certificate fingerprint: `C:\server\_secrets\amarati-live-admin.txt`
- The build reads `android/key.properties`, which is gitignored. A machine
  without that file still builds, falling back to the debug key.

**The keystore cannot be replaced.** Android refuses an update signed with a
different key, so losing it means no installed copy of the app can ever be
updated again. Keep a copy somewhere that is not this building.

## Credentials

`C:\server\_secrets\amarati-live-admin.txt` holds the super-admin login and the
keystore passwords. Nothing else on this box needs a shared credential: every
building's manager account belongs to a person.
