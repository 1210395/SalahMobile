<?php
// سكن برو — the nightly backup, run by cron on the host that holds the data.
//
// Lives outside public_html: it reads the database password, and a file that
// reads a password has no business being fetchable over HTTP.
//
// The job is not "produce a file". A file proves nothing — a dump can be zero
// bytes, or a valid file containing no data, and both look like success to
// anything that only checks the exit code. This verifies the dump has rows in
// it before it counts, and says so loudly when it does not, because the failure
// that matters is the one nobody notices for twelve days.
//
//   cron:  30 2 * * *  /usr/local/bin/ea-php83 /home/sakanpro/ops/backup.php

// These scripts do not boot the framework, so they get PHP's default timezone
// rather than the platform's. Ops logs in UTC beside an application that bills
// in Palestine local time is how someone misreads when a backup actually ran.
date_default_timezone_set('Asia/Hebron');

$home = '/home/sakanpro';
$appDir = $home.'/sakanpro-api';
$outDir = $home.'/backups';
$keepDays = 14;

@mkdir($outDir, 0700, true);

/// Read one key out of the application's own .env — the password lives in
/// exactly one place, and this is not a second copy of it.
function env_value(string $file, string $key): string
{
    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (str_starts_with(ltrim($line), $key.'=')) {
            // \r is in the trim list on purpose. The file is CRLF - it is
            // written from a Windows box - and FILE_IGNORE_NEW_LINES drops only
            // the \n. A password with a carriage return welded to the end is
            // refused by MySQL as a plain "access denied" that names nothing,
            // while Laravel's own parser handles it and the app keeps working:
            // exactly the kind of failure that looks like a wrong password.
            return trim(substr(ltrim($line), strlen($key) + 1), " \t\r\n\"'");
        }
    }

    return '';
}

$envFile = $appDir.'/.env';
$db = [
    'host' => env_value($envFile, 'DB_HOST') ?: '127.0.0.1',
    'name' => env_value($envFile, 'DB_DATABASE'),
    'user' => env_value($envFile, 'DB_USERNAME'),
    'pass' => env_value($envFile, 'DB_PASSWORD'),
];

$stamp = date('Ymd-Hi');
$log = [];
$fail = function (string $why) use (&$log, $outDir, $stamp) {
    $log[] = 'FAILED: '.$why;
    file_put_contents($outDir.'/status.json', json_encode([
        'ok' => false, 'at' => date('c'), 'error' => $why,
    ], JSON_PRETTY_PRINT));
    ops_notify('نسخة سكن برو الاحتياطية فشلت', implode("\n", $log));
    echo implode("\n", $log)."\n";
    exit(1);
};

/// Tell somebody. A backup nobody hears about failing is a backup that is not
/// running — that is the whole lesson this job exists to remember.
function ops_notify(string $subject, string $body): void
{
    $to = trim((string) getenv('OPS_ALERT_EMAIL')) ?: 'no-reply@sakanpro.app';
    $cmd = sprintf('/usr/local/bin/ea-php83 %s/sakanpro-api/artisan amarati:ops-mail %s %s 2>&1',
        escapeshellarg('/home/sakanpro'), escapeshellarg($to), escapeshellarg($subject));
    $proc = popen($cmd, 'w');
    if ($proc) { fwrite($proc, $body); pclose($proc); }
}

if ($db['name'] === '' || $db['user'] === '') {
    $fail('could not read the database settings out of .env');
}

// ── dump ─────────────────────────────────────────────────────────────────
// The password goes in a 0600 defaults file, never on the command line where
// every other account on a shared host can read it out of the process list.
$cnf = tempnam(sys_get_temp_dir(), 'sp');
chmod($cnf, 0600);
file_put_contents($cnf, "[client]\nuser={$db['user']}\npassword=\"{$db['pass']}\"\nhost={$db['host']}\n");

$sqlFile = $outDir."/sakanpro-db-$stamp.sql";
$cmd = sprintf('/usr/bin/mysqldump --defaults-extra-file=%s --single-transaction --routines %s > %s 2>%s',
    escapeshellarg($cnf), escapeshellarg($db['name']),
    escapeshellarg($sqlFile), escapeshellarg($sqlFile.'.err'));
exec($cmd, $out, $code);
unlink($cnf);

$stderr = trim((string) @file_get_contents($sqlFile.'.err'));
@unlink($sqlFile.'.err');

if ($code !== 0) {
    @unlink($sqlFile);
    $fail("mysqldump exited $code: ".mb_substr($stderr, 0, 300));
}

// ── verify it is a backup, not just a file ───────────────────────────────
$bytes = (int) @filesize($sqlFile);
$sql = (string) @file_get_contents($sqlFile);
$inserts = substr_count($sql, 'INSERT INTO');
$tables = substr_count($sql, 'CREATE TABLE');

if ($bytes < 1024 || $tables === 0) {
    @unlink($sqlFile);
    $fail("the dump is not usable: $bytes bytes, $tables tables");
}
if ($inserts === 0) {
    // Every table empty is possible on a fresh install and catastrophic on a
    // live one. Keep the file, but do not let it pass silently.
    $log[] = 'WARNING: the dump contains no rows at all';
    ops_notify('نسخة سكن برو الاحتياطية بلا بيانات',
        "The dump completed but contains no INSERT statements.\n$sqlFile\n");
}

exec(sprintf('/usr/bin/gzip -f %s', escapeshellarg($sqlFile)), $o, $gz);
$archive = $sqlFile.'.gz';
if ($gz !== 0 || ! is_file($archive)) {
    $fail('gzip failed');
}
$log[] = sprintf('database  %s  (%s KB, %d tables, %d inserts)',
    basename($archive), round(filesize($archive) / 1024, 1), $tables, $inserts);

// ── the uploaded files (logos and anything else on the public disk) ──────
$storage = $appDir.'/storage/app/public';
if (is_dir($storage) && count(scandir($storage)) > 2) {
    $filesArchive = $outDir."/sakanpro-files-$stamp.tar.gz";
    exec(sprintf('/usr/bin/tar -czf %s -C %s . 2>/dev/null',
        escapeshellarg($filesArchive), escapeshellarg($storage)), $o2, $t);
    if ($t === 0) {
        $log[] = sprintf('files     %s  (%s KB)',
            basename($filesArchive), round(filesize($filesArchive) / 1024, 1));
    }
}

// ── prune ────────────────────────────────────────────────────────────────
$cutoff = time() - ($keepDays * 86400);
$pruned = 0;
foreach (glob($outDir.'/sakanpro-*') ?: [] as $old) {
    if (filemtime($old) < $cutoff) { @unlink($old); $pruned++; }
}
$log[] = "kept $keepDays days; removed $pruned expired";

file_put_contents($outDir.'/status.json', json_encode([
    'ok' => true,
    'at' => date('c'),
    'archive' => basename($archive),
    'bytes' => filesize($archive),
    'tables' => $tables,
    'inserts' => $inserts,
], JSON_PRETTY_PRINT));

echo implode("\n", $log)."\n";
