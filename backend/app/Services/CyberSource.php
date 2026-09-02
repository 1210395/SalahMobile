<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

// سكن برو — card payments through Arab Bank's CyberSource account.
//
// Unified Checkout keeps the card number away from us entirely: the browser
// talks to CyberSource directly and hands back a short-lived "transient token"
// that stands in for the card. Nothing here ever sees a PAN, which is the whole
// reason for the extra round trip.
//
// The three steps:
//   1. captureContext()  — we ask CyberSource what this payment is, and get a
//                          signed JWT that authorises the browser to collect it
//   2. the browser       — CyberSource's SDK renders the form and returns a
//                          transient token (see resources/views/pay.blade.php)
//   3. pay()             — we charge that token
//
// Requests are authenticated with CyberSource's HTTP Signature scheme rather
// than a bearer token: a per-request HMAC over a fixed set of headers. The
// shared secret therefore never travels, and a captured request cannot be
// replayed against a different body or a different merchant.
class CyberSource
{
    /// Whether real card payments are configured. Everything that offers to take
    /// money checks this first — an unconfigured gateway must present no payment
    /// UI at all rather than a form that cannot work.
    public static function isConfigured(): bool
    {
        $c = config('amarati.payments');

        return ! empty($c['merchant_id']) && ! empty($c['key_id']) && ! empty($c['secret_key']);
    }

    /// The configured price in minor units, or null if it is not a price.
    ///
    /// A plain (float) cast reads "1,000.00" as 1.0 and would charge one dollar
    /// for a thousand — silently, and in our favour never. A value we cannot
    /// read exactly is refused instead of guessed at.
    public static function configuredAmount(): ?int
    {
        $raw = trim((string) config('amarati.payments.amount'));
        if (! preg_match('/^\d{1,9}(\.\d{1,2})?$/', $raw)) {
            return null;
        }

        $minor = (int) round(((float) $raw) * 100);

        return $minor > 0 ? $minor : null;
    }

    private function host(): string
    {
        return config('amarati.payments.host');
    }

    /// Step 1 — describe the payment and get the JWT that lets the browser
    /// collect it. [$origin] must be exactly the site the form is embedded in;
    /// CyberSource refuses to render anywhere else, which is what stops the
    /// context being lifted into someone else's page.
    public function captureContext(string $origin, string $reference, string $amount, string $currency): string
    {
        $body = [
            'targetOrigins' => [$origin],
            'clientVersion' => '0.24',
            'allowedCardNetworks' => ['VISA', 'MASTERCARD'],
            'allowedPaymentTypes' => ['PANENTRY'],
            'country' => config('amarati.payments.country'),
            'locale' => config('amarati.payments.locale'),
            'captureMandate' => [
                'billingType' => 'NONE',
                'requestEmail' => false,
                'requestPhone' => false,
                'requestShipping' => false,
                'showAcceptedNetworkIcons' => true,
            ],
            'orderInformation' => [
                'amountDetails' => ['totalAmount' => $amount, 'currency' => $currency],
            ],
        ];

        $res = $this->send('post', '/up/v1/capture-contexts', $body);

        // This endpoint answers with a bare JWT, not JSON.
        $jwt = trim($res->body());
        if (! $res->successful() || substr_count($jwt, '.') !== 2) {
            Log::error('amarati.pay.context_failed', ['status' => $res->status(), 'body' => mb_substr($jwt, 0, 300)]);
            throw new RuntimeException('تعذّر بدء عملية الدفع');
        }

        return $jwt;
    }

    /// Step 3 — charge the transient token the browser handed back.
    ///
    /// [$reference] is our own order id and is sent as the merchant reference so
    /// a payment can always be traced back to the subscription it belongs to,
    /// from either side of the integration.
    public function pay(string $transientToken, string $reference, string $amount, string $currency): array
    {
        // The dangerous case is not a decline, it is a LOST ANSWER: the card is
        // charged and the response never arrives. Retrying then charges twice.
        // Our own order id is sent as the idempotency key, so a repeat of this
        // exact payment returns the original result instead of taking the money
        // again — which is what makes retrying safe at all.
        $res = $this->send('post', '/pts/v2/payments', [
            'clientReferenceInformation' => ['code' => $reference],
            'processingInformation' => ['capture' => true],
            'tokenInformation' => ['transientTokenJwt' => $transientToken],
            'orderInformation' => [
                'amountDetails' => ['totalAmount' => $amount, 'currency' => $currency],
            ],
        ], ['v-c-idempotency-id' => $reference]);

        $json = $res->json() ?? [];
        $status = $json['status'] ?? 'UNKNOWN';

        if (! $res->successful()) {
            Log::error('amarati.pay.declined', [
                'reference' => $reference,
                'http' => $res->status(),
                'status' => $status,
                'reason' => $json['errorInformation']['reason'] ?? ($json['reason'] ?? null),
            ]);
        }

        return [
            // ONLY an authorised capture is money. Everything else is a hold, a
            // review, or a different rail: AUTHORIZED_PENDING_REVIEW can still be
            // reversed by the bank, and PENDING belongs to the transfer rails we
            // do not accept. Any of them read as paid would hand out a
            // subscription nobody paid for.
            'paid' => $res->successful() && $status === 'AUTHORIZED',
            'status' => $status,
            'id' => $json['id'] ?? null,
            'reason' => $json['errorInformation']['reason'] ?? ($json['errorInformation']['message'] ?? null),
        ];
    }

    /// Where the browser should load CyberSource's SDK from, and the integrity
    /// hash that pins it.
    ///
    /// Both travel inside the capture context, so the page always loads the
    /// build that matches the context it was issued — pinning a version here
    /// would drift the day CyberSource moves theirs.
    public static function clientLibrary(string $captureContext): array
    {
        $parts = explode('.', $captureContext);
        $payload = json_decode(base64_decode(strtr($parts[1] ?? '', '-_', '+/')), true) ?: [];
        $data = $payload['ctx'][0]['data'] ?? [];

        return [
            'url' => $data['clientLibrary'] ?? null,
            'integrity' => $data['clientLibraryIntegrity'] ?? null,
        ];
    }

    // ───────────────────────── HTTP Signature ─────────────────────────

    private function send(string $method, string $path, array $body, array $extraHeaders = [])
    {
        if (! self::isConfigured()) {
            throw new RuntimeException('بوابة الدفع غير مهيأة');
        }

        $payload = json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $date = gmdate('D, d M Y H:i:s \G\M\T');
        $digest = 'SHA-256='.base64_encode(hash('sha256', $payload, true));

        return Http::withHeaders([
            'v-c-merchant-id' => config('amarati.payments.merchant_id'),
            'Date' => $date,
            'Host' => $this->host(),
            'Digest' => $digest,
            'Signature' => $this->signature($method, $path, $date, $digest),
            'Content-Type' => 'application/json',
            'Accept' => 'application/json',
        ] + $extraHeaders)->withBody($payload, 'application/json')
            ->timeout(30)
            ->send(strtoupper($method), 'https://'.$this->host().$path);
    }

    /// The signature header CyberSource expects: an HMAC-SHA256, over the named
    /// headers in the stated order, keyed with the base64-decoded shared secret.
    /// The header list is part of the signed material, so nothing can be dropped
    /// from it in transit without the signature failing.
    private function signature(string $method, string $path, string $date, string $digest): string
    {
        $merchant = config('amarati.payments.merchant_id');
        $headers = 'host date (request-target) digest v-c-merchant-id';

        $signing = implode("\n", [
            'host: '.$this->host(),
            'date: '.$date,
            '(request-target): '.strtolower($method).' '.$path,
            'digest: '.$digest,
            'v-c-merchant-id: '.$merchant,
        ]);

        $mac = base64_encode(hash_hmac(
            'sha256', $signing,
            base64_decode(config('amarati.payments.secret_key')), true,
        ));

        return sprintf(
            'keyid="%s", algorithm="HmacSHA256", headers="%s", signature="%s"',
            config('amarati.payments.key_id'), $headers, $mac,
        );
    }
}
