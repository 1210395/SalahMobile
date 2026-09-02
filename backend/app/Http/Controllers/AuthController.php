<?php

namespace App\Http\Controllers;

use App\Models\EmailCode;
use App\Models\OtpCode;
use App\Models\User;
use App\Services\Notifier;
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

    /// Whether the generated code may still be echoed in the HTTP response.
    ///
    /// A REAL provider on that channel always wins: once SMS or SMTP is
    /// configured the echo turns itself off, so a hosted deployment cannot be
    /// left handing out other people's login codes because an env var was
    /// forgotten. Without a provider, the echo is what keeps the flow usable in
    /// development and on a demo box.
    private function exposesDevCode(string $channel): bool
    {
        if (Notifier::channelIsLive($channel)) {
            return false;
        }

        return app()->environment(['local', 'testing'])
            || (bool) config($channel === 'sms'
                ? 'amarati.expose_sms_dev_code'
                : 'amarati.expose_email_dev_code');
    }

    /// Whether a manager must confirm their e-mail to register: only when the
    /// code can actually reach them (a live mailer, or the dev echo).
    private function emailVerificationRequired(): bool
    {
        return (bool) config('amarati.require_email_verification')
            && (Notifier::channelIsLive('mail') || $this->exposesDevCode('mail'));
    }

    /// Issue + store a fresh 6-digit code, invalidating any outstanding one.
    private function issueCode(string $model, string $key, string $value): string
    {
        $model::where($key, $value)->where('used', false)->update(['used' => true]);
        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $model::create([
            $key => $value,
            'code' => Hash::make($code),   // stored hashed - never in the clear
            'expires_at' => now()->addMinutes((int) config('amarati.code_ttl_minutes', 10)),
        ]);

        return $code;
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
            // This account will own a building's finances.
            'password' => 'required|string|min:8',
            // Required as soon as a code can actually reach the person — through a
            // real mailer, or the dev echo on a box without one. A deployment with
            // neither can still register (nobody could ever confirm).
            'email_code' => [
                $this->emailVerificationRequired() ? 'required' : 'nullable',
                'string', 'max:64',
            ],
        ], [
            // Arabic, like every other message the app surfaces — an APK already
            // in the field shows this text verbatim in its toast.
            'email_code.required' => 'أدخل رمز التأكيد المُرسَل إلى بريدك الإلكتروني',
            'email_code.max' => 'رمز التأكيد غير صحيح',
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

    public function requestEmailCode(Request $r, Notifier $notifier)
    {
        $data = $r->validate(['email' => 'required|email']);

        $code = $this->issueCode(EmailCode::class, 'email', $data['email']);
        $sent = $notifier->sendEmailCode($data['email'], $code);

        $body = ['sent' => $sent];
        if ($this->exposesDevCode('mail')) {
            $body['dev_code'] = $code;
        }
        // Nothing delivered it and nothing echoed it - say so, instead of leaving
        // the user waiting for a mail that will never arrive.
        abort_if(! $sent && ! isset($body['dev_code']), 503,
            'تعذّر إرسال رمز التحقق حالياً — حاول مرة أخرى بعد قليل');

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

    public function requestOtp(Request $r, Notifier $notifier)
    {
        $data = $r->validate(['phone' => 'required|string|max:32']);

        // The gateway we can buy serves Palestinian/Israeli numbers only. Say so
        // BEFORE issuing a code — a resident abroad must never be left waiting on
        // an SMS that was never going to arrive, with no way forward named.
        abort_if(! Notifier::coversNumber($data['phone']), 422,
            'إرسال رموز التحقق عبر SMS متاح حالياً للأرقام الفلسطينية والإسرائيلية '
            .'(+970 / +972) فقط. سجّل الدخول بكلمة المرور، أو استخدم رمز QR / كود '
            .'الدخول الذي يوفره مسؤول العمارة.');

        $code = $this->issueCode(OtpCode::class, 'phone', $data['phone']);
        $sent = $notifier->sendSmsCode($data['phone'], $code);

        $body = ['sent' => $sent];
        if ($this->exposesDevCode('sms')) {
            $body['dev_code'] = $code;
        }
        abort_if(! $sent && ! isset($body['dev_code']), 503,
            'تعذّر إرسال رمز التحقق حالياً — سجّل الدخول بكلمة المرور، أو استخدم '
            .'رمز QR / كود الدخول من مسؤول العمارة.');

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

    /// Step 1 of password recovery: mail a code to the address.
    ///
    /// The answer is the SAME whether or not an account exists — otherwise this
    /// endpoint becomes a way to enumerate who is registered.
    public function forgotPassword(Request $r, Notifier $notifier)
    {
        $data = $r->validate(['email' => 'required|email']);

        $exists = User::where('email', $data['email'])->whereNotNull('password')->exists();
        $body = ['sent' => true];

        if ($exists) {
            $code = $this->issueCode(EmailCode::class, 'email', $data['email']);
            $notifier->sendEmailCode($data['email'], $code, 'reset');
            if ($this->exposesDevCode('mail')) {
                $body['dev_code'] = $code;
            }
        }

        return response()->json($body);
    }

    /// Step 2: consume the code and set a new password.
    ///
    /// Every existing session of that account is revoked — a reset is what you
    /// do when you fear someone else has the old password, so their tokens must
    /// die with it. One address can belong to accounts in several buildings, so
    /// the caller names which (or is asked).
    public function resetPassword(Request $r)
    {
        $data = $r->validate([
            'email' => 'required|email',
            'code' => 'required|string|max:64',
            'password' => 'required|string|min:6',
            'building_id' => 'nullable|integer',
        ]);

        $q = User::where('email', $data['email'])->whereNotNull('password');
        if (! empty($data['building_id'])) {
            $q->where('building_id', $data['building_id']);
        }
        $accounts = $q->get();

        if ($accounts->isEmpty()) {
            throw ValidationException::withMessages(['email' => ['لا يوجد حساب بهذا البريد']]);
        }
        if ($accounts->count() > 1) {
            // Ask which building BEFORE consuming the code, so the same code
            // still works on the second call.
            return $this->chooseBuilding($accounts);
        }

        $this->consumeEmailCodeOrFail($data['email'], $data['code']);

        $user = $accounts->first();
        $user->tokens()->delete();
        $user->forceFill([
            'password' => Hash::make($data['password']),
            'email_verified_at' => $user->email_verified_at ?? now(),
            // A reset also lifts a disabled flag: it is the owner proving control
            // of the address on file.
            'disabled_at' => null,
        ])->save();

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
