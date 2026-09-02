<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->defineRateLimits();
    }

    /// سكن برو — the API's rate limits, as NAMED limiters.
    ///
    /// They were written into the route file as `throttle:6,1`, which reads its
    /// number when the routes are REGISTERED. Two consequences: `route:cache`
    /// freezes the number into the cached file, so changing the env var on a
    /// deployed server does nothing until the cache is rebuilt; and nothing can
    /// vary it per request. Named limiters read config on every request instead.
    private function defineRateLimits(): void
    {
        // Sign-in, registration, and every code-issuing endpoint. Per IP, because
        // the whole point is the caller has not proven who they are yet.
        RateLimiter::for('amarati-auth', fn (Request $r) => Limit::perMinute(
            (int) config('amarati.auth_rate', 6)
        )->by($r->ip()));

        // A signed-in session. Keyed by ACCOUNT, so one noisy device cannot
        // throttle a colleague sharing an office IP — and a stolen token cannot
        // pull the platform's data at machine speed.
        RateLimiter::for('amarati-api', fn (Request $r) => Limit::perMinute(
            (int) config('amarati.api_rate', 240)
        )->by($r->user()?->getAuthIdentifier() ?: $r->ip()));

        // The handful of endpoints that need no token at all.
        RateLimiter::for('amarati-public', fn (Request $r) => Limit::perMinute(
            (int) config('amarati.public_rate', 60)
        )->by($r->ip()));
    }
}
