<?php

// عمارتي — app-specific runtime flags.
return [

    // Echo the generated code back in the API response, per channel.
    //
    // It is IGNORED whenever a real provider is configured for that channel (see
    // Notifier::channelIsLive), so wiring SMS or SMTP switches the echo off by
    // itself. The two channels are separate because their risk is not the same:
    // an echoed SMS code turns any resident's phone NUMBER into a one-request
    // account takeover, while an echoed e-mail code only lets someone confirm an
    // address they already typed. A host with no mail provider can therefore keep
    // registration working without leaving the takeover path open.
    //
    // AMARATI_EXPOSE_OTP_DEV_CODE sets both, and stays as the older name so an
    // existing deployment keeps behaving the way it was configured.
    'expose_otp_dev_code' => env('AMARATI_EXPOSE_OTP_DEV_CODE', false),
    'expose_sms_dev_code' => env('AMARATI_EXPOSE_SMS_DEV_CODE',
        env('AMARATI_EXPOSE_OTP_DEV_CODE', false)),
    'expose_email_dev_code' => env('AMARATI_EXPOSE_EMAIL_DEV_CODE',
        env('AMARATI_EXPOSE_OTP_DEV_CODE', false)),

    // Per-minute request cap on the auth endpoints (login / register / OTP /
    // email-code / redeem) — blunts credential stuffing + code brute force.
    // Defaults to 6/min in production; raise only for automated test runs via
    // AMARATI_AUTH_RATE (e.g. the e2e suite hammers auth far faster than a human).
    'auth_rate' => (int) env('AMARATI_AUTH_RATE', 6),

    // A manager's e-mail must be confirmed before the account is created. Turn
    // off only for a deployment with no mail provider at all.
    'require_email_verification' => (bool) env('AMARATI_REQUIRE_EMAIL_VERIFICATION', true),

    // How long a verification code stays valid.
    'code_ttl_minutes' => (int) env('AMARATI_CODE_TTL_MINUTES', 10),

    'sms' => [
        // log    — write the message to the Laravel log (development default)
        // twilio — Twilio REST API
        // http   — any gateway that takes a plain GET/POST (local operators)
        'driver' => env('SMS_DRIVER', 'log'),

        // The name/number the message comes from (Twilio: a purchased number or
        // messaging-service SID; http: usually an approved alphabetic sender).
        'from' => env('SMS_FROM', 'Amarati'),

        'twilio' => [
            'sid' => env('TWILIO_SID'),
            'token' => env('TWILIO_TOKEN'),
            // Optional: use a Messaging Service instead of a plain from-number.
            'messaging_service_sid' => env('TWILIO_MESSAGING_SERVICE_SID'),
        ],

        // Generic gateway: every field is env-driven so a local operator can be
        // wired without touching code. `url` is the endpoint; the three *_field
        // values name that gateway's parameter names; `extra` is any additional
        // static query pairs (api key, account id…) as `k=v&k2=v2`.
        'http' => [
            'url' => env('SMS_HTTP_URL'),
            'method' => env('SMS_HTTP_METHOD', 'POST'),
            'to_field' => env('SMS_HTTP_TO_FIELD', 'to'),
            'text_field' => env('SMS_HTTP_TEXT_FIELD', 'text'),
            'from_field' => env('SMS_HTTP_FROM_FIELD', 'from'),
            'extra' => env('SMS_HTTP_EXTRA'),
            // A response containing this string counts as accepted; leave empty
            // to accept any 2xx.
            'success_contains' => env('SMS_HTTP_SUCCESS_CONTAINS'),
        ],
    ],
];
