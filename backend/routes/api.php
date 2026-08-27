<?php

use App\Http\Controllers\ApiController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\NoteController;
use App\Http\Controllers\OnboardingController;
use App\Http\Controllers\SettingsController;
use App\Http\Controllers\SuperAdminController;
use App\Http\Controllers\UnitController;
use Illuminate\Support\Facades\Route;

// ───────────────────────────── Auth ─────────────────────────────
// Rate-limited to blunt credential stuffing / OTP brute force (6/min in prod;
// configurable via AMARATI_AUTH_RATE so automated e2e runs aren't throttled).
Route::middleware('throttle:'.config('amarati.auth_rate', 6).',1')->group(function () {
    Route::post('/auth/register', [AuthController::class, 'register']);
    Route::post('/auth/login', [AuthController::class, 'login']);
    Route::post('/auth/request-otp', [AuthController::class, 'requestOtp']);
    Route::post('/auth/verify-otp', [AuthController::class, 'verifyOtp']);
    Route::post('/auth/request-email-code', [AuthController::class, 'requestEmailCode']);
    Route::post('/auth/verify-email-code', [AuthController::class, 'verifyEmailCode']);
    Route::post('/auth/redeem-code', [AuthController::class, 'redeemCode']);
    // Password recovery for a manager — the only account type that signs in with
    // a password it chose itself. Without this, a forgotten password locked the
    // building's manager out permanently.
    Route::post('/auth/forgot-password', [AuthController::class, 'forgotPassword']);
    Route::post('/auth/reset-password', [AuthController::class, 'resetPassword']);
});

// ───────────── Public (brand theming + onboarding only) ─────────────
// Only non-sensitive branding/onboarding data is public — the building shell
// (name/theme) and the fee catalogue. Financials (/summary) are NOT public.
Route::get('/building', [ApiController::class, 'building']);
Route::get('/pay-types', [ApiController::class, 'payTypes']);
Route::get('/settings', [SettingsController::class, 'index']);

// Subscription query only (doesn't need auth)
Route::get('/subscription', [OnboardingController::class, 'subscription']);

// ───────────────────── Protected (signed-in users) ─────────────────────
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::get('/me/payments', [ApiController::class, 'myPayments']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    // Financials + messaging templates require login (no public exposure).
    Route::get('/summary', [ApiController::class, 'summary']);
    Route::get('/wa-templates', [ApiController::class, 'waTemplates']);

    // The building directory a signed-in user picks from (join / create-admin).
    // Behind auth: a building's existence is not public information.
    Route::get('/buildings', [ApiController::class, 'buildings']);

    // Building data (reads scoped to the user's building; admin may pass ?btype)
    Route::get('/units', [ApiController::class, 'units']);
    Route::post('/units', [UnitController::class, 'store']);
    Route::put('/units/{unit}', [UnitController::class, 'update']);
    Route::delete('/units/{unit}', [UnitController::class, 'destroy']);

    Route::put('/building', [ApiController::class, 'updateBuilding']);

    // Admin creates a renter account / a co-admin for their own building.
    Route::post('/residents', [ApiController::class, 'storeResident']);
    // Set (or create) the login for the renter on a unit — a renter added before
    // logins were mandatory had no way to ever get one, and a forgotten password
    // could not be reset from anywhere.
    Route::post('/units/{unit}/password', [ApiController::class, 'setUnitPassword']);
    // كشف حساب الساكن — personal record + both pots + a dated statement.
    Route::get('/units/{unit}/statement', [ApiController::class, 'unitStatement']);
    Route::post('/co-admins', [ApiController::class, 'createCoAdmin']);

    Route::get('/payments', [ApiController::class, 'payments']);
    Route::post('/payments', [ApiController::class, 'storePayment']);
    Route::put('/payments/{payment}', [ApiController::class, 'updatePayment']);
    Route::delete('/payments/{payment}', [ApiController::class, 'deletePayment']);

    Route::get('/expenses', [ApiController::class, 'expenses']);
    Route::post('/expenses', [ApiController::class, 'storeExpense']);
    Route::put('/expenses/{expense}', [ApiController::class, 'updateExpense']);
    Route::delete('/expenses/{expense}', [ApiController::class, 'deleteExpense']);

    Route::get('/workers', [ApiController::class, 'workers']);
    Route::post('/workers', [ApiController::class, 'storeWorker']);
    Route::put('/workers/{worker}', [ApiController::class, 'updateWorker']);
    Route::delete('/workers/{worker}', [ApiController::class, 'destroyWorker']);

    Route::get('/parking', [ApiController::class, 'parking']);
    Route::post('/parking', [ApiController::class, 'storeParking']);
    Route::put('/parking/{parking}', [ApiController::class, 'updateParking']);
    Route::delete('/parking/{parking}', [ApiController::class, 'deleteParking']);

    Route::get('/guard', [ApiController::class, 'guard']);
    Route::put('/guard', [ApiController::class, 'storeGuard']);
    Route::put('/pay-types/{payType}', [ApiController::class, 'updatePayType']);

    Route::get('/craftsmen', [ApiController::class, 'craftsmen']);
    Route::post('/craftsmen', [ApiController::class, 'storeCraftsman']);

    Route::get('/alerts', [ApiController::class, 'alerts']);
    Route::post('/alerts/regenerate', [ApiController::class, 'regenerateAlerts']);
    Route::post('/notifications', [ApiController::class, 'storeNotification']);
    Route::get('/year-summary', [ApiController::class, 'yearSummary']);

    // Resident → admin notes
    Route::post('/notes', [NoteController::class, 'store']);
    Route::get('/notes', [NoteController::class, 'index']);
    Route::post('/notes/{note}/read', [NoteController::class, 'markRead']);

    // Onboarding — subscription activation, building setup (promotes to admin), joins
    Route::post('/subscription/activate', [OnboardingController::class, 'activateSubscription']);
    Route::post('/building/setup', [OnboardingController::class, 'setupBuilding']);
    Route::post('/join-requests', [OnboardingController::class, 'storeJoinRequest']);
    Route::get('/join-requests', [OnboardingController::class, 'joinRequests']);
    Route::post('/join-requests/{joinRequest}/approve', [OnboardingController::class, 'approveJoinRequest']);
    Route::post('/join-requests/{joinRequest}/reject', [OnboardingController::class, 'rejectJoinRequest']);

    // Brand / app settings (admin write)
    Route::put('/settings', [SettingsController::class, 'update']);
    Route::post('/settings/logo', [SettingsController::class, 'uploadLogo']);

    // Super-admin (platform owner): manage admins + global report
    Route::get('/admins', [SuperAdminController::class, 'admins']);
    Route::post('/admins', [SuperAdminController::class, 'createAdmin']);
    Route::get('/reports/global', [SuperAdminController::class, 'globalReport']);
});
