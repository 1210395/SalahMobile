سكن برو — what runs on this host, and what does not
====================================================

  ops/backup.php    02:30 nightly   dump + gzip to ../backups, keep 14 days
  ops/health.php    :17 hourly      database, backup freshness, quota, SMS
                                    credit, error volume
  ops/rehearse.php  03:50 Sundays   restore the newest dump into
                                    sakanpro_rehearse and compare every table

Each mails a person ONLY when something is wrong, through the application's own
authenticated SMTP (artisan amarati:ops-mail), so alerts arrive from a signed
domain instead of landing in spam. Set OPS_ALERT_EMAIL in the crontab to change
where they go; it defaults to no-reply@sakanpro.app, which nobody watches.

These live outside public_html because backup.php reads the database password.
Nothing here should ever be fetchable over HTTP.

WHAT NONE OF THIS CAN SEE
-------------------------
Whether the host is up. A check that dies with the thing it is checking reports
nothing, so every job here goes quiet in exactly the situation that matters
most. Closing that needs something OUTSIDE this machine watching
https://sakanpro.app/api/settings — an external uptime service, or a job on
another box. Until then: silence from these jobs means either all is well or
the server is gone, and there is no way to tell the two apart from here.

The backups are also on the same disk as the data they protect. They defend
against the common loss — a bad edit, a dropped table, a broken deploy — and
not against losing the host. Off-site copies need a destination decision.
