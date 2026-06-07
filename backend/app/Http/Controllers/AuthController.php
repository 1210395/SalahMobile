<?php

namespace App\Http\Controllers;

use App\Models\OtpCode;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    private function payload(User $user): array
    {
        return [
            'token' => $user->createToken('amarati')->plainTextToken,
            'user' => $user->only(['id', 'name', 'email', 'phone', 'role', 'building_key', 'unit_no']),
        ];
    }

    public function register(Request $r)
    {
        $data = $r->validate([
            'name' => 'required|string|max:120',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:6',
            'building_key' => 'in:residential,commercial',
        ]);
        // SECURITY: role is never accepted from a public endpoint. New accounts
        // are always unprivileged residents; promotion to admin must be done by
        // an existing admin through a separate, authorized flow.
        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => 'resident',
            'building_key' => $data['building_key'] ?? 'residential',
        ]);

        return response()->json($this->payload($user), 201);
    }

    public function login(Request $r)
    {
        $data = $r->validate([
            'email' => 'required|email',
            'password' => 'required|string',
        ]);
        $user = User::where('email', $data['email'])->first();
        if (! $user || ! $user->password || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['email' => ['بيانات الدخول غير صحيحة']]);
        }

        return response()->json($this->payload($user));
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
        if (app()->environment('local') || config('amarati.expose_otp_dev_code')) {
            $body['dev_code'] = $code;
        }

        return response()->json($body);
    }

    public function verifyOtp(Request $r)
    {
        $data = $r->validate([
            'phone' => 'required|string|max:32',
            'code' => 'required|string',
            'building_key' => 'in:residential,commercial',
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
        $otp->update(['used' => true]);

        $user = User::where('phone', $data['phone'])->first();

        // SECURITY: never let an OTP take over a password-protected account
        // (e.g. an admin). Those must authenticate with their password.
        if ($user && $user->password) {
            throw ValidationException::withMessages(
                ['phone' => ['هذا الرقم مرتبط بحساب بكلمة مرور — سجّل الدخول بكلمة المرور']]
            );
        }

        // SECURITY: phone-only accounts are always unprivileged residents; role
        // is server-decided, never client-supplied. building_key only scopes
        // which dataset they see and defaults to residential.
        $user ??= User::create([
            'phone' => $data['phone'],
            'name' => 'مستخدم عمارتي',
            'role' => 'resident',
            'building_key' => $data['building_key'] ?? 'residential',
        ]);

        return response()->json($this->payload($user));
    }

    public function me(Request $r)
    {
        return response()->json([
            'user' => $r->user()->only(['id', 'name', 'email', 'phone', 'role', 'building_key', 'unit_no']),
        ]);
    }

    public function logout(Request $r)
    {
        $r->user()->currentAccessToken()->delete();

        return response()->json(['ok' => true]);
    }
}
