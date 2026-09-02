<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Deployed behind Cloudflare + Traefik (Coolify). Trust only the
        // internal proxy hop — the app's immediate peer is always the Traefik
        // container on a private Docker network — so X-Forwarded-For is honoured
        // for real-client-IP detection (the throttle:6,1 limiter keys off it)
        // WITHOUT letting an external client forge XFF to spoof their IP / dodge
        // the rate limit. Trusting '*' would make XFF client-spoofable.
        $middleware->trustProxies(at: [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '127.0.0.1',
            '::1',
        ], headers: Request::HEADER_X_FORWARDED_FOR
            | Request::HEADER_X_FORWARDED_HOST
            | Request::HEADER_X_FORWARDED_PORT
            | Request::HEADER_X_FORWARDED_PROTO);
        // An unauthenticated API call must answer 401. Laravel's default tries
        // to redirect a guest to a `login` ROUTE, which an API-only app has no
        // reason to define — so every token-less request that did not happen to
        // send `Accept: application/json` blew up as a 500 and wrote a full stack
        // trace to the log (110 of them so far). Returning null here makes the
        // middleware throw AuthenticationException instead, which the JSON
        // renderer below turns into a clean 401.
        $middleware->redirectGuestsTo(fn (Request $request) => $request->is('api/*') ? null : '/');

        // The hosted card page authenticates on the one-time secret in its URL,
        // not on a session. A CSRF token adds nothing there — an attacker who
        // could forge the request would need that secret, and having it they
        // would not need forgery — while it can take a payment down: a browser
        // that drops the session cookie, or a page left open past the session
        // lifetime, answers 419 AFTER the card form has already succeeded, and
        // the transient token is spent for nothing.
        $middleware->validateCsrfTokens(except: ['pay/*']);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*'),
        );
    })->create();
