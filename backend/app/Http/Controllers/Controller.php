<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;

abstract class Controller
{
    /// The authenticated caller, whichever guard the route happens to configure.
    ///
    /// On a route inside `auth:sanctum` the middleware calls Auth::shouldUse(),
    /// so `$r->user()` resolves the token's owner. A PUBLIC route has no such
    /// middleware: the default guard is the session-based `web` one, so
    /// `$r->user()` is null even when a perfectly valid Bearer token is attached,
    /// which quietly demoted every caller to a guest. Ask the token guard
    /// explicitly so a public route still knows who is calling.
    protected function actor(Request $r): ?User
    {
        return $r->user() ?? $r->user('sanctum');
    }
}
