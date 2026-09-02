<?php

namespace App\Http\Controllers;

use App\Models\Building;
use App\Models\Expense;
use App\Models\Payment;
use App\Models\Unit;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

// سكن برو — super-admin (platform owner): create building admins and view a
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
            ->get(['id', 'name', 'email', 'phone', 'role', 'building_id', 'building_key']);
    }

    /// Create a regular building admin (super-admin only).
    public function createAdmin(Request $r)
    {
        $this->requireSuperAdmin($r);
        $data = $r->validate([
            'name' => 'required|string|max:120',
            // Unique within the building this admin will run (the same person
            // may already be an admin or a resident of another building).
            'email' => ['required', 'email',
                Rule::unique('users', 'email')->where('building_id', $r->input('building_id'))],
            'password' => 'required|string|min:8',
            'building_key' => 'required|in:residential,commercial',
            // WHICH building this admin runs. A btype is not a building: several
            // share one, and resolving by type alone made every new admin an admin
            // of building #1 regardless of intent.
            'building_id' => 'nullable|integer|exists:buildings,id',
        ]);

        if (! empty($data['building_id'])) {
            $building = Building::findOrFail($data['building_id']);
        } else {
            // No id given: only safe while the type identifies exactly one
            // building. Otherwise refuse rather than guess.
            $matches = Building::where('key', $data['building_key'])->orderBy('id')->get();
            abort_if($matches->count() > 1, 422,
                'حدّد المبنى — يوجد أكثر من مبنى بهذا النوع');
            $building = $matches->first();
            abort_unless($building, 404, 'لا يوجد مبنى بهذا النوع');
        }

        $user = User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'role' => 'admin',
            'building_id' => $building->id,
            'building_key' => $building->key,
        ]);

        return response()->json(
            $user->only(['id', 'name', 'email', 'role', 'building_id', 'building_key']),
            201,
        );
    }

    /// Global report across all buildings, filterable by ?month= and ?btype=.
    public function globalReport(Request $r)
    {
        $this->requireSuperAdmin($r);
        $month = $r->filled('month') ? (int) $r->query('month') : null;

        // EVERY building — not "the first one of each type". This loop used to run
        // over the two type KEYS and resolve each with idForKey(), so the platform
        // owner's report silently covered 2 buildings no matter how many existed.
        $q = Building::query()->orderBy('id');
        if (in_array($r->query('btype'), ['residential', 'commercial'])) {
            $q->where('key', $r->query('btype'));
        }

        $buildings = [];
        $totCollected = $totExpenses = $totUnits = $totLate = $totOpening = 0;

        foreach ($q->get() as $b) {
            $bid = (int) $b->id;
            $payQ = Payment::where('building_id', $bid);
            if ($month !== null) {
                $payQ->where('month', $month);
            }
            $collected = (int) $payQ->sum('amount');
            $payCount = $payQ->count();
            $expenses = (int) Expense::where('building_id', $bid)->sum('amount');
            // Genesis opening so the per-building balance reflects true cash on
            // hand (consistent with the dashboard's opening + revenue − expenses).
            $opening = (int) (\App\Models\YearSummary::where('building_id', $bid)
                ->orderBy('year')->value('opening_balance') ?? 0);
            // Refresh the cached balance/status first — it drifts stale between
            // writes as dues accrue, so a raw "late" count under-reports.
            Unit::refreshLedgerCache($bid);
            $units = Unit::where('building_id', $bid)->where('status', '!=', 'vacant')->count();
            $late = Unit::where('building_id', $bid)->where('status', 'late')->count();
            $admins = User::where('building_id', $bid)->where('role', 'admin')->count();

            $buildings[] = [
                'id' => $bid,
                'key' => $b->key,
                'name' => $b->name,
                'type' => $b->type,
                'currency' => $b->currency,
                'collected' => $collected,
                'payments' => $payCount,
                'expenses' => $expenses,
                'balance' => $opening + $collected - $expenses,
                'units' => $units,
                'late' => $late,
                'admins' => $admins,
            ];
            $totCollected += $collected;
            $totExpenses += $expenses;
            $totOpening += $opening;
            $totUnits += $units;
            $totLate += $late;
        }

        return response()->json([
            'month' => $month,
            'buildings' => $buildings,
            'totals' => [
                'collected' => $totCollected,
                'expenses' => $totExpenses,
                'balance' => $totOpening + $totCollected - $totExpenses,
                'units' => $totUnits,
                'late' => $totLate,
            ],
        ]);
    }
}
