<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// عمارتي — landing page for a shared invite link (imarty.olive-dev.com/join/CODE).
// Without this the URL 404s. It guides the recipient to install the app and sign
// in with their QR/code (it does NOT auto-log-in — the code shown is only the
// building-invite reference, not a credential). AMARATI_APP_URL points at the
// APK / store listing.
Route::get('/join/{code?}', function (?string $code = null) {
    return view('join', [
        'code' => $code ? preg_replace('/[^A-Za-z0-9\-]/', '', substr($code, 0, 40)) : null,
        'appUrl' => env('AMARATI_APP_URL', 'https://github.com/1210395/SalahMobile/releases/latest'),
    ]);
})->name('join');
