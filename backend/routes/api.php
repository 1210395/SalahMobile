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
// Rate-limited to blunt credential stuffing / OTP brute force.
Route::middleware('throttle:6,1')->group(function () {
    Route::post('/auth/register', [AuthController::class, 'register']);
    Route::post('/auth/login', [AuthController::class, 'login']);
    Route::post('/auth/request-otp', [AuthController::class, 'requestOtp']);
    Route::post('/auth/verify-otp', [AuthController::class, 'verifyOtp']);
});

// ───────────── Public (guest mode + brand theming) ─────────────
Route::get('/building', [ApiController::class, 'building']);
Route::get('/summary', [ApiController::class, 'summary']);
Route::get('/pay-types', [ApiController::class, 'payTypes']);
Route::get('/wa-templates', [ApiController::class, 'waTemplates']);
Route::get('/settings', [SettingsController::class, 'index']);

// ───────────────────── Protected (signed-in users) ─────────────────────
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::get('/me/payments', [ApiController::class, 'myPayments']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);

    // Building data (reads scoped to the user's building; admin may pass ?btype)
    Route::get('/units', [ApiController::class, 'units']);
    Route::post('/units', [UnitController::class, 'store']);
    Route::put('/units/{unit}', [UnitController::class, 'update']);
    Route::delete('/units/{unit}', [UnitController::class, 'destroy']);

    Route::put('/building', [ApiController::class, 'updateBuilding']);

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
    Route::post('/alerts/regenerate', [ApiController::class, 'regenerateAlerts']);
    Route::get('/year-summary', [ApiController::class, 'yearSummary']);

    // Resident → admin notes
    Route::post('/notes', [NoteController::class, 'store']);
    Route::get('/notes', [NoteController::class, 'index']);
    Route::post('/notes/{note}/read', [NoteController::class, 'markRead']);

    // Onboarding — subscription, building setup (promotes to admin), joins
    Route::get('/subscription', [OnboardingController::class, 'subscription']);
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
