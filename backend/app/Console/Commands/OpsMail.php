<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Mail;

// سكن برو — how the ops jobs on the host reach a person.
//
// The backup and health checks are plain scripts run by cron; they have no
// framework of their own, and PHP's mail() on shared hosting lands in spam if
// it arrives at all. Piping their output through this command means an alert
// goes out over the same authenticated SMTP, from the same signed domain, as
// everything else the platform sends — so it actually reaches the inbox.
//
//   echo "body" | ea-php83 artisan amarati:ops-mail someone@example.com "subject"
class OpsMail extends Command
{
    protected $signature = 'amarati:ops-mail {to : where to send it} {subject}';

    protected $description = 'Send an operational alert (body on stdin)';

    public function handle(): int
    {
        $body = trim((string) file_get_contents('php://stdin'));
        if ($body === '') {
            $body = '(no detail was given)';
        }

        $to = $this->argument('to');
        $subject = $this->argument('subject');

        try {
            Mail::raw($body, function ($m) use ($to, $subject) {
                $m->to($to)->subject('[سكن برو] '.$subject);
            });
        } catch (\Throwable $e) {
            // Say it on stdout as well. Cron captures that and mails it locally,
            // which is the last line of defence when the mailer itself is what
            // has broken — an alert that cannot be sent must not vanish.
            $this->error('could not send the alert: '.$e->getMessage());
            $this->line($subject);
            $this->line($body);

            return self::FAILURE;
        }

        $this->info('sent to '.$to);

        return self::SUCCESS;
    }
}
