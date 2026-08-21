<?php

namespace App\Http\Controllers;

use App\Models\EmailCode;
use App\Models\OtpCode;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    private function payload(User $user): array
    {
        return [
            'token' => $user->createToken('amarati')->plainTextToken,
            'user' => $user->only(['id', 'name', 'email', 'phone', 'role', 'building_id', 'building_key', 'unit_no'])
                // The same person can hold an account in several buildings, so a
                // session must say which building it is for.
                + ['building_name' => $user->building?->name],
        ];
    }

    /// The "which building?" answer when one identifier matches accounts in more
    /// than one building. The client re-sends the same credentials plus the
    /// chosen building_id. Deliberately thin — it is returned before the caller
    /// has proven anything beyond the password matching that specific account.
    private function chooseBuilding($candidates)
    {
        return response()->json([
            'choose' => $candidates->map(fn (User $u) => [
                'building_id' => $u->building_id,
                'building_name' => $u->building?->name ?? '',
                'building_key' => $u->building_key,
                'role' => $u->role,
                'unit_no' => $u->unit_no,
            ])->values(),
        ]);
    }

    /// Whether to return the OTP / email code in the HTTP response (dev + e2e only).
    /// Honoured locally and in tests. AMARATI_EXPOSE_OTP_DEV_CODE is an explicit
    /// demo-mode opt-in on top of that — it must never be set on a real production
    /// deployment, since it turns every resident's phone into a one-request
    /// account takeover, but when it IS set (demo deploys) it is the control.
    private function exposesDevCode(): bool
    {
        return app()->environment(['local', 'testing'])
            || (bool) config('amarati.expose_otp_dev_code');
    }

    /// A short, unique, uppercase login code (QR / shareable). 8 hex chars.
    private function loginCode(): string
    {
        do {
            // 128-bit CSPRNG code (the resident's standing login credential; it
            // must stay readable to render the admin-side QR, so it isn't hashed).
            $code = strtoupper(bin2hex(random_bytes(16)));
        } while (User::where('login_code', $code)->exists());

        return $code;
    }

    public function register(Request $r)
    {
        $data = $r->validate([
            'name' => 'required|string|max:120',
            // Identity is unique WITHIN a building. A self-registering manager
            // has no building yet, so they are checked against the other
            // building-less accounts only — the same person may already be a
            // resident somewhere, and that must not block them.
            'email' => ['required', 'email', Rule::unique('users', 'email')->whereNull('building_id')],
            'phone' => ['nullable', 'string', 'max:32', Rule::unique('users', 'phone')->whereNull('building_id')],
            'whatsapp' => 'nullable|string|max:32',
            'password' => 'required|string|min:6',
            'email_code' => 'nullable|string',
        ]);
        // Validation above (unique email/phone) has already passed, so a
        // duplicate never reaches — and thus never consumes — the email code.
        // Verify the code as part of account creation: a wrong code fails here
        // WITHOUT creating the user, and (crucially) a later failure can't strand
        // an already-consumed code so the correct code reads as "wrong" on retry.
        $emailVerified = false;
        if (! empty($data['email_code'])) {
            $this->consumeEmailCodeOrFail($data['email'], $data['email_code']);
            $emailVerified = true;
        }

        // SECURITY: role is never accepted from a public endpoint. New accounts
        // are always unprivileged residents; promotion to admin must be done by
        // an existing admin through a separate, authorized flow.
        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'phone' => $data['phone'] ?? null,
            'whatsapp' => $data['whatsapp'] ?? null,
            'password' => Hash::make($data['password']),
            'role' => 'resident',
            // Multi-building: a fresh registrant is a pending manager with NO
            // building yet — they create their own at building-setup. building_key
            // is deliberately NOT accepted from the request: it is a type, not a
            // building, and honouring it would scope the new account into whatever
            // building happened to be first of that type (a stranger's).
            'building_key' => null,
            'email_verified_at' => $emailVerified ? now() : null,
        ]);

        return response()->json($this->payload($user), 201);
    }

    public function login(Request $r)
    {
        // Identifier is EITHER email OR phone (plus password).
        $data = $r->validate([
            'email' => 'required_without:phone|email',
            'phone' => 'required_without:email|string|max:32',
            'password' => 'required|string|max:200',
            // Set on the second call when the first returned a `choose` list.
            'building_id' => 'nullable|integer',
        ]);
        $q = isset($data['email'])
            ? User::where('email', $data['email'])
            : User::where('phone', $data['phone']);
        if (! empty($data['building_id'])) {
            $q->where('building_id', $data['building_id']);
        }

        // Every account this identifier + password opens. One person may hold an
        // account in several buildings, each with its own password.
        $candidates = $q->get()->filter(fn (User $u) => ! $u->isDisabled()
            && $u->password && Hash::check($data['password'], $u->password))->values();

        if ($candidates->isEmpty()) {
            throw ValidationException::withMessages(['email' => ['بيانات الدخول غير صحيحة']]);
        }
        if ($candidates->count() > 1) {
            return $this->chooseBuilding($candidates);
        }

        return response()->json($this->payload($candidates->first()));
    }

    public function requestEmailCode(Request $r)
    {
        $data = $r->validate(['email' => 'required|email']);

        // Invalidate any outstanding codes for this email, then issue one fresh
        // 6-digit code stored only as a hash.
        EmailCode::where('email', $data['email'])->where('used', false)->update(['used' => true]);
        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        EmailCode::create([
            'email' => $data['email'],
            'code' => Hash::make($code),
            'expires_at' => now()->addMinutes(10),
        ]);

        // In production this is sent over SMTP. Locally — or on a demo deploy with
        // AMARATI_EXPOSE_OTP_DEV_CODE=true — we return it so the email-verify flow
        // is testable without a mail provider.
        $body = ['sent' => true];
        if ($this->exposesDevCode()) {
            $body['dev_code'] = $code;
        }

        return response()->json($body);
    }

    public function verifyEmailCode(Request $r)
    {
        $data = $r->validate([
            'email' => 'required|email',
            'code' => 'required|string|max:64',
        ]);

        $this->consumeEmailCodeOrFail($data['email'], $data['code']);

        // If an account already uses this email, mark it verified.
        User::where('email', $data['email'])->whereNull('email_verified_at')
            ->update(['email_verified_at' => now()]);

        return response()->json(['verified' => true]);
    }

    /// Verify + consume the latest email code for [email]. Throws a 422 on a
    /// wrong/expired code (incrementing attempts, locking after 5) and only marks
    /// the code used on success — shared by verify-email-code and register so the
    /// two never double-consume a code.
    private function consumeEmailCodeOrFail(string $email, string $code): void
    {
        $ec = EmailCode::where('email', $email)
            ->where('used', false)
            ->where('expires_at', '>', now())
            ->latest()
            ->first();

        $invalid = fn () => throw ValidationException::withMessages(
            ['code' => ['رمز التحقق غير صحيح أو منتهٍ']]
        );

        if (! $ec) {
            $invalid();
        }
        if ($ec->attempts >= 5) {
            $ec->update(['used' => true]);
            $invalid();
        }
        if (! Hash::check($code, $ec->code)) {
            $ec->increment('attempts');
            $invalid();
        }
        $ec->update(['used' => true]);
    }

    /// QR / short-code resident login: the code is matched case-insensitively.
    /// SINGLE-USE — the code is rotated on redeem so the same QR/link cannot mint
    /// logins on unlimited devices forever (a scanned/reused code stops working
    /// after first use). The resident's durable login is their password; the
    /// admin can regenerate/see the new code any time.
    public function redeemCode(Request $r)
    {
        $data = $r->validate(['code' => 'required|string|max:64']);
        $user = User::where('login_code', strtoupper(trim($data['code'])))->first();
        if (! $user || $user->isDisabled()) {
            throw ValidationException::withMessages(['code' => ['رمز الدخول غير صحيح']]);
        }

        $payload = $this->payload($user);       // mint the token BEFORE rotating
        $user->update(['login_code' => $this->loginCode()]); // invalidate the used code

        return response()->json($payload);
    }

    public function requestOtp(Request $r)
    {
        $data = $r->validate(['phone' => 'required|string|max:32']);

        // Invalidate any outstanding codes for this phone, then issue one fresh
        // 6-digit code stored only as a hash.
        OtpCode::where('phone', $data['phone'])->where('used', false)->update(['used' => true]);
        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        OtpCode::create([
            'phone' => $data['phone'],
            'code' => Hash::make($code),
            'expires_at' => now()->addMinutes(10),
        ]);

        // In production this is sent over SMS. Locally — or on a demo deploy with
        // AMARATI_EXPOSE_OTP_DEV_CODE=true — we return it so the phone-login flow
        // is testable without an SMS provider.
        $body = ['sent' => true];
        if ($this->exposesDevCode()) {
            $body['dev_code'] = $code;
        }

        return response()->json($body);
    }

    public function verifyOtp(Request $r)
    {
        $data = $r->validate([
            'phone' => 'required|string|max:32',
            'code' => 'required|string|max:64',
            'building_key' => 'in:residential,commercial',
            // Which building's account to open, when the number matches several.
            'building_id' => 'nullable|integer',
            // Optional full name captured on first sign-up (used only when the
            // phone-only account is created; never overwrites an existing one).
            'name' => 'nullable|string|max:120',
        ]);

        $otp = OtpCode::where('phone', $data['phone'])
            ->where('used', false)
            ->where('expires_at', '>', now())
            ->latest()
            ->first();

        $invalid = fn () => throw ValidationException::withMessages(
            ['code' => ['رمز التحقق غير صحيح أو منتهٍ']]
        );

        if (! $otp) {
            $invalid();
        }
        if ($otp->attempts >= 5) {
            $otp->update(['used' => true]);
            $invalid();
        }
        if (! Hash::check($data['code'], $otp->code)) {
            $otp->increment('attempts');
            $invalid();
        }

        $accounts = User::where('phone', $data['phone'])->get()
            ->filter(fn (User $u) => ! $u->isDisabled())->values();
        if ($r->filled('building_id')) {
            $accounts = $accounts->where('building_id', (int) $r->input('building_id'))->values();
        }
        // Password-holders can't be opened by OTP (below), so the choice is only
        // ever between the passwordless accounts.
        $passwordless = $accounts->filter(fn (User $u) => ! $u->password)->values();
        if ($passwordless->count() > 1) {
            // Return the picker WITHOUT consuming the code — the client re-sends
            // the same code with a building_id, and it is still valid.
            return $this->chooseBuilding($passwordless);
        }
        $user = $passwordless->first() ?? $accounts->first();

        // Renters never self-register: an account only exists if a manager issued
        // a QR/invite or approved a join request. An OTP for an unknown phone is
        // rejected (it must NOT silently create a resident account). A disabled
        // (moved-out) account is treated the same — it cannot be signed into.
        if (! $user || $user->isDisabled()) {
            throw ValidationException::withMessages(
                ['phone' => ['لا يوجد حساب لهذا الرقم — انضم عبر رمز/رابط من مسؤول العمارة']]
            );
        }

        // SECURITY: never let an OTP take over a password-protected account
        // (e.g. an admin). Those must authenticate with their password. Check
        // this BEFORE consuming the code, so a valid OTP isn't wasted on a login
        // that can't succeed anyway (mirrors the register fix).
        if ($user->password) {
            throw ValidationException::withMessages(
                ['phone' => ['هذا الرقم مرتبط بحساب بكلمة مرور — سجّل الدخول بكلمة المرور']]
            );
        }

        // All checks passed — now consume the code.
        $otp->update(['used' => true]);

        return response()->json($this->payload($user));
    }

    public function me(Request $r)
    {
        return response()->json([
            'user' => $r->user()->only(['id', 'name', 'email', 'phone', 'role', 'building_id', 'building_key', 'unit_no']),
        ]);
    }

    public function logout(Request $r)
    {
        $r->user()->currentAccessToken()->delete();

        return response()->json(['ok' => true]);
    }
}
