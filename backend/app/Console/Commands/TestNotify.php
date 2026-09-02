<?php

namespace App\Console\Commands;

use App\Services\Notifier;
use Illuminate\Console\Command;

// سكن برو — prove that verification codes actually leave this server.
//
// Run it right after moving hosts (or after changing a provider) and it reports,
// per channel, what is configured and whether a real message was accepted:
//
//   php artisan amarati:test-notify --email=you@example.com --phone=0599123456
//
// A channel still on the `log` driver is reported as NOT live, which is also the
// condition under which the API still echoes codes in its responses.
class TestNotify extends Command
{
    protected $signature = 'amarati:test-notify {--email= : send a test e-mail here} {--phone= : send a test SMS here}';

    protected $description = 'Verify that e-mail / SMS delivery is really configured';

    public function handle(Notifier $notifier): int
    {
        $failed = false;

        // ── configuration, before sending anything ─────────────────────────
        $mailLive = Notifier::channelIsLive('mail');
        $smsLive = Notifier::channelIsLive('sms');

        $this->line('');
        $this->line('  البريد / e-mail');
        $this->line('    driver : '.config('mail.default').($mailLive ? '  (live)' : '  (NOT live — codes are still echoed in API responses)'));
        $this->line('    host   : '.(config('mail.mailers.smtp.host') ?: '—'));
        $this->line('    from   : '.(config('mail.from.address') ?: '—').' <'.(config('mail.from.name') ?: '—').'>');
        $this->line('');
        $this->line('  الرسائل القصيرة / SMS');
        $this->line('    driver : '.config('amarati.sms.driver').($smsLive ? '  (live)' : '  (NOT live — codes are still echoed in API responses)'));
        $this->line('    from   : '.(config('amarati.sms.from') ?: '—'));
        if (config('amarati.sms.driver') === 'http') {
            $this->line('    url    : '.(config('amarati.sms.http.url') ?: '— MISSING'));
        }
        if (config('amarati.sms.driver') === 'twilio') {
            $this->line('    sid    : '.(config('amarati.sms.twilio.sid') ? 'set' : '— MISSING'));
        }
        $this->line('');

        // ── real sends ─────────────────────────────────────────────────────
        if ($email = $this->option('email')) {
            $ok = $notifier->sendEmailCode($email, '123456');
            $ok ? $this->info("  ✓ e-mail accepted for $email")
                : $this->error("  ✗ e-mail FAILED for $email — see storage/logs");
            $failed = $failed || ! $ok;
        }

        if ($phone = $this->option('phone')) {
            $normalised = $notifier->normalisePhone($phone);
            $this->line("  → sending to $normalised");
            $ok = $notifier->sendSmsCode($phone, '123456');
            $ok ? $this->info("  ✓ SMS accepted for $normalised")
                : $this->error("  ✗ SMS FAILED for $normalised — see storage/logs");
            $failed = $failed || ! $ok;
        }

        if (! $this->option('email') && ! $this->option('phone')) {
            $this->comment('  (no --email / --phone given: configuration shown, nothing sent)');
        }

        $this->line('');

        return $failed ? self::FAILURE : self::SUCCESS;
    }
}
