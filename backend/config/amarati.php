<?php

// عمارتي — app-specific runtime flags.
return [

    // When true, the OTP request endpoint returns the generated code in its JSON
    // response (`dev_code`) so the phone-login flow is testable without an SMS
    // provider. This is implicitly on in the `local` environment; set
    // AMARATI_EXPOSE_OTP_DEV_CODE=true to also enable it on a hosted demo.
    'expose_otp_dev_code' => env('AMARATI_EXPOSE_OTP_DEV_CODE', false),

    // Per-minute request cap on the auth endpoints (login / register / OTP /
    // email-code / redeem) — blunts credential stuffing + code brute force.
    // Defaults to 6/min in production; raise only for automated test runs via
    // AMARATI_AUTH_RATE (e.g. the e2e suite hammers auth far faster than a human).
    'auth_rate' => (int) env('AMARATI_AUTH_RATE', 6),

];
