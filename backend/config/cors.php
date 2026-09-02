<?php

// سكن برو — permissive CORS for the API (mobile app + local web review).
// Bearer-token auth (no cookies), so credentials support stays off.
return [
    'paths' => ['api/*', 'sanctum/csrf-cookie'],
    'allowed_methods' => ['*'],
    // The API is consumed by the mobile app (which is not subject to CORS at
    // all) and by our own web build. A wildcard let any website in a victim's
    // browser call it; these are the only origins that have a reason to.
    'allowed_origins' => array_values(array_filter(array_map('trim', explode(',', (string) env(
        'CORS_ALLOWED_ORIGINS',
        'https://imarty.olive-dev.com,https://imarti.olive-dev.com,https://amarati.olive-dev.com,http://127.0.0.1:8099,http://localhost:8099',
    ))))),
    'allowed_origins_patterns' => [],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => false,
];
