<?php

namespace App\Http\Controllers;

use App\Models\Building;
use App\Models\Expense;
use App\Models\Payment;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

// عمارتي — super-admin (platform owner): create building admins and view a
// global report across all buildings with filters.
class SuperAdminController extends Controller
{
    private function requireSuperAdmin(Request $r): void
    {
        abort_unless(optional($r->user())->role === 'superadmin', 403,
            'يتطلب صلاحية المدير العام');
    }

    /// List building admins (super-admin only).
    public function admins(Request $r)
    {
        $this->requireSuperAdmin($r);

        return User::where('role', 'admin')
            ->orderBy('building_key')->orderBy('name')
            ->get(['id', 'name', 'email', 'phone', 'role', 'building_key']);
    }

    /// Create a regular building admin (super-admin only).
    public function createAdmin(Request $r)
    {
        $this->requireSuperAdmin($r);
        $data = $r->validate([
            'name' => 'required|string|max:120',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:6',
            'building_key' => 'required|in:residential,commercial',
        ]);

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => 'admin',
            'building_key' => $data['building_key'],
        ]);

        return response()->json(
            $user->only(['id', 'name', 'email', 'role', 'building_key']),
            201,
        );
    }

    /// Global report across all buildings, filterable by ?month= and ?btype=.
    public function globalReport(Request $r)
    {
        $this->requireSuperAdmin($r);
        $month = $r->filled('month') ? (int) $r->query('month') : null;
        $keys = in_array($r->query('btype'), ['residential', 'commercial'])
            ? [$r->query('btype')]
            : ['residential', 'commercial'];

        $buildings = [];
        $totCollected = $totExpenses = $totUnits = $totLate = 0;

        foreach ($keys as $bk) {
            $b = Building::where('key', $bk)->first();
            if (! $b) {
                continue;
            }
            $payQ = Payment::where('building_key', $bk);
            if ($month !== null) {
                $payQ->where('month', $month);
            }
            $collected = (int) $payQ->sum('amount');
            $payCount = $payQ->count();
            $expenses = (int) Expense::where('building_key', $bk)->sum('amount');
            $units = Unit::where('building_key', $bk)->where('status', '!=', 'vacant')->count();
            $late = Unit::where('building_key', $bk)->where('status', 'late')->count();
            $admins = User::where('building_key', $bk)->where('role', 'admin')->count();

            $buildings[] = [
                'key' => $bk,
                'name' => $b->name,
                'type' => $b->type,
                'currency' => $b->currency,
                'collected' => $collected,
                'payments' => $payCount,
                'expenses' => $expenses,
                'balance' => $collected - $expenses,
                'units' => $units,
                'late' => $late,
                'admins' => $admins,
            ];
            $totCollected += $collected;
            $totExpenses += $expenses;
            $totUnits += $units;
            $totLate += $late;
        }

        return response()->json([
            'month' => $month,
            'buildings' => $buildings,
            'totals' => [
                'collected' => $totCollected,
                'expenses' => $totExpenses,
                'balance' => $totCollected - $totExpenses,
                'units' => $totUnits,
                'late' => $totLate,
            ],
        ]);
    }
}
