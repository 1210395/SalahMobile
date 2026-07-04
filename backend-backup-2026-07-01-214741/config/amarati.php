<?php

// عمارتي — app-specific runtime flags.
return [

    // When true, the OTP request endpoint returns the generated code in its JSON
    // response (`dev_code`) so the phone-login flow is testable without an SMS
    // provider. This is implicitly on in the `local` environment; set
    // AMARATI_EXPOSE_OTP_DEV_CODE=true to also enable it on a hosted demo.
    'expose_otp_dev_code' => env('AMARATI_EXPOSE_OTP_DEV_CODE', false),

];
