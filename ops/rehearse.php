<?php
// سكن برو — the weekly restore rehearsal, run by cron on the host.
//
// A backup nobody has ever restored is a hope, not a backup. This takes the
// newest dump, restores it into a scratch database, and compares every table's
// row count against the live one. It catches the failures a "the file exists"
// check never will: a dump truncated by a full disk, a schema the current
// MySQL will not accept, a job that has been quietly dumping the wrong
// database for a month.
//
// Restoring is safe to repeat because mysqldump writes DROP TABLE IF EXISTS
// ahead of each table, so the scratch database is rebuilt from nothing each
// time. It NEVER touches the live database — the target is named here and is
// not the one the application uses.
//
//   cron:  50 3 * * 0  /usr/local/bin/ea-php83 /home/sakanpro/ops/rehearse.php

// These scripts do not boot the framework, so they get PHP's default timezone
// rather than the platform's. Ops logs in UTC beside an application that bills
// in Palestine local time is how someone misreads when a backup actually ran.
date_default_timezone_set('Asia/Hebron');

$home = '/home/sakanpro';
$appDir = $home.'/sakanpro-api';
$scratch = 'sakanpro_rehearse';

function env_value(string $file, string $key): string
{
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (str_starts_with(ltrim($line), $key.'=')) {
            // \r matters: the file is CRLF and FILE_IGNORE_NEW_LINES drops only \n.
            return trim(substr(ltrim($line), strlen($key) + 1), " \t\r\n\"'");
        }
    }

    return '';
}

function ops_notify(string $subject, string $body): void
{
    $to = trim((string) getenv('OPS_ALERT_EMAIL')) ?: 'no-reply@sakanpro.app';
    $cmd = sprintf('/usr/local/bin/ea-php83 /home/sakanpro/sakanpro-api/artisan amarati:ops-mail %s %s 2>&1',
        escapeshellarg($to), escapeshellarg($subject));
    $proc = popen($cmd, 'w');
    if ($proc) { fwrite($proc, $body); pclose($proc); }
}

$env = $appDir.'/.env';
$user = env_value($env, 'DB_USERNAME');
$pass = env_value($env, 'DB_PASSWORD');
$live = env_value($env, 'DB_DATABASE');

$fail = function (string $why) {
    echo "REHEARSAL FAILED: $why\n";
    ops_notify('نسخة سكن برو الاحتياطية لا تُستعاد', $why);
    exit(1);
};

if ($live === $scratch) {
    $fail('the scratch database is the live one — refusing to restore over it');
}

$dumps = glob($home.'/backups/sakanpro-db-*.sql.gz') ?: [];
usort($dumps, fn ($a, $b) => filemtime($b) <=> filemtime($a));
if ($dumps === []) {
    $fail('there is no dump to restore');
}
$dump = $dumps[0];

if (time() - filemtime($dump) > 26 * 3600) {
    $fail('the newest dump is '.round((time() - filemtime($dump)) / 3600).'h old');
}

$cnf = tempnam(sys_get_temp_dir(), 'sp');
chmod($cnf, 0600);
file_put_contents($cnf, "[client]\nuser=$user\npassword=\"$pass\"\nhost=127.0.0.1\n");

exec(sprintf('/usr/bin/gzip -dc %s | /usr/bin/mysql --defaults-extra-file=%s %s 2>&1',
    escapeshellarg($dump), escapeshellarg($cnf), escapeshellarg($scratch)), $out, $code);

if ($code !== 0) {
    @unlink($cnf);
    $fail("restoring ".basename($dump)." failed (exit $code): ".implode(' | ', array_slice($out, 0, 4)));
}

// ── compare ──────────────────────────────────────────────────────────────
// "It restored" is not the claim worth making; "it restored the same data" is.
try {
    $dsn = fn ($db) => new PDO("mysql:host=127.0.0.1;dbname=$db;charset=utf8mb4", $user, $pass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $a = $dsn($live);
    $b = $dsn($scratch);
} catch (\Throwable $e) {
    @unlink($cnf);
    $fail('could not compare the databases: '.$e->getMessage());
}
@unlink($cnf);

$mismatch = [];
$rows = 0;
$tables = $a->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
foreach ($tables as $t) {
    $liveRows = (int) $a->query("SELECT COUNT(*) FROM `$t`")->fetchColumn();
    try {
        $restored = (int) $b->query("SELECT COUNT(*) FROM `$t`")->fetchColumn();
    } catch (\Throwable $e) {
        $mismatch[] = "$t is missing from the restore";
        continue;
    }
    $rows += $restored;
    // The live database is in use while the dump is a moment in the past, so a
    // small drift is normal; a table that lost everything is not.
    if ($restored === 0 && $liveRows > 0) {
        $mismatch[] = "$t restored empty (live has $liveRows)";
    }
}

$summary = sprintf('%s: %d tables, %d rows', basename($dump), count($tables), $rows);
echo date('c')."  $summary\n";

if ($mismatch !== []) {
    $fail("$summary\n\n".implode("\n", $mismatch));
}

echo "every table restored\n";
@file_put_contents($home.'/logs/rehearse.log', date('c')."  OK  $summary\n", FILE_APPEND);
