<?php

// سكن برو — app-specific runtime flags.
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

    // Everything else. The auth endpoints are the ones worth guessing at, but an
    // unthrottled API is still a free bulk export to anyone holding one token,
    // and the unauthenticated reads had no ceiling at all.
    'api_rate' => (int) env('AMARATI_API_RATE', 240),
    'public_rate' => (int) env('AMARATI_PUBLIC_RATE', 60),

    // A manager's e-mail must be confirmed before the account is created. Turn
    // off only for a deployment with no mail provider at all.
    'require_email_verification' => (bool) env('AMARATI_REQUIRE_EMAIL_VERIFICATION', true),

    // How long a verification code stays valid.
    'code_ttl_minutes' => (int) env('AMARATI_CODE_TTL_MINUTES', 10),

    // ─────────────────────────── card payments ───────────────────────────
    // Arab Bank's CyberSource account, through Unified Checkout. Leave the
    // credentials empty and the platform simply does not offer to take money —
    // subscriptions activate the way they did before a gateway existed, rather
    // than presenting a payment form that cannot work.
    'payments' => [
        // apitest.cybersource.com while testing; api.cybersource.com for real money.
        'host' => env('CYBERSOURCE_HOST', 'apitest.cybersource.com'),

        'merchant_id' => env('CYBERSOURCE_MERCHANT_ID'),
        'key_id' => env('CYBERSOURCE_KEY_ID'),
        'secret_key' => env('CYBERSOURCE_SECRET_KEY'),

        // The subscription price. Deliberately NOT a row a building manager can
        // edit — this is what the platform charges THEM.
        'amount' => env('AMARATI_SUBSCRIPTION_AMOUNT', '0.00'),
        'currency' => env('AMARATI_SUBSCRIPTION_CURRENCY', 'USD'),

        // How long one payment buys.
        'period_days' => (int) env('AMARATI_SUBSCRIPTION_PERIOD_DAYS', 365),

        'country' => env('CYBERSOURCE_COUNTRY', 'PS'),
        'locale' => env('CYBERSOURCE_LOCALE', 'ar_PS'),

        // How long a started checkout stays payable. The capture context itself
        // expires in about fifteen minutes, so the link must not outlive it.
        'checkout_ttl_minutes' => (int) env('AMARATI_CHECKOUT_TTL_MINUTES', 15),
    ],

    // The same restraint as SMS, for the same reason: request-email-code needs
    // no account, so without a per-address limit it is a way to bomb a
    // stranger's inbox from our domain — which costs us the sending reputation
    // that makes the codes arrive at all.
    'email_cooldown_seconds' => (int) env('EMAIL_COOLDOWN_SECONDS', 60),
    'email_per_address_hourly' => (int) env('EMAIL_PER_ADDRESS_HOURLY', 5),

    'sms' => [
        // log    — write the message to the Laravel log (development default)
        // htd    — HTD / sms.htd.ps, the Palestinian gateway in production
        // twilio — Twilio REST API
        // http   — any other gateway that takes a plain GET/POST
        'driver' => env('SMS_DRIVER', 'log'),

        // Which numbers the provider can actually REACH, as E.164 prefixes.
        // A local operator gateway serves Palestinian and Israeli numbers only,
        // so anyone abroad requesting an OTP would otherwise wait for a message
        // that was never going to arrive. Empty = no restriction (a global
        // provider such as Twilio).
        'coverage' => env('SMS_COVERAGE', '+970,+972'),

        // The name/number the message comes from (Twilio: a purchased number or
        // messaging-service SID; http: usually an approved alphabetic sender).
        'from' => env('SMS_FROM', 'Amarati'),

        // ─────────── spending limits ───────────
        // Sending is not free and the balance is finite: 1000 credits is 1000
        // codes. `request-otp` needs no account, so without a ceiling anyone
        // can drain the balance — and with it everyone's ability to sign in —
        // by asking for codes for numbers they do not own. This is the ordinary
        // SMS-pumping attack, and the per-IP throttle does not stop it because
        // an attacker simply uses more addresses.
        'daily_cap' => (int) env('SMS_DAILY_CAP', 300),

        // One person, one number: a code every minute at most, and a handful an
        // hour. Comfortably above anyone re-requesting a code they did not get.
        'cooldown_seconds' => (int) env('SMS_COOLDOWN_SECONDS', 60),
        'per_number_hourly' => (int) env('SMS_PER_NUMBER_HOURLY', 5),

        'htd' => [
            'url' => env('SMS_HTD_URL', 'https://sms.htd.ps/API/SendSMS.aspx'),

            // The API ID from the gateway's "My Account" page. It is the only
            // credential the send call carries, so it is a password: it lives in
            // .env and nowhere else. Sending is additionally locked to the
            // server's IP by an allow-list on the account itself.
            'id' => env('SMS_HTD_ID'),

            // Rewrite a Palestinian +970 number to this country code before
            // sending. The account was issued against 972; blank it to send the
            // number exactly as the app stores it.
            'country_code' => env('SMS_HTD_COUNTRY_CODE', '972'),
        ],

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
