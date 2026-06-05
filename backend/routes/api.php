<?php

use App\Http\Controllers\ApiController;
use App\Http\Controllers\AuthController;
use Illuminate\Support\Facades\Route;

// ───────────────────────────── Auth ─────────────────────────────
// Rate-limited to blunt credential stuffing / OTP brute force.
Route::middleware('throttle:6,1')->group(function () {
    Route::post('/auth/register', [AuthController::class, 'register']);
    Route::post('/auth/login', [AuthController::class, 'login']);
    Route::post('/auth/request-otp', [AuthController::class, 'requestOtp']);
    Route::post('/auth/verify-otp', [AuthController::class, 'verifyOtp']);
});

// ───────────── Public (guest mode — general building data) ─────────────
Route::get('/building', [ApiController::class, 'building']);
Route::get('/summary', [ApiController::class, 'summary']);
Route::get('/pay-types', [ApiController::class, 'payTypes']);
Route::get('/wa-templates', [ApiController::class, 'waTemplates']);

// ───────────────────── Protected (signed-in users) ─────────────────────
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);

    Route::get('/units', [ApiController::class, 'units']);

    Route::get('/payments', [ApiController::class, 'payments']);
    Route::post('/payments', [ApiController::class, 'storePayment']);

    Route::get('/expenses', [ApiController::class, 'expenses']);
    Route::post('/expenses', [ApiController::class, 'storeExpense']);

    Route::get('/workers', [ApiController::class, 'workers']);
    Route::post('/workers', [ApiController::class, 'storeWorker']);

    Route::get('/parking', [ApiController::class, 'parking']);
    Route::get('/guard', [ApiController::class, 'guard']);

    Route::get('/craftsmen', [ApiController::class, 'craftsmen']);
    Route::post('/craftsmen', [ApiController::class, 'storeCraftsman']);

    Route::get('/alerts', [ApiController::class, 'alerts']);
    Route::get('/year-summary', [ApiController::class, 'yearSummary']);
});
