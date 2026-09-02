<?php

namespace App\Services;

use App\Mail\VerificationCodeMail;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

// سكن برو — the one place a verification code leaves the server.
//
// Both channels are provider-agnostic: SMS picks a driver from config
// (log | twilio | http-gateway), e-mail rides Laravel's own mailer, so moving
// to another host means filling in env vars — never editing code. Nothing here
// throws: a provider outage must not turn a login attempt into a 500, so a
// failure is logged and reported back as `false` for the caller to surface.
class Notifier
{
    /// Whether [channel] ('sms' | 'mail') has a REAL provider behind it. Used to
    /// decide whether a code may still be echoed in the API response: once a
    /// provider is configured, the dev echo turns itself off.
    public static function channelIsLive(string $channel): bool
    {
        if ($channel === 'sms') {
            // A driver NAME is not a working provider. Naming a gateway and
            // forgetting its credential would otherwise advertise SMS as
            // available and fail every single code silently, which is the exact
            // dishonesty this method exists to prevent.
            return match (config('amarati.sms.driver')) {
                'htd' => ! empty(config('amarati.sms.htd.id')),
                'twilio' => ! empty(config('amarati.sms.twilio.sid'))
                    && ! empty(config('amarati.sms.twilio.token')),
                'http' => ! empty(config('amarati.sms.http.url')),
                default => false,
            };
        }

        return ! in_array(config('mail.default'), ['log', 'array', 'null', '', null], true);
    }

    /// The E.164 prefixes the SMS provider can actually reach, or an empty list
    /// when it is unrestricted.
    public static function smsCoverage(): array
    {
        return array_values(array_filter(array_map(
            'trim',
            explode(',', (string) config('amarati.sms.coverage')),
        )));
    }

    /// Whether this is even a phone number.
    ///
    /// The coverage check only looks at the prefix, so "+9705" passed it and we
    /// would spend a credit posting nonsense to the gateway. E.164 allows at
    /// most fifteen digits and no real mobile has fewer than nine.
    public static function looksLikeANumber(string $phone): bool
    {
        $digits = strlen(preg_replace('/\D/', '', $phone));

        return $digits >= 9 && $digits <= 15;
    }

    /// Whether an OTP could ever arrive at this number.
    ///
    /// A local operator gateway serves Palestinian and Israeli numbers only. A
    /// resident abroad would otherwise ask for a code, be told it was sent, and
    /// wait for a message that was never going to leave the building.
    public static function coversNumber(string $phone): bool
    {
        $prefixes = self::smsCoverage();
        if ($prefixes === []) {
            return true;
        }

        $number = (new self)->normalisePhone($phone);
        foreach ($prefixes as $prefix) {
            if (str_starts_with($number, $prefix)) {
                return true;
            }
        }

        return false;
    }

    /// Send a verification code by SMS. Returns true when the provider accepted it.
    public function sendSmsCode(string $phone, string $code): bool
    {
        $minutes = (int) config('amarati.code_ttl_minutes', 10);

        // Kept under 70 characters ON PURPOSE. Arabic goes out as UCS-2, which
        // fits 70 to a segment, and the gateway bills by segment — the previous
        // wording ran to 74 and so cost two credits for every single code,
        // halving what the balance was worth.
        return $this->sendSms($phone, "سكن برو: رمز الدخول $code\nصالح $minutes دقائق — لا تشاركه مع أحد.");
    }

    /// Send an arbitrary SMS through the configured driver.
    public function sendSms(string $phone, string $text): bool
    {
        $to = $this->normalisePhone($phone);
        $driver = config('amarati.sms.driver', 'log');

        // A finite balance is a resource worth guarding at the one place every
        // send passes through, rather than at each caller that might forget.
        if (! $this->claimDailyBudget()) {
            Log::error('amarati.sms.budget_exhausted', [
                'cap' => (int) config('amarati.sms.daily_cap'),
                'to' => $this->mask($to),
            ]);

            return false;
        }

        try {
            return match ($driver) {
                'htd' => $this->viaHtd($to, $text),
                'twilio' => $this->viaTwilio($to, $text),
                'http' => $this->viaHttpGateway($to, $text),
                default => $this->viaLog('sms', $to, $text),
            };
        } catch (\Throwable $e) {
            // A dead provider must never break sign-in for everyone else.
            Log::error('amarati.sms.failed', ['driver' => $driver, 'to' => $this->mask($to), 'error' => $e->getMessage()]);

            return false;
        }
    }

    /// Send a verification code by e-mail. Returns true when the mailer accepted it.
    public function sendEmailCode(string $email, string $code, string $purpose = 'register'): bool
    {
        try {
            Mail::to($email)->send(new VerificationCodeMail(
                $code, $purpose, (int) config('amarati.code_ttl_minutes', 10),
            ));

            return true;
        } catch (\Throwable $e) {
            Log::error('amarati.mail.failed', ['to' => $this->mask($email), 'error' => $e->getMessage()]);

            return false;
        }
    }

    // ───────────────────────────── drivers ─────────────────────────────

    /// HTD (sms.htd.ps) — the Palestinian gateway سكن برو sends through.
    ///
    /// Two things stop the generic gateway driver from covering this one. The
    /// number must be bare digits with a country code and no "+", and success is
    /// a plain English sentence in the body rather than a status code — every
    /// failure mode is another sentence ("Insufficient Credit", "IP Not Allowed",
    /// "Sender Not Allowed"), which is worth logging verbatim because each one
    /// names its own fix.
    private function viaHtd(string $to, string $text): bool
    {
        $id = config('amarati.sms.htd.id');
        if (! $id) {
            Log::error('amarati.sms.misconfigured', ['driver' => 'htd', 'missing' => 'SMS_HTD_ID']);

            return false;
        }

        $res = Http::timeout(20)->get(config('amarati.sms.htd.url'), [
            'id' => $id,
            'sender' => config('amarati.sms.from'),
            'to' => $this->htdNumber($to),
            'msg' => $text,
            'mode' => 0,
        ]);

        $body = trim($res->body());
        $ok = $res->successful() && str_contains($body, 'Message Sent Successfully');

        if (! $ok) {
            Log::error('amarati.sms.rejected', [
                'driver' => 'htd',
                'status' => $res->status(),
                'to' => $this->mask($to),
                'body' => mb_substr($body, 0, 200),
            ]);
        }

        return $ok;
    }

    /// The number as HTD wants it: digits only, carrying a country code.
    ///
    /// The account is provisioned against 972, so a Palestinian +970 number goes
    /// out as 972 — the same handset either way. It is configurable because the
    /// provider's own manual documents 970 and the account note says 972; if
    /// that ever changes it must not need a deploy.
    public function htdNumber(string $phone): string
    {
        $digits = preg_replace('/\D/', '', $this->normalisePhone($phone));
        $cc = trim((string) config('amarati.sms.htd.country_code'));

        return ($cc !== '' && str_starts_with($digits, '970'))
            ? $cc.substr($digits, 3)
            : $digits;
    }

    private function viaTwilio(string $to, string $text): bool
    {
        $sid = config('amarati.sms.twilio.sid');
        $token = config('amarati.sms.twilio.token');
        if (! $sid || ! $token) {
            Log::error('amarati.sms.misconfigured', ['driver' => 'twilio']);

            return false;
        }

        $service = config('amarati.sms.twilio.messaging_service_sid');
        $payload = ['To' => $to, 'Body' => $text]
            + ($service ? ['MessagingServiceSid' => $service] : ['From' => config('amarati.sms.from')]);

        $res = Http::asForm()->withBasicAuth($sid, $token)->timeout(15)
            ->post("https://api.twilio.com/2010-04-01/Accounts/$sid/Messages.json", $payload);

        if (! $res->successful()) {
            Log::error('amarati.sms.rejected', ['driver' => 'twilio', 'status' => $res->status(), 'body' => $res->body()]);
        }

        return $res->successful();
    }

    /// Any operator gateway that takes plain parameters — field names come from
    /// config so a local provider needs no code change.
    private function viaHttpGateway(string $to, string $text): bool
    {
        $cfg = config('amarati.sms.http');
        if (empty($cfg['url'])) {
            Log::error('amarati.sms.misconfigured', ['driver' => 'http']);

            return false;
        }

        $params = [
            $cfg['to_field'] => $to,
            $cfg['text_field'] => $text,
            $cfg['from_field'] => config('amarati.sms.from'),
        ];
        if (! empty($cfg['extra'])) {
            parse_str($cfg['extra'], $extra);
            $params += $extra;
        }

        $req = Http::timeout(15);
        $res = strtoupper($cfg['method'] ?? 'POST') === 'GET'
            ? $req->get($cfg['url'], $params)
            : $req->asForm()->post($cfg['url'], $params);

        // Many operator gateways answer 200 with a failure code in the body, so
        // an expected marker can be required on top of the HTTP status.
        $ok = $res->successful()
            && (empty($cfg['success_contains']) || str_contains($res->body(), $cfg['success_contains']));

        if (! $ok) {
            Log::error('amarati.sms.rejected', ['driver' => 'http', 'status' => $res->status(), 'body' => mb_substr($res->body(), 0, 300)]);
        }

        return $ok;
    }

    /// Take one unit of today's sending budget, or report that it is spent.
    ///
    /// Counted for real sends only: the log driver spends nothing, so a
    /// development box is never throttled by a limit that means nothing there.
    private function claimDailyBudget(): bool
    {
        $cap = (int) config('amarati.sms.daily_cap');
        if ($cap <= 0 || ! self::channelIsLive('sms')) {
            return true;
        }

        $key = 'amarati-sms-sent:'.now()->toDateString();
        $sent = (int) Cache::get($key, 0);
        if ($sent >= $cap) {
            return false;
        }

        // Expires on its own at the end of the day; nothing has to sweep it.
        Cache::put($key, $sent + 1, now()->endOfDay());

        return true;
    }

    /// How much of today's budget is left. Zero means codes are not going out.
    public static function remainingDailyBudget(): int
    {
        $cap = (int) config('amarati.sms.daily_cap');
        if ($cap <= 0) {
            return PHP_INT_MAX;
        }

        return max(0, $cap - (int) Cache::get('amarati-sms-sent:'.now()->toDateString(), 0));
    }

    /// Development default: the message goes to the log, never to a person.
    private function viaLog(string $channel, string $to, string $text): bool
    {
        Log::info("amarati.$channel.log-driver", ['to' => $this->mask($to), 'text' => $text]);

        return true;
    }

    // ───────────────────────────── helpers ─────────────────────────────

    /// E.164 for the gateway: local Palestinian numbers (059…/056…) are sent as
    /// +970…, anything already carrying a country code is left alone.
    public function normalisePhone(string $phone): string
    {
        $p = preg_replace('/[^0-9+]/', '', $phone);
        if (str_starts_with($p, '+')) {
            return $p;
        }
        if (str_starts_with($p, '00')) {
            return '+'.substr($p, 2);
        }
        if (str_starts_with($p, '0')) {
            return '+970'.substr($p, 1);
        }

        return '+'.$p;
    }

    /// Never write a full phone/e-mail into a log line.
    private function mask(string $v): string
    {
        return mb_strlen($v) <= 4 ? '***' : mb_substr($v, 0, 3).str_repeat('*', max(0, mb_strlen($v) - 6)).mb_substr($v, -3);
    }
}
