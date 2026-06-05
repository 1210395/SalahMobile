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
            'role' => 'in:admin,resident,guest',
            'building_key' => 'in:residential,commercial',
        ]);
        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => $data['role'] ?? 'resident',
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
        if (! $user || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['email' => ['بيانات الدخول غير صحيحة']]);
        }

        return response()->json($this->payload($user));
    }

    public function requestOtp(Request $r)
    {
        $data = $r->validate(['phone' => 'required|string']);
        $code = str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        OtpCode::create([
            'phone' => $data['phone'],
            'code' => $code,
            'expires_at' => now()->addMinutes(10),
        ]);

        // In production this would be sent over SMS. In local/dev we return it
        // so the flow is testable without an SMS provider.
        $body = ['sent' => true];
        if (app()->environment('local')) {
            $body['dev_code'] = $code;
        }

        return response()->json($body);
    }

    public function verifyOtp(Request $r)
    {
        $data = $r->validate([
            'phone' => 'required|string',
            'code' => 'required|string',
            'role' => 'in:admin,resident,guest',
            'building_key' => 'in:residential,commercial',
        ]);

        $otp = OtpCode::where('phone', $data['phone'])
            ->where('code', $data['code'])
            ->where('used', false)
            ->where('expires_at', '>', now())
            ->latest()
            ->first();

        if (! $otp) {
            throw ValidationException::withMessages(['code' => ['رمز التحقق غير صحيح أو منتهٍ']]);
        }
        $otp->update(['used' => true]);

        $user = User::firstOrCreate(
            ['phone' => $data['phone']],
            [
                'name' => 'مستخدم عمارتي',
                'role' => $data['role'] ?? 'resident',
                'building_key' => $data['building_key'] ?? 'residential',
            ],
        );
        // Honour an explicit role/building choice on subsequent logins.
        if (isset($data['role']) || isset($data['building_key'])) {
            $user->update(array_filter([
                'role' => $data['role'] ?? null,
                'building_key' => $data['building_key'] ?? null,
            ]));
        }

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
