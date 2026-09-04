<?php
// سكن برو — the hourly health check, run by cron on the host.
//
// What this CAN see: the database, the freshness of last night's backup, the
// disk quota, the SMS balance, and how loudly the application is complaining.
//
// What it CANNOT see, and no job running here ever could: whether the host
// itself is up. A check that dies with the thing it is checking reports
// nothing. That gap needs something outside this machine — see the note in
// ops/README.
//
//   cron:  17 * * * *  /usr/local/bin/ea-php83 /home/sakanpro/ops/health.php

$home = '/home/sakanpro';
$appDir = $home.'/sakanpro-api';
$outDir = $home.'/backups';

$problems = [];
$notes = [];

require $appDir.'/vendor/autoload.php';
$app = require_once $appDir.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();


// ── the database ─────────────────────────────────────────────────────────
try {
    $users = Illuminate\Support\Facades\DB::table('users')->count();
    $buildings = Illuminate\Support\Facades\DB::table('buildings')->count();
    $notes[] = "database: reachable, $buildings buildings, $users accounts";
} catch (\Throwable $e) {
    $problems[] = 'THE DATABASE IS UNREACHABLE: '.$e->getMessage();
}

// ── last night's backup ──────────────────────────────────────────────────
$status = @json_decode((string) @file_get_contents($outDir.'/status.json'), true);
if (! is_array($status)) {
    $problems[] = 'no backup has ever reported a result';
} elseif (! ($status['ok'] ?? false)) {
    $problems[] = 'the last backup FAILED: '.($status['error'] ?? 'unknown');
} else {
    $age = time() - strtotime($status['at']);
    $hours = round($age / 3600, 1);
    if ($age > 26 * 3600) {
        $problems[] = "the last successful backup is {$hours}h old — the nightly job is not running";
    } elseif ((int) ($status['inserts'] ?? 0) === 0) {
        $problems[] = 'the last backup contains no rows';
    } else {
        $notes[] = sprintf('backup: %sh old, %s KB, %d inserts',
            $hours, round(($status['bytes'] ?? 0) / 1024, 1), $status['inserts']);
    }
}

// ── the quota ────────────────────────────────────────────────────────────
$used = 0;
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($home,
    FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::SELF_FIRST);
foreach ($it as $f) { if ($f->isFile()) { $used += $f->getSize(); } }
$usedMb = round($used / 1048576, 1);
if ($usedMb > 900) {
    $problems[] = "the account is at {$usedMb} MB of its 1000 MB quota — writes will start failing";
} elseif ($usedMb > 750) {
    $problems[] = "the account is at {$usedMb} MB of 1000 MB";
} else {
    $notes[] = "disk: {$usedMb} MB of 1000 MB";
}

// ── the SMS balance ──────────────────────────────────────────────────────
$smsId = config('amarati.sms.htd.id');
if (config('amarati.sms.driver') === 'htd' && $smsId) {
    $ch = curl_init('https://sms.htd.ps/API/GetCredit.aspx?id='.urlencode($smsId));
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 15]);
    $credit = trim((string) curl_exec($ch));
    curl_close($ch);

    if (is_numeric($credit)) {
        $left = (float) $credit;
        // Every verification code is one message. Running out means nobody can
        // sign in by phone, and nothing else would announce it.
        if ($left < 50) {
            $problems[] = "SMS credit is down to $left — top it up before codes stop going out";
        } else {
            $notes[] = "sms: $left credits";
        }
    } else {
        $problems[] = "the SMS gateway answered '$credit' instead of a balance";
    }
}

// ── what the application is complaining about ────────────────────────────
$logFile = $appDir.'/storage/logs/laravel-'.date('Y-m-d').'.log';
if (is_file($logFile)) {
    $errors = substr_count((string) file_get_contents($logFile), '.ERROR:');
    if ($errors > 50) {
        $problems[] = "$errors errors logged today";
    } elseif ($errors > 0) {
        $notes[] = "log: $errors errors today";
    }
}

// ── report ───────────────────────────────────────────────────────────────
$line = date('c').'  '.(($problems === []) ? 'OK' : count($problems).' PROBLEM(S)');
@file_put_contents($home.'/logs/health.log', $line."\n", FILE_APPEND);

echo $line."\n";
foreach ($notes as $n) { echo "  $n\n"; }
foreach ($problems as $p) { echo "  ! $p\n"; }

if ($problems === []) {
    exit(0);
}

// Only ever mailed when something is actually wrong. A daily "all is well" is
// how people learn to filter the alert that matters into the bin.
$to = trim((string) getenv('OPS_ALERT_EMAIL')) ?: 'no-reply@sakanpro.app';
$body = "sakanpro.app\n\n".implode("\n", array_map(fn ($p) => "- $p", $problems))
    ."\n\ncontext:\n".implode("\n", array_map(fn ($n) => "  $n", $notes))."\n";

$cmd = sprintf('/usr/local/bin/ea-php83 %s/artisan amarati:ops-mail %s %s 2>&1',
    escapeshellarg($appDir), escapeshellarg($to),
    escapeshellarg(count($problems).' مشكلة على الخادم'));
$proc = popen($cmd, 'w');
if ($proc) { fwrite($proc, $body); pclose($proc); }

exit(1);
